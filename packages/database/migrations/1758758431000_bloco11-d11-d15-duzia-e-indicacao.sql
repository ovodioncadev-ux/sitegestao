-- ═══════════════════════════════════════════════════════════════════════════
-- Bloco 11 — D11 (dúzia pedida pelo assinante) e D15 (bônus de indicação).
--
-- D11  R$ 12,00; só para quem já recebe pente; não aparece no site público. O assinante PEDE na
--      área dele, o dono APROVA; vale a partir da próxima entrega depois do corte (D9).
-- D15  o indicado tem os mesmos 10% do 1º mês de todo mundo; o INDICADOR ganha 10% na fatura do mês
--      em que uma pessoa indicada por ele pagou a 1ª fatura. Duas indicações no mesmo mês continuam
--      10%, e os percentuais nunca se somam (D15c: vale o maior).
--
-- Interpretações (a confirmar; ver DECISOES.md):
--   • fatura já emitida não é refeita quando entra a dúzia: vale a partir da próxima fatura;
--   • o bônus vale na 1ª fatura do indicador cujo período é do mês do pagamento do indicado ou
--     posterior (se a fatura do mês já saiu, vale na seguinte; não há devolução);
--   • o bônus só é concedido a indicador com assinatura ativa e só se for MAIOR que o 1º mês
--     do próprio indicador (empate: fica para a próxima fatura);
--   • fatura cancelada devolve o bônus.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

alter type tipo_solicitacao add value if not exists 'duzia';
alter table solicitacoes_assinatura
  add column duzias_pedidas smallint check (duzias_pedidas is null or duzias_pedidas between 0 and 50);

-- D11: R$ 12,00 (só onde ainda não havia preço) e D15: 10% para o indicador (só onde estava zerado).
update config_negocio set preco_duzia_centavos = 1200 where preco_duzia_centavos = 0;
update config_negocio set bonus_indicador_pct = 10 where bonus_indicador_pct = 0;
alter table config_negocio alter column bonus_indicador_pct set default 10;
comment on column config_negocio.bonus_indicador_pct is
  'D15: desconto do INDICADOR na fatura do mês em que um indicado paga a 1ª fatura. Não soma com o 1º mês (vale o maior).';

-- ───────────────────────────────────────────────────────────────────────────
-- Livro dos bônus de indicação
-- ───────────────────────────────────────────────────────────────────────────
create table bonus_indicacao (
  id           uuid primary key default gen_random_uuid(),
  indicador_id uuid not null references clientes (id) on delete restrict,
  indicado_id  uuid not null references clientes (id) on delete restrict unique,
  mes          date not null check (extract(day from mes) = 1),
  status       text not null default 'pendente' check (status in ('pendente', 'aplicado')),
  fatura_id    uuid references faturas (id) on delete restrict,
  criado_em    timestamptz not null default now(),
  check ((status = 'aplicado') = (fatura_id is not null)),
  check (indicador_id <> indicado_id)
);
create index bonus_indicacao_indicador_idx on bonus_indicacao (indicador_id, status);

comment on table bonus_indicacao is
  'D15: um bônus por indicado (o que pagou a 1ª fatura). Pendente até entrar numa fatura do indicador; só as funções do banco escrevem.';

alter table bonus_indicacao enable row level security;
revoke all on table bonus_indicacao from app_anon, app_usuario;
grant select on table bonus_indicacao to app_usuario;
create policy "bonus: dono le tudo, indicador os proprios"
  on bonus_indicacao for select to app_usuario
  using (
    (select sou_dono())
    or exists (select 1 from clientes c where c.id = bonus_indicacao.indicador_id and c.usuario_id = app.usuario_id())
  );

-- Pagou a 1ª fatura de um indicado → o indicador (se tem assinatura ativa) ganha o bônus.
create function faturas_conceder_bonus_indicacao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ind uuid;
begin
  select indicado_por into v_ind from clientes where id = new.cliente_id;
  if v_ind is null or v_ind = new.cliente_id then
    return null;
  end if;
  -- Só a PRIMEIRA fatura paga do indicado conta (nova assinatura).
  if exists (select 1 from faturas where cliente_id = new.cliente_id and status = 'paga' and id <> new.id) then
    return null;
  end if;
  if not exists (select 1 from assinaturas where cliente_id = v_ind and status = 'ativa') then
    return null;
  end if;
  insert into bonus_indicacao (indicador_id, indicado_id, mes)
  values (v_ind, new.cliente_id, date_trunc('month', coalesce(new.data_pagamento, hoje_sp()))::date)
  on conflict (indicado_id) do nothing;
  return null;
end;
$$;
revoke execute on function faturas_conceder_bonus_indicacao() from public;

create trigger faturas_conceder_bonus_indicacao_tg
  after update of status on faturas
  for each row
  when (old.status in ('pendente', 'atrasada') and new.status = 'paga')
  execute function faturas_conceder_bonus_indicacao();


-- ───────────────────────────────────────────────────────────────────────────
-- A conta da fatura passa a conhecer o bônus
-- ───────────────────────────────────────────────────────────────────────────
drop function if exists inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer, integer, smallint);
drop function if exists calcular_detalhe_fatura(uuid, integer, smallint);

create function calcular_detalhe_fatura(p_assinatura uuid, p_entregas integer default null, p_plano smallint default null, p_mes date default null)
returns table (
  regra                 text,
  plano_id              smallint,
  plano_frequencia      frequencia_plano,
  plano_nome            text,
  preco_plano_centavos  integer,
  entregas              smallint,
  pentes_por_entrega    smallint,
  duzias_por_entrega    smallint,
  valor_pente_centavos  integer,
  valor_duzia_centavos  integer,
  valor_entrega_centavos integer,
  valor_bruto_centavos  integer,
  desconto_pct          numeric,
  desconto_centavos     integer,
  desconto_origem       text,
  credito_centavos      integer,
  valor_final_centavos  integer
)
language plpgsql
stable
set search_path = public
as $$
declare
  v_ass     assinaturas%rowtype;
  v_plano   planos%rowtype;
  v_cli     clientes%rowtype;
  v_cfg     config_negocio%rowtype;
  v_pentes  integer;
  v_duzias  integer;
  v_entrega integer;
  v_n       integer;
  v_bruto   integer;
  v_pct     numeric := 0;
  v_cred    integer := 0;
  v_final   integer;
  v_origem  text;
  v_bonus   numeric := 0;
begin
  select * into v_ass from assinaturas where id = p_assinatura;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  select * into v_plano from planos where id = coalesce(p_plano, v_ass.plano_id);
  select * into v_cli   from clientes where id = v_ass.cliente_id;
  select * into v_cfg   from config_negocio where id = 1;

  v_n       := coalesce(p_entregas, v_plano.entregas_por_mes);
  v_pentes  := coalesce(v_cli.pentes_padrao, 1);
  v_duzias  := coalesce(v_cli.duzias_padrao, 0);
  v_entrega := v_pentes * v_cfg.preco_pente_centavos + v_duzias * v_cfg.preco_duzia_centavos;
  v_bruto   := v_entrega * v_n;
  v_final   := v_bruto;

  if v_cli.desconto_primeiro_mes_aplicavel
     and v_plano.desconto_primeiro_mes_pct > 0
     and not exists (select 1 from faturas where cliente_id = v_cli.id and status <> 'cancelada')
  then
    v_pct    := v_plano.desconto_primeiro_mes_pct;
    v_origem := 'primeiro_mes';
    v_final  := round(v_bruto::numeric * (100 - v_pct) / 100)::integer;
  end if;

  -- D15: o INDICADOR ganha bonus_indicador_pct na fatura do mês em que um indicado pagou a 1ª fatura.
  -- Só em fatura com período (p_mes) e só se maior que o 1º mês: os percentuais NÃO se somam.
  if p_mes is not null and v_cfg.bonus_indicador_pct > v_pct
     and exists (select 1 from bonus_indicacao b
                  where b.indicador_id = v_cli.id and b.status = 'pendente'
                    and b.mes <= date_trunc('month', p_mes)::date)
  then
    v_bonus  := v_cfg.bonus_indicador_pct;
    v_pct    := v_bonus;
    v_origem := 'indicacao';
    v_final  := round(v_bruto::numeric * (100 - v_pct) / 100)::integer;
  end if;

  -- D15c: ou desconto percentual, ou crédito. O percentual vence; o crédito espera a próxima fatura.
  -- O crédito nunca zera a fatura (sobra no mínimo R$ 1,00).
  if v_pct = 0 then
    v_cred  := least(greatest(saldo_credito(p_assinatura), 0), greatest(v_bruto - 100, 0));
    v_final := v_bruto - v_cred;
  end if;

  return query select
    case when p_entregas is null then 'mensalidade-fixa-v1' else 'calendario-v1' end,
    v_plano.id,
    v_plano.frequencia,
    v_plano.nome,
    (v_cfg.preco_pente_centavos * v_plano.entregas_por_mes)::integer,
    v_n::smallint,
    v_pentes::smallint,
    v_duzias::smallint,
    v_cfg.preco_pente_centavos,
    v_cfg.preco_duzia_centavos,
    v_entrega,
    v_bruto,
    v_pct,
    v_bruto - (case when v_pct > 0 then v_final else v_bruto end),
    v_origem,
    v_cred,
    v_final;
end;
$$;
revoke execute on function calcular_detalhe_fatura(uuid, integer, smallint, date) from public;

create function inserir_fatura_com_snapshot(
  p_assinatura      uuid,
  p_vencimento      date,
  p_status          status_fatura,
  p_periodo_inicio  date,
  p_periodo_fim     date,
  p_observacao      text,
  p_valor_informado integer default null,
  p_entregas        integer default null,
  p_plano           smallint default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass   assinaturas%rowtype;
  v_d     record;
  v_valor integer;
  v_cred  integer;
  v_id    uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;

  select * into v_d from calcular_detalhe_fatura(p_assinatura, p_entregas, p_plano, p_periodo_inicio);
  v_valor := coalesce(p_valor_informado, v_d.valor_final_centavos);
  -- Valor informado à mão não consome crédito.
  v_cred  := case when p_valor_informado is null then v_d.credito_centavos else 0 end;

  if v_valor <= 0 then
    raise exception 'O valor da fatura precisa ser maior que zero.' using errcode = 'OV001';
  end if;

  insert into faturas (
    cliente_id, assinatura_id, valor_centavos, vencimento, status,
    periodo_inicio, periodo_fim, observacao,
    calculo_regra, calculado_em, calculo_plano_id, calculo_plano_frequencia, calculo_plano_nome,
    calculo_preco_plano_centavos, calculo_entregas, calculo_pentes_por_entrega, calculo_duzias_por_entrega,
    calculo_valor_pente_centavos, calculo_valor_duzia_centavos, calculo_valor_entrega_centavos,
    calculo_valor_bruto_centavos, calculo_desconto_pct, calculo_desconto_centavos, calculo_desconto_origem,
    calculo_credito_centavos, calculo_ajuste_centavos
  )
  values (
    v_ass.cliente_id, p_assinatura, v_valor, p_vencimento, p_status,
    p_periodo_inicio, p_periodo_fim, p_observacao,
    v_d.regra, now(), v_d.plano_id, v_d.plano_frequencia, v_d.plano_nome,
    v_d.preco_plano_centavos, v_d.entregas, v_d.pentes_por_entrega, v_d.duzias_por_entrega,
    v_d.valor_pente_centavos, v_d.valor_duzia_centavos, v_d.valor_entrega_centavos,
    v_d.valor_bruto_centavos, v_d.desconto_pct, v_d.desconto_centavos, v_d.desconto_origem,
    v_cred,
    v_valor - (v_d.valor_bruto_centavos - v_d.desconto_centavos - v_cred)
  )
  returning id into v_id;

  -- D15: o bônus de indicação usado nesta fatura fica gasto (volta se a fatura for cancelada).
  if v_d.desconto_origem = 'indicacao' and p_valor_informado is null then
    update bonus_indicacao
       set status = 'aplicado', fatura_id = v_id
     where indicador_id = v_ass.cliente_id and status = 'pendente'
       and mes <= date_trunc('month', p_periodo_inicio)::date;
  end if;

  if v_cred > 0 then
    insert into creditos_assinatura (assinatura_id, cliente_id, valor_centavos, origem, fatura_id)
    values (p_assinatura, v_ass.cliente_id, -v_cred, 'uso_em_fatura', v_id);
  end if;

  return v_id;
end;
$$;
revoke execute on function inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer, integer, smallint) from public;

create or replace function faturas_devolver_credito()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update bonus_indicacao set status = 'pendente', fatura_id = null where fatura_id = new.id and status = 'aplicado';
  if new.calculo_credito_centavos > 0 and new.assinatura_id is not null then
    insert into creditos_assinatura (assinatura_id, cliente_id, valor_centavos, origem, fatura_id, observacao)
    values (new.assinatura_id, new.cliente_id, new.calculo_credito_centavos, 'fatura_cancelada', new.id,
            'Fatura cancelada: crédito devolvido');
  end if;
  return null;
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- D11 — aplicar a dúzia
-- ───────────────────────────────────────────────────────────────────────────
create function aplicar_duzias(p_assinatura uuid, p_duzias smallint)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_ass    assinaturas%rowtype;
  v_quarta date := primeira_quarta_apos_corte(now());
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' then
    raise exception 'Só assinaturas ativas podem mudar as dúzias.' using errcode = 'OV001';
  end if;
  if p_duzias is null or p_duzias < 0 or p_duzias > 50 then
    raise exception 'Quantidade de dúzias inválida (0 a 50).' using errcode = 'OV001';
  end if;

  perform set_config('app.motivo', 'Dúzias por entrega: ' || p_duzias, true);
  update clientes set duzias_padrao = p_duzias where id = v_ass.cliente_id;
  -- Vale a partir da próxima entrega depois do corte (D9); as anteriores não mudam.
  update entregas set duzias = p_duzias
   where assinatura_id = p_assinatura and status = 'pendente' and data_prevista >= v_quarta;
  perform set_config('app.motivo', '', true);
end;
$$;
comment on function aplicar_duzias(uuid, smallint) is
  'D11: grava as dúzias por entrega do cliente e ajusta as entregas pendentes a partir da 1ª quarta que o corte permite.';
revoke execute on function aplicar_duzias(uuid, smallint) from public;

drop function if exists solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text, text, smallint);

create function solicitar_alteracao_assinatura(
  p_assinatura    uuid,
  p_tipo          tipo_solicitacao,
  p_motivo        text default null,
  p_preferencia   text default null,
  p_plano_destino smallint default null,
  p_duzias        smallint default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ass assinaturas%rowtype;
  v_id  uuid;
begin
  -- SEMPRE a primeira instrução: a assinatura tem que ser do próprio chamador.
  select a.* into v_ass
    from assinaturas a
    join clientes c on c.id = a.cliente_id
   where a.id = p_assinatura
     and c.usuario_id = app.usuario_id();

  if not found then
    raise exception 'Você não tem permissão para realizar esta ação.' using errcode = 'OV001';
  end if;

  if p_tipo = 'pausa' and v_ass.status <> 'ativa' then
    raise exception 'Só uma assinatura ativa pode ser pausada.' using errcode = 'OV001';
  end if;
  if p_tipo = 'cancelamento' and v_ass.status not in ('ativa', 'pausada') then
    raise exception 'Esta assinatura não pode ser cancelada.' using errcode = 'OV001';
  end if;
  if p_tipo::text = 'troca_plano' then
    if v_ass.status <> 'ativa' then
      raise exception 'Só uma assinatura ativa pode trocar de plano.' using errcode = 'OV001';
    end if;
    if p_plano_destino is null or not exists (select 1 from planos where id = p_plano_destino and ativo)
       or p_plano_destino = v_ass.plano_id then
      raise exception 'Escolha um plano diferente do atual.' using errcode = 'OV001';
    end if;
  end if;
  if p_tipo::text = 'duzia' then
    if v_ass.status <> 'ativa' then
      raise exception 'Só uma assinatura ativa pode pedir dúzia.' using errcode = 'OV001';
    end if;
    if p_duzias is null or p_duzias < 0 or p_duzias > 50 then
      raise exception 'Informe quantas dúzias por entrega (de 0 a 50).' using errcode = 'OV001';
    end if;
    -- D11: só quem já recebe pente.
    if not exists (select 1 from clientes c where c.id = v_ass.cliente_id and coalesce(c.pentes_padrao, 1) >= 1) then
      raise exception 'A dúzia é um complemento para quem já recebe pente.' using errcode = 'OV001';
    end if;
    if p_duzias is not distinct from (select coalesce(c.duzias_padrao, 0)::smallint from clientes c where c.id = v_ass.cliente_id) then
      raise exception 'Você já recebe essa quantidade de dúzias.' using errcode = 'OV001';
    end if;
  end if;
  if p_preferencia is not null and p_preferencia not in ('credito', 'pentes') then
    raise exception 'Escolha crédito ou pentes depois.' using errcode = 'OV001';
  end if;

  insert into solicitacoes_assinatura (assinatura_id, cliente_id, tipo, motivo, preferencia, plano_destino_id, duzias_pedidas)
  values (p_assinatura, v_ass.cliente_id, p_tipo, nullif(trim(p_motivo), ''),
          case when p_tipo = 'pausa' then coalesce(p_preferencia, 'credito') end,
          case when p_tipo::text = 'troca_plano' then p_plano_destino end,
          case when p_tipo::text = 'duzia' then p_duzias end)
  returning id into v_id;

  return v_id;
end;
$$;
comment on function solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text, text, smallint, smallint) is
  'O assinante pede pausa, cancelamento, troca de plano ou dúzias da PRÓPRIA assinatura. Quem executa é o dono.';
revoke execute on function solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text, text, smallint, smallint) from public;
grant  execute on function solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text, text, smallint, smallint) to app_usuario;

create or replace function resolver_solicitacao(
  p_solicitacao      uuid,
  p_status           status_solicitacao,
  p_resposta         text default null,
  p_executar         boolean default false,
  p_retorno_previsto date default null
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_s solicitacoes_assinatura%rowtype;
begin
  select * into v_s from solicitacoes_assinatura where id = p_solicitacao for update;
  if not found then
    raise exception 'Pedido não encontrado.' using errcode = 'OV001';
  end if;
  if v_s.status <> 'pendente' then
    raise exception 'Este pedido já foi respondido.' using errcode = 'OV001';
  end if;
  if p_status not in ('atendida', 'recusada') then
    raise exception 'Resposta inválida.' using errcode = 'OV001';
  end if;

  if p_status = 'atendida' and p_executar then
    if v_s.tipo = 'pausa' then
      perform pausar_assinatura(v_s.assinatura_id,
        left('Pedido do assinante' || coalesce(': ' || v_s.motivo, ''), 500), p_retorno_previsto,
        coalesce(v_s.preferencia, 'credito'));
    elsif v_s.tipo::text = 'duzia' then
      perform aplicar_duzias(v_s.assinatura_id, v_s.duzias_pedidas);
    elsif v_s.tipo::text = 'troca_plano' then
      perform alterar_plano_assinatura(v_s.assinatura_id, v_s.plano_destino_id);
    else
      perform cancelar_assinatura(v_s.assinatura_id,
        left('Pedido do assinante' || coalesce(': ' || v_s.motivo, ''), 500));
    end if;
  end if;

  update solicitacoes_assinatura
     set status = p_status, resolvida_em = now(),
         resolvida_por = nullif(current_setting('app.usuario_id', true), ''),
         resposta = nullif(trim(p_resposta), '')
   where id = p_solicitacao;
end;
$$;


-- Down Migration

drop trigger if exists faturas_conceder_bonus_indicacao_tg on faturas;
drop function if exists faturas_conceder_bonus_indicacao();

-- Volta às funções do Bloco 10. (O valor 'duzia' do enum tipo_solicitacao fica sem uso.)
drop function if exists solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text, text, smallint, smallint);
create function solicitar_alteracao_assinatura(
  p_assinatura    uuid,
  p_tipo          tipo_solicitacao,
  p_motivo        text default null,
  p_preferencia   text default null,
  p_plano_destino smallint default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ass assinaturas%rowtype;
  v_id  uuid;
begin
  -- SEMPRE a primeira instrução: a assinatura tem que ser do próprio chamador.
  select a.* into v_ass
    from assinaturas a
    join clientes c on c.id = a.cliente_id
   where a.id = p_assinatura
     and c.usuario_id = app.usuario_id();

  if not found then
    raise exception 'Você não tem permissão para realizar esta ação.' using errcode = 'OV001';
  end if;

  if p_tipo = 'pausa' and v_ass.status <> 'ativa' then
    raise exception 'Só uma assinatura ativa pode ser pausada.' using errcode = 'OV001';
  end if;
  if p_tipo = 'cancelamento' and v_ass.status not in ('ativa', 'pausada') then
    raise exception 'Esta assinatura não pode ser cancelada.' using errcode = 'OV001';
  end if;
  if p_tipo::text = 'troca_plano' then
    if v_ass.status <> 'ativa' then
      raise exception 'Só uma assinatura ativa pode trocar de plano.' using errcode = 'OV001';
    end if;
    if p_plano_destino is null or not exists (select 1 from planos where id = p_plano_destino and ativo)
       or p_plano_destino = v_ass.plano_id then
      raise exception 'Escolha um plano diferente do atual.' using errcode = 'OV001';
    end if;
  end if;
  if p_preferencia is not null and p_preferencia not in ('credito', 'pentes') then
    raise exception 'Escolha crédito ou pentes depois.' using errcode = 'OV001';
  end if;

  insert into solicitacoes_assinatura (assinatura_id, cliente_id, tipo, motivo, preferencia, plano_destino_id)
  values (p_assinatura, v_ass.cliente_id, p_tipo, nullif(trim(p_motivo), ''),
          case when p_tipo = 'pausa' then coalesce(p_preferencia, 'credito') end,
          case when p_tipo::text = 'troca_plano' then p_plano_destino end)
  returning id into v_id;

  return v_id;
end;
$$;
revoke execute on function solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text, text, smallint) from public;
grant  execute on function solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text, text, smallint) to app_usuario;

create or replace function resolver_solicitacao(
  p_solicitacao      uuid,
  p_status           status_solicitacao,
  p_resposta         text default null,
  p_executar         boolean default false,
  p_retorno_previsto date default null
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_s solicitacoes_assinatura%rowtype;
begin
  select * into v_s from solicitacoes_assinatura where id = p_solicitacao for update;
  if not found then
    raise exception 'Pedido não encontrado.' using errcode = 'OV001';
  end if;
  if v_s.status <> 'pendente' then
    raise exception 'Este pedido já foi respondido.' using errcode = 'OV001';
  end if;
  if p_status not in ('atendida', 'recusada') then
    raise exception 'Resposta inválida.' using errcode = 'OV001';
  end if;

  if p_status = 'atendida' and p_executar then
    if v_s.tipo = 'pausa' then
      perform pausar_assinatura(v_s.assinatura_id,
        left('Pedido do assinante' || coalesce(': ' || v_s.motivo, ''), 500), p_retorno_previsto,
        coalesce(v_s.preferencia, 'credito'));
    elsif v_s.tipo::text = 'troca_plano' then
      perform alterar_plano_assinatura(v_s.assinatura_id, v_s.plano_destino_id);
    else
      perform cancelar_assinatura(v_s.assinatura_id,
        left('Pedido do assinante' || coalesce(': ' || v_s.motivo, ''), 500));
    end if;
  end if;

  update solicitacoes_assinatura
     set status = p_status, resolvida_em = now(),
         resolvida_por = nullif(current_setting('app.usuario_id', true), ''),
         resposta = nullif(trim(p_resposta), '')
   where id = p_solicitacao;
end;
$$;

drop function if exists aplicar_duzias(uuid, smallint);

drop function if exists inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer, integer, smallint);
drop function if exists calcular_detalhe_fatura(uuid, integer, smallint, date);
create function calcular_detalhe_fatura(p_assinatura uuid, p_entregas integer default null, p_plano smallint default null)
returns table (
  regra                 text,
  plano_id              smallint,
  plano_frequencia      frequencia_plano,
  plano_nome            text,
  preco_plano_centavos  integer,
  entregas              smallint,
  pentes_por_entrega    smallint,
  duzias_por_entrega    smallint,
  valor_pente_centavos  integer,
  valor_duzia_centavos  integer,
  valor_entrega_centavos integer,
  valor_bruto_centavos  integer,
  desconto_pct          numeric,
  desconto_centavos     integer,
  desconto_origem       text,
  credito_centavos      integer,
  valor_final_centavos  integer
)
language plpgsql
stable
set search_path = public
as $$
declare
  v_ass     assinaturas%rowtype;
  v_plano   planos%rowtype;
  v_cli     clientes%rowtype;
  v_cfg     config_negocio%rowtype;
  v_pentes  integer;
  v_duzias  integer;
  v_entrega integer;
  v_n       integer;
  v_bruto   integer;
  v_pct     numeric := 0;
  v_cred    integer := 0;
  v_final   integer;
  v_origem  text;
begin
  select * into v_ass from assinaturas where id = p_assinatura;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  select * into v_plano from planos where id = coalesce(p_plano, v_ass.plano_id);
  select * into v_cli   from clientes where id = v_ass.cliente_id;
  select * into v_cfg   from config_negocio where id = 1;

  v_n       := coalesce(p_entregas, v_plano.entregas_por_mes);
  v_pentes  := coalesce(v_cli.pentes_padrao, 1);
  v_duzias  := coalesce(v_cli.duzias_padrao, 0);
  v_entrega := v_pentes * v_cfg.preco_pente_centavos + v_duzias * v_cfg.preco_duzia_centavos;
  v_bruto   := v_entrega * v_n;
  v_final   := v_bruto;

  if v_cli.desconto_primeiro_mes_aplicavel
     and v_plano.desconto_primeiro_mes_pct > 0
     and not exists (select 1 from faturas where cliente_id = v_cli.id and status <> 'cancelada')
  then
    v_pct    := v_plano.desconto_primeiro_mes_pct;
    v_origem := 'primeiro_mes';
    v_final  := round(v_bruto::numeric * (100 - v_pct) / 100)::integer;
  end if;

  -- D15c: ou desconto percentual, ou crédito. O percentual vence; o crédito espera a próxima fatura.
  -- O crédito nunca zera a fatura (sobra no mínimo R$ 1,00).
  if v_pct = 0 then
    v_cred  := least(greatest(saldo_credito(p_assinatura), 0), greatest(v_bruto - 100, 0));
    v_final := v_bruto - v_cred;
  end if;

  return query select
    case when p_entregas is null then 'mensalidade-fixa-v1' else 'calendario-v1' end,
    v_plano.id,
    v_plano.frequencia,
    v_plano.nome,
    (v_cfg.preco_pente_centavos * v_plano.entregas_por_mes)::integer,
    v_n::smallint,
    v_pentes::smallint,
    v_duzias::smallint,
    v_cfg.preco_pente_centavos,
    v_cfg.preco_duzia_centavos,
    v_entrega,
    v_bruto,
    v_pct,
    v_bruto - (case when v_pct > 0 then v_final else v_bruto end),
    v_origem,
    v_cred,
    v_final;
end;
$$;
revoke execute on function calcular_detalhe_fatura(uuid, integer, smallint) from public;
create function inserir_fatura_com_snapshot(
  p_assinatura      uuid,
  p_vencimento      date,
  p_status          status_fatura,
  p_periodo_inicio  date,
  p_periodo_fim     date,
  p_observacao      text,
  p_valor_informado integer default null,
  p_entregas        integer default null,
  p_plano           smallint default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass   assinaturas%rowtype;
  v_d     record;
  v_valor integer;
  v_cred  integer;
  v_id    uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;

  select * into v_d from calcular_detalhe_fatura(p_assinatura, p_entregas, p_plano);
  v_valor := coalesce(p_valor_informado, v_d.valor_final_centavos);
  -- Valor informado à mão não consome crédito.
  v_cred  := case when p_valor_informado is null then v_d.credito_centavos else 0 end;

  if v_valor <= 0 then
    raise exception 'O valor da fatura precisa ser maior que zero.' using errcode = 'OV001';
  end if;

  insert into faturas (
    cliente_id, assinatura_id, valor_centavos, vencimento, status,
    periodo_inicio, periodo_fim, observacao,
    calculo_regra, calculado_em, calculo_plano_id, calculo_plano_frequencia, calculo_plano_nome,
    calculo_preco_plano_centavos, calculo_entregas, calculo_pentes_por_entrega, calculo_duzias_por_entrega,
    calculo_valor_pente_centavos, calculo_valor_duzia_centavos, calculo_valor_entrega_centavos,
    calculo_valor_bruto_centavos, calculo_desconto_pct, calculo_desconto_centavos, calculo_desconto_origem,
    calculo_credito_centavos, calculo_ajuste_centavos
  )
  values (
    v_ass.cliente_id, p_assinatura, v_valor, p_vencimento, p_status,
    p_periodo_inicio, p_periodo_fim, p_observacao,
    v_d.regra, now(), v_d.plano_id, v_d.plano_frequencia, v_d.plano_nome,
    v_d.preco_plano_centavos, v_d.entregas, v_d.pentes_por_entrega, v_d.duzias_por_entrega,
    v_d.valor_pente_centavos, v_d.valor_duzia_centavos, v_d.valor_entrega_centavos,
    v_d.valor_bruto_centavos, v_d.desconto_pct, v_d.desconto_centavos, v_d.desconto_origem,
    v_cred,
    v_valor - (v_d.valor_bruto_centavos - v_d.desconto_centavos - v_cred)
  )
  returning id into v_id;

  if v_cred > 0 then
    insert into creditos_assinatura (assinatura_id, cliente_id, valor_centavos, origem, fatura_id)
    values (p_assinatura, v_ass.cliente_id, -v_cred, 'uso_em_fatura', v_id);
  end if;

  return v_id;
end;
$$;
revoke execute on function inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer, integer, smallint) from public;
create or replace function faturas_devolver_credito()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.calculo_credito_centavos > 0 and new.assinatura_id is not null then
    insert into creditos_assinatura (assinatura_id, cliente_id, valor_centavos, origem, fatura_id, observacao)
    values (new.assinatura_id, new.cliente_id, new.calculo_credito_centavos, 'fatura_cancelada', new.id,
            'Fatura cancelada: crédito devolvido');
  end if;
  return null;
end;
$$;

drop table if exists bonus_indicacao;
alter table config_negocio alter column bonus_indicador_pct set default 0;
alter table solicitacoes_assinatura drop column if exists duzias_pedidas;
