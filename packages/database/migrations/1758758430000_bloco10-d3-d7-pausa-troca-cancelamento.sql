-- ═══════════════════════════════════════════════════════════════════════════
-- Bloco 10 — D3 a D7: pausa com crédito, troca de plano e cancelamento no fim do mês.
--
-- D7  cancelar vale no FIM DO MÊS PAGO (as entregas continuam até lá; sem fatura nova).
-- D5  pausa de no máximo 60 dias; passou disso o DONO é avisado no painel e decide.
-- D3  na pausa, as entregas pagas e não feitas viram CRÉDITO na próxima fatura (padrão)
--     ou o cliente RECEBE OS PENTES DEPOIS (na 1ª entrega após o retorno).
-- D4  pausa com fatura em aberto do mês: a fatura é reduzida às entregas FEITAS.
-- D6  troca de plano: AUMENTO vale na hora (fatura de diferença); REDUÇÃO vale no mês seguinte.
-- D15c uma fatura recebe ou desconto percentual ou crédito em reais (o % vence; o crédito espera).
--
-- Interpretações (a confirmar; ver DECISOES.md):
--   • crédito = entregas do calendário que caem na pausa dentro de períodos JÁ PAGOS × valor da
--     entrega congelado na fatura paga (sem refazer o desconto do 1º mês);
--   • o crédito nunca zera uma fatura: sobra no mínimo R$ 1,00 a pagar (a fatura precisa ser > 0);
--     o resto do crédito segue para a fatura seguinte;
--   • "pentes depois" = os pentes/dúzias devidos vão junto da 1ª entrega após o retorno (máx. 50);
--   • D4 vale para a fatura em aberto (pendente ou atrasada) cujo período contém a data da pausa;
--   • cancelar uma assinatura PAUSADA, aguardando 1º pagamento ou bloqueada é imediato;
--   • no aumento de plano, faturas futuras ainda não pagas são refeitas pelo plano novo.
--
-- Não reescreve fatura, entrega ou pausa existente.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

alter table config_negocio
  add column dias_max_pausa integer not null default 60 check (dias_max_pausa between 1 and 365);
comment on column config_negocio.dias_max_pausa is
  'D5: duração máxima de uma pausa. Passou disso, o dono é avisado no painel (nada acontece sozinho).';

alter table assinaturas
  add column cancelamento_agendado_para date,
  add column cancelamento_agendado_motivo text check (char_length(cancelamento_agendado_motivo) <= 500),
  add column plano_proximo_id smallint references planos (id),
  add column plano_proximo_a_partir_de date,
  add constraint assinaturas_troca_agendada_completa
    check ((plano_proximo_id is null) = (plano_proximo_a_partir_de is null));
comment on column assinaturas.cancelamento_agendado_para is
  'D7: último dia pago. A rotina cancela no dia seguinte. Nulo = sem cancelamento agendado.';
comment on column assinaturas.plano_proximo_id is
  'D6: plano que passa a valer em plano_proximo_a_partir_de (redução de plano vale no mês seguinte).';

alter table pausas_assinatura
  add column destino_credito text not null default 'credito' check (destino_credito in ('credito', 'pentes')),
  add column entregas_pagas_nao_feitas smallint not null default 0 check (entregas_pagas_nao_feitas >= 0),
  add column credito_centavos integer not null default 0 check (credito_centavos >= 0),
  add column pentes_a_repor smallint not null default 0 check (pentes_a_repor >= 0),
  add column duzias_a_repor smallint not null default 0 check (duzias_a_repor >= 0);

alter table solicitacoes_assinatura
  add column preferencia text check (preferencia is null or preferencia in ('credito', 'pentes')),
  add column plano_destino_id smallint references planos (id);

alter type tipo_solicitacao add value if not exists 'troca_plano';


-- ───────────────────────────────────────────────────────────────────────────
-- Livro de créditos: + concede, − usa em fatura. Saldo = soma.
-- ───────────────────────────────────────────────────────────────────────────
create table creditos_assinatura (
  id             uuid primary key default gen_random_uuid(),
  assinatura_id  uuid not null references assinaturas (id) on delete restrict,
  cliente_id     uuid not null references clientes (id)    on delete restrict,
  valor_centavos integer not null check (valor_centavos <> 0),
  origem         text not null check (origem in ('pausa', 'uso_em_fatura', 'fatura_cancelada', 'fatura_reduzida')),
  pausa_id       uuid references pausas_assinatura (id) on delete restrict,
  fatura_id      uuid references faturas (id) on delete restrict,
  observacao     text check (char_length(observacao) <= 500),
  criado_em      timestamptz not null default now()
);
create index creditos_assinatura_idx on creditos_assinatura (assinatura_id);

comment on table creditos_assinatura is
  'Livro-razão do crédito em reais (D3): + concedido (pausa, fatura cancelada/reduzida), − usado em fatura. Nunca é apagado; só as funções do banco escrevem.';

alter table creditos_assinatura enable row level security;
revoke all on table creditos_assinatura from app_anon, app_usuario;
grant select on table creditos_assinatura to app_usuario;
create policy "creditos: dono le tudo, assinante os proprios"
  on creditos_assinatura for select to app_usuario
  using (
    (select sou_dono())
    or exists (select 1 from clientes c where c.id = creditos_assinatura.cliente_id and c.usuario_id = app.usuario_id())
  );

create or replace function saldo_credito(p_assinatura uuid)
returns integer
language sql
stable
set search_path = public
as $$
  select coalesce(sum(valor_centavos), 0)::integer from creditos_assinatura where assinatura_id = p_assinatura;
$$;
revoke execute on function saldo_credito(uuid) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- D15c — a conta da fatura passa a abater crédito (e aceita plano de referência)
-- ───────────────────────────────────────────────────────────────────────────
drop function if exists calcular_detalhe_fatura(uuid, integer);

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

drop function if exists inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer, integer);

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

-- Fatura cancelada devolve o crédito que consumiu.
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
revoke execute on function faturas_devolver_credito() from public;

create trigger faturas_devolver_credito_tg
  after update of status on faturas
  for each row
  when (old.status in ('pendente', 'atrasada') and new.status = 'cancelada')
  execute function faturas_devolver_credito();


-- ───────────────────────────────────────────────────────────────────────────
-- D7 — cancelamento no fim do mês pago
-- ───────────────────────────────────────────────────────────────────────────

-- O cancelamento de verdade (o que cancelar_assinatura fazia até agora).
create function cancelar_assinatura_agora(p_assinatura uuid, p_motivo text default null)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_ass assinaturas%rowtype;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status not in ('ativa', 'pausada') then
    raise exception 'Só assinaturas ativas ou pausadas podem ser canceladas.' using errcode = 'OV001';
  end if;

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);

  update assinaturas
     set status = 'cancelada',
         data_cancelamento = hoje_sp(),
         motivo_cancelamento = nullif(trim(p_motivo), ''),
         cancelamento_agendado_para = null, cancelamento_agendado_motivo = null,
         plano_proximo_id = null, plano_proximo_a_partir_de = null
   where id = p_assinatura;
  perform cancelar_pendencias_da_assinatura(p_assinatura, 'assinatura cancelada');
  update clientes set status = 'cancelado' where id = v_ass.cliente_id;

  perform set_config('app.motivo', '', true);
end;
$$;
comment on function cancelar_assinatura_agora(uuid, text) is
  'Cancela já (sem esperar o fim do mês pago). Interna: usada por cancelar_assinatura e pela rotina.';
revoke execute on function cancelar_assinatura_agora(uuid, text) from public;

drop function if exists cancelar_assinatura(uuid, text);

create function cancelar_assinatura(p_assinatura uuid, p_motivo text default null, p_imediato boolean default false)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_ass      assinaturas%rowtype;
  v_fim_pago date;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status not in ('ativa', 'pausada') then
    raise exception 'Só assinaturas ativas ou pausadas podem ser canceladas.' using errcode = 'OV001';
  end if;
  if v_ass.cancelamento_agendado_para is not null and not coalesce(p_imediato, false) then
    raise exception 'O cancelamento já está agendado para %. Para cancelar agora, escolha "imediato".',
      to_char(v_ass.cancelamento_agendado_para, 'DD/MM/YYYY') using errcode = 'OV001';
  end if;

  v_fim_pago := (select max(periodo_fim) from faturas
                  where assinatura_id = p_assinatura and status = 'paga' and periodo_fim is not null);

  -- Sem nada pago pela frente (ou pausada, bloqueada, aguardando o 1º pagamento): cancela já.
  if coalesce(p_imediato, false)
     or v_ass.status <> 'ativa'
     or v_ass.aguardando_pagamento_desde is not null
     or v_ass.bloqueada_desde is not null
     or v_fim_pago is null
     or v_fim_pago <= hoje_sp()
  then
    perform cancelar_assinatura_agora(p_assinatura, p_motivo);
    return;
  end if;

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);

  update assinaturas
     set cancelamento_agendado_para = v_fim_pago,
         cancelamento_agendado_motivo = left(nullif(trim(p_motivo), ''), 500),
         plano_proximo_id = null, plano_proximo_a_partir_de = null,
         -- a cobrança volta para logo depois do mês pago (para o caso de desfazer)
         proxima_cobranca = least(coalesce(proxima_cobranca, v_fim_pago + 1), v_fim_pago + 1)
   where id = p_assinatura;

  -- Nenhuma cobrança nova depois do mês pago.
  update faturas
     set status = 'cancelada',
         observacao = left(concat_ws(' | ', observacao, 'Cancelada: cancelamento agendado'), 500)
   where assinatura_id = p_assinatura and status = 'pendente' and periodo_inicio > v_fim_pago;

  perform set_config('app.motivo', '', true);
end;
$$;
comment on function cancelar_assinatura(uuid, text, boolean) is
  'D7: o cancelamento vale no fim do mês pago (agenda); a rotina executa no dia seguinte. Pausada, bloqueada, sem mês pago ou p_imediato = cancela já.';
revoke execute on function cancelar_assinatura(uuid, text, boolean) from public;

create function desfazer_cancelamento_agendado(p_assinatura uuid)
returns void
language plpgsql
set search_path = public
as $$
begin
  perform 1 from assinaturas where id = p_assinatura and status = 'ativa' and cancelamento_agendado_para is not null for update;
  if not found then
    raise exception 'Esta assinatura não tem cancelamento agendado.' using errcode = 'OV001';
  end if;
  perform set_config('app.motivo', 'Cancelamento agendado desfeito', true);
  update assinaturas set cancelamento_agendado_para = null, cancelamento_agendado_motivo = null where id = p_assinatura;
  perform set_config('app.motivo', '', true);
end;
$$;
revoke execute on function desfazer_cancelamento_agendado(uuid) from public;

create function executar_cancelamentos_agendados()
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_a record;
  v_n integer := 0;
begin
  for v_a in
    select id, cancelamento_agendado_motivo from assinaturas
     where status in ('ativa', 'pausada') and cancelamento_agendado_para < hoje_sp()
  loop
    perform cancelar_assinatura_agora(v_a.id, coalesce(v_a.cancelamento_agendado_motivo, 'Cancelamento agendado'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
revoke execute on function executar_cancelamentos_agendados() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- D3/D4/D5 — pausa
-- ───────────────────────────────────────────────────────────────────────────
drop function if exists pausar_assinatura(uuid, text, date);

create function pausar_assinatura(
  p_assinatura       uuid,
  p_motivo           text default null,
  p_retorno_previsto date default null,
  p_destino          text default 'credito'
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_ass      assinaturas%rowtype;
  v_cli      clientes%rowtype;
  v_cfg      config_negocio%rowtype;
  v_hoje     date := hoje_sp();
  v_f        record;
  v_fim      date;
  v_n        integer;
  v_n_total  integer := 0;
  v_cred     integer := 0;
  v_feitas   integer;
  v_novo_bruto integer;
  v_desc     integer;
  v_cred_f   integer;
  v_valor    integer;
  v_reduzidas uuid[] := '{}';
  v_pausa    uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' then
    raise exception 'Só assinaturas ativas podem ser pausadas.' using errcode = 'OV001';
  end if;
  if v_ass.aguardando_pagamento_desde is not null then
    raise exception 'Esta assinatura aguarda o 1º pagamento: não há o que pausar. Cancele ou aguarde o pagamento.'
      using errcode = 'OV001';
  end if;
  if v_ass.cancelamento_agendado_para is not null then
    raise exception 'Há cancelamento agendado para %: desfaça o cancelamento antes de pausar.',
      to_char(v_ass.cancelamento_agendado_para, 'DD/MM/YYYY') using errcode = 'OV001';
  end if;
  if p_destino is null or p_destino not in ('credito', 'pentes') then
    raise exception 'Escolha como compensar as entregas pagas: crédito ou pentes depois.' using errcode = 'OV001';
  end if;
  if p_retorno_previsto is not null and p_retorno_previsto <= v_hoje then
    raise exception 'O retorno previsto precisa ser depois de hoje.' using errcode = 'OV001';
  end if;
  select * into v_cfg from config_negocio where id = 1;
  if p_retorno_previsto is not null and p_retorno_previsto > v_hoje + v_cfg.dias_max_pausa then
    raise exception 'A pausa pode durar no máximo % dias (retorno até %).',
      v_cfg.dias_max_pausa, to_char(v_hoje + v_cfg.dias_max_pausa, 'DD/MM/YYYY') using errcode = 'OV001';
  end if;
  select * into v_cli from clientes where id = v_ass.cliente_id;

  -- D3: entregas PAGAS e não feitas, dentro de períodos já pagos, durante a pausa.
  for v_f in
    select f.id, f.periodo_inicio, f.periodo_fim,
           coalesce(f.calculo_plano_frequencia, (select frequencia from planos where id = v_ass.plano_id)) as freq,
           coalesce(f.calculo_valor_entrega_centavos, 0) as valor_entrega
      from faturas f
     where f.assinatura_id = p_assinatura and f.status = 'paga'
       and f.periodo_inicio is not null and f.periodo_fim >= v_hoje
  loop
    v_fim := least(v_f.periodo_fim, coalesce(p_retorno_previsto - 1, v_f.periodo_fim));
    if v_fim >= greatest(v_hoje, v_f.periodo_inicio) then
      v_n := entregas_do_calendario_no_periodo(greatest(v_hoje, v_f.periodo_inicio), v_fim, v_f.freq)
           - (select count(*) from entregas
               where assinatura_id = p_assinatura and status = 'entregue'
                 and data_prevista between greatest(v_hoje, v_f.periodo_inicio) and v_fim);
      v_n := greatest(v_n, 0);
      v_n_total := v_n_total + v_n;
      v_cred := v_cred + v_n * v_f.valor_entrega;
    end if;
  end loop;

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);

  -- D4: a fatura em aberto do período corrente fica só com as entregas feitas.
  for v_f in
    select * from faturas
     where assinatura_id = p_assinatura and status in ('pendente', 'atrasada')
       and periodo_inicio is not null and periodo_inicio <= v_hoje and periodo_fim >= v_hoje
       and calculo_regra is not null
     for update
  loop
    select count(*) into v_feitas from entregas
     where assinatura_id = p_assinatura and status = 'entregue'
       and data_prevista between v_f.periodo_inicio and v_hoje;

    if v_feitas = 0 then
      update faturas set status = 'cancelada',
             observacao = left(concat_ws(' | ', observacao, 'Cancelada: pausa sem entregas feitas no período'), 500)
       where id = v_f.id;                                -- devolve o crédito, se havia (gatilho)
    else
      v_novo_bruto := v_feitas * v_f.calculo_valor_entrega_centavos;
      v_desc := round(v_novo_bruto::numeric * v_f.calculo_desconto_pct / 100)::integer;
      v_cred_f := least(v_f.calculo_credito_centavos, greatest(v_novo_bruto - v_desc - 100, 0));
      v_valor := v_novo_bruto - v_desc - v_cred_f;
      if v_f.calculo_credito_centavos > v_cred_f then
        insert into creditos_assinatura (assinatura_id, cliente_id, valor_centavos, origem, fatura_id, observacao)
        values (p_assinatura, v_ass.cliente_id, v_f.calculo_credito_centavos - v_cred_f, 'fatura_reduzida', v_f.id,
                'Fatura reduzida às entregas feitas (pausa): crédito devolvido');
      end if;
      update faturas
         set valor_centavos = v_valor, calculo_entregas = v_feitas, calculo_valor_bruto_centavos = v_novo_bruto,
             calculo_desconto_centavos = v_desc, calculo_credito_centavos = v_cred_f, calculo_ajuste_centavos = 0,
             observacao = left(concat_ws(' | ', observacao, 'Reduzida às ' || v_feitas || ' entrega(s) feita(s) (pausa)'), 500)
       where id = v_f.id;
      v_reduzidas := array_append(v_reduzidas, v_f.id);
    end if;
  end loop;

  update assinaturas
     set status = 'pausada', pausada_em = v_hoje, data_retorno_prevista = p_retorno_previsto
   where id = p_assinatura;

  -- Entregas pendentes e faturas pendentes que não foram reduzidas (D4) saem.
  update entregas
     set status = 'cancelada',
         observacao = left(concat_ws(' | ', observacao, 'Cancelada: assinatura pausada'), 500)
   where assinatura_id = p_assinatura and status = 'pendente';
  update faturas
     set status = 'cancelada',
         observacao = left(concat_ws(' | ', observacao, 'Cancelada: assinatura pausada'), 500)
   where assinatura_id = p_assinatura and status = 'pendente' and id <> all (v_reduzidas);

  update clientes set status = 'suspenso' where id = v_ass.cliente_id;

  -- A linha da pausa foi criada pelo gatilho; completa com a compensação escolhida.
  select id into v_pausa from pausas_assinatura where assinatura_id = p_assinatura and status = 'ativa';
  update pausas_assinatura
     set destino_credito = p_destino,
         entregas_pagas_nao_feitas = v_n_total,
         credito_centavos = case when p_destino = 'credito' then v_cred else 0 end,
         pentes_a_repor = case when p_destino = 'pentes' then least(v_n_total * coalesce(v_cli.pentes_padrao, 1), 49) else 0 end,
         duzias_a_repor = case when p_destino = 'pentes' then least(v_n_total * coalesce(v_cli.duzias_padrao, 0), 50) else 0 end
   where id = v_pausa;

  if p_destino = 'credito' and v_cred > 0 then
    insert into creditos_assinatura (assinatura_id, cliente_id, valor_centavos, origem, pausa_id, observacao)
    values (p_assinatura, v_ass.cliente_id, v_cred, 'pausa', v_pausa,
            v_n_total || ' entrega(s) paga(s) e não feita(s) na pausa');
  end if;

  perform set_config('app.motivo', '', true);
end;
$$;
comment on function pausar_assinatura(uuid, text, date, text) is
  'D3/D4/D5: pausa; entregas pagas e não feitas viram crédito ou pentes a repor; fatura aberta do período fica só com as entregas feitas; retorno limitado a config_negocio.dias_max_pausa.';
revoke execute on function pausar_assinatura(uuid, text, date, text) from public;


-- Reativar: os pentes/dúzias devidos pela pausa (D3, "pentes depois") vão na 1ª entrega do retorno.
create or replace function reativar_assinatura(
  p_assinatura uuid,
  p_retorno    date default null,
  p_motivo     text default null,
  p_agora      timestamptz default null
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_ass      assinaturas%rowtype;
  v_cliente  clientes%rowtype;
  v_retorno  date := coalesce(p_retorno, hoje_sp());
  v_primeira date;
  v_rep_pentes integer := 0;
  v_rep_duzias integer := 0;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status not in ('pausada', 'cancelada') then
    raise exception 'Só assinaturas pausadas ou canceladas podem ser reativadas.' using errcode = 'OV001';
  end if;
  if v_retorno < hoje_sp() then
    raise exception 'A data de retorno não pode estar no passado.' using errcode = 'OV001';
  end if;

  select * into v_cliente from clientes where id = v_ass.cliente_id for update;
  if not v_cliente.dentro_area_entrega then
    raise exception 'CEP fora da área de entrega.' using errcode = 'OV001';
  end if;

  if exists (
    select 1 from assinaturas
     where cliente_id = v_ass.cliente_id and id <> p_assinatura and status in ('ativa', 'pausada')
  ) then
    raise exception 'Este cliente já tem outra assinatura ativa ou pausada.' using errcode = 'OV001';
  end if;

  -- Lido ANTES de o status mudar (o gatilho encerra a pausa).
  select coalesce(pentes_a_repor, 0), coalesce(duzias_a_repor, 0)
    into v_rep_pentes, v_rep_duzias
    from pausas_assinatura where assinatura_id = p_assinatura and status = 'ativa';

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);

  update assinaturas
     set status = 'ativa', data_cancelamento = null, motivo_cancelamento = null,
         cancelamento_agendado_para = null, cancelamento_agendado_motivo = null,
         proxima_cobranca = v_retorno
   where id = p_assinatura;

  v_primeira := data_primeira_entrega(v_retorno, v_ass.plano_id, coalesce(p_agora, now()));
  while exists (
    select 1 from entregas
     where assinatura_id = p_assinatura and data_prevista = v_primeira
       and status in ('pendente', 'entregue')
  ) loop
    v_primeira := data_proxima_entrega(v_primeira, v_ass.plano_id);
  end loop;

  insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
  values (p_assinatura, v_ass.cliente_id, v_primeira,
          least(coalesce(v_cliente.pentes_padrao, 1) + v_rep_pentes, 50),
          least(coalesce(v_cliente.duzias_padrao, 0) + v_rep_duzias, 50));

  update clientes
     set status = case
                    when exists (select 1 from faturas where cliente_id = v_ass.cliente_id and status = 'paga')
                    then 'ativo'::status_cliente
                    else 'cadastro_andamento'::status_cliente
                  end
   where id = v_ass.cliente_id;

  perform set_config('app.motivo', '', true);
end;
$$;
revoke execute on function reativar_assinatura(uuid, date, text, timestamptz) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- D6 — troca de plano
-- ───────────────────────────────────────────────────────────────────────────

-- Põe as entregas pendentes de acordo com o calendário do plano novo: pendentes depois da
-- 1ª data nova saem; se não sobra nenhuma, cria a 1ª.
create function reagendar_entregas_pelo_plano(p_assinatura uuid, p_primeira date)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_ass assinaturas%rowtype;
  v_cli clientes%rowtype;
  v_d   date := p_primeira;
begin
  select * into v_ass from assinaturas where id = p_assinatura;
  select * into v_cli from clientes where id = v_ass.cliente_id;

  update entregas
     set status = 'cancelada',
         observacao = left(concat_ws(' | ', observacao, 'Cancelada: troca de plano (nova data no calendário do plano novo)'), 500)
   where assinatura_id = p_assinatura and status = 'pendente' and data_prevista > p_primeira;

  if not exists (select 1 from entregas where assinatura_id = p_assinatura and status = 'pendente') then
    while exists (
      select 1 from entregas
       where assinatura_id = p_assinatura and data_prevista = v_d and status in ('pendente', 'entregue')
    ) loop
      v_d := data_proxima_entrega(v_d, v_ass.plano_id);
    end loop;
    insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
    values (p_assinatura, v_ass.cliente_id, v_d,
            coalesce(v_cli.pentes_padrao, 1), coalesce(v_cli.duzias_padrao, 0));
  end if;
end;
$$;
revoke execute on function reagendar_entregas_pelo_plano(uuid, date) from public;

create or replace function alterar_plano_assinatura(p_assinatura uuid, p_plano smallint)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_ass     assinaturas%rowtype;
  v_atual   planos%rowtype;
  v_novo    planos%rowtype;
  v_hoje    date := hoje_sp();
  v_agora   timestamptz := now();
  v_quarta  date;
  v_fim_mes date;
  v_dif     integer;
  v_venc    date;
  v_prox_mes date := (date_trunc('month', hoje_sp()) + interval '1 month')::date;
  v_futuro  date;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status not in ('ativa', 'pausada') then
    raise exception 'Só assinaturas ativas ou pausadas podem trocar de plano.' using errcode = 'OV001';
  end if;
  if v_ass.aguardando_pagamento_desde is not null then
    raise exception 'A 1ª fatura já saiu com o plano atual: cancele e assine de novo para trocar de plano.'
      using errcode = 'OV001';
  end if;
  if v_ass.cancelamento_agendado_para is not null then
    raise exception 'Há cancelamento agendado: desfaça o cancelamento antes de trocar de plano.'
      using errcode = 'OV001';
  end if;
  select * into v_novo from planos where id = p_plano and ativo;
  if not found then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;
  select * into v_atual from planos where id = v_ass.plano_id;

  -- Voltar ao plano atual cancela uma redução agendada.
  if p_plano = v_ass.plano_id then
    if v_ass.plano_proximo_id is null then
      raise exception 'A assinatura já está neste plano.' using errcode = 'OV001';
    end if;
    update assinaturas set plano_proximo_id = null, plano_proximo_a_partir_de = null where id = p_assinatura;
    return;
  end if;

  perform set_config('app.motivo', 'Troca de plano: ' || v_atual.nome || ' → ' || v_novo.nome, true);

  -- Pausada (ou bloqueada): sem entregas em andamento, vale já e só muda o plano.
  if v_ass.status = 'pausada' or v_ass.bloqueada_desde is not null then
    update assinaturas set plano_id = p_plano, plano_proximo_id = null, plano_proximo_a_partir_de = null
     where id = p_assinatura;
    update clientes set plano_id = p_plano where id = v_ass.cliente_id and plano_id is distinct from p_plano;
    perform set_config('app.motivo', '', true);
    return;
  end if;

  if v_novo.entregas_por_mes < v_atual.entregas_por_mes then
    -- REDUÇÃO: vale no mês seguinte.
    update assinaturas set plano_proximo_id = p_plano, plano_proximo_a_partir_de = v_prox_mes
     where id = p_assinatura;
    perform set_config('app.motivo', '', true);
    return;
  end if;

  -- AUMENTO: vale na hora.
  v_quarta  := primeira_quarta_apos_corte(v_agora);
  v_fim_mes := (date_trunc('month', v_hoje) + interval '1 month')::date - 1;

  update assinaturas set plano_id = p_plano, plano_proximo_id = null, plano_proximo_a_partir_de = null
   where id = p_assinatura;
  update clientes set plano_id = p_plano where id = v_ass.cliente_id and plano_id is distinct from p_plano;

  -- Novo ritmo na 1ª quarta depois do corte.
  perform reagendar_entregas_pelo_plano(p_assinatura, data_primeira_entrega(v_hoje, p_plano, v_agora));

  -- Diferença do mês corrente: (entregas do plano novo − as do antigo, do corte ao fim do mês) × valor da entrega.
  -- (sem nenhuma fatura ainda, a 1ª fatura já sai pelo plano novo: não há diferença a cobrar)
  if v_quarta <= v_fim_mes
     and exists (select 1 from faturas where assinatura_id = p_assinatura and status <> 'cancelada') then
    v_dif := entregas_do_calendario_no_periodo(v_quarta, v_fim_mes, v_novo.frequencia)
           - entregas_do_calendario_no_periodo(v_quarta, v_fim_mes, v_atual.frequencia);
    if v_dif > 0 then
      v_venc := v_hoje;
      while exists (select 1 from faturas where assinatura_id = p_assinatura and vencimento = v_venc and status <> 'cancelada') loop
        v_venc := v_venc + 1;
      end loop;
      -- Avulsa (sem período): não desloca a cobrança do ciclo nem colide com a fatura do mês.
      perform inserir_fatura_com_snapshot(
        p_assinatura, v_venc, 'pendente', null, null,
        left('Diferença de plano (' || v_atual.nome || ' → ' || v_novo.nome || '): '
             || v_dif || ' entrega(s) de ' || to_char(v_quarta, 'DD/MM') || ' a ' || to_char(v_fim_mes, 'DD/MM'), 500),
        null, v_dif, p_plano);
    end if;
  end if;

  -- Faturas futuras ainda não pagas foram feitas pelo plano antigo: voltam a ser geradas pelo novo.
  select min(periodo_inicio) into v_futuro from faturas
   where assinatura_id = p_assinatura and status = 'pendente' and periodo_inicio > v_hoje and calculo_regra = 'calendario-v1';
  if v_futuro is not null then
    update faturas
       set status = 'cancelada',
           observacao = left(concat_ws(' | ', observacao, 'Cancelada: troca de plano (será refeita pelo plano novo)'), 500)
     where assinatura_id = p_assinatura and status = 'pendente' and periodo_inicio >= v_futuro and calculo_regra = 'calendario-v1';
    update assinaturas set proxima_cobranca = least(coalesce(proxima_cobranca, v_futuro), v_futuro) where id = p_assinatura;
  end if;

  perform set_config('app.motivo', '', true);
end;
$$;
revoke execute on function alterar_plano_assinatura(uuid, smallint) from public;

-- A rotina aplica a redução no dia marcado.
create function aplicar_trocas_agendadas()
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_a    assinaturas%rowtype;
  v_freq frequencia_plano;
  v_n    integer := 0;
  v_pend record;
begin
  for v_a in
    select * from assinaturas
     where plano_proximo_id is not null and plano_proximo_a_partir_de <= hoje_sp() and status in ('ativa', 'pausada')
     for update
  loop
    select frequencia into v_freq from planos where id = v_a.plano_proximo_id;
    perform set_config('app.motivo', 'Redução de plano agendada: vale a partir de hoje', true);
    update assinaturas set plano_id = v_a.plano_proximo_id, plano_proximo_id = null, plano_proximo_a_partir_de = null
     where id = v_a.id;
    update clientes set plano_id = v_a.plano_proximo_id where id = v_a.cliente_id and plano_id is distinct from v_a.plano_proximo_id;

    -- Entrega pendente fora do calendário do plano novo passa para a próxima data dele.
    for v_pend in
      select id, data_prevista from entregas
       where assinatura_id = v_a.id and status = 'pendente' and not data_de_entrega_do_plano(data_prevista, v_freq)
    loop
      update entregas set data_prevista = entrega_do_calendario_a_partir_de(v_pend.data_prevista, v_freq),
             observacao = left(concat_ws(' | ', observacao, 'Data ajustada ao calendário do plano novo'), 500)
       where id = v_pend.id;
    end loop;
    perform set_config('app.motivo', '', true);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
revoke execute on function aplicar_trocas_agendadas() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- Pedidos do assinante: pausa com preferência e troca de plano
-- ───────────────────────────────────────────────────────────────────────────
drop function if exists solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text);

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
comment on function solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text, text, smallint) is
  'O assinante pede pausa (com preferência: crédito ou pentes depois), cancelamento ou troca de plano da PRÓPRIA assinatura. Quem executa é o dono.';
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


-- ───────────────────────────────────────────────────────────────────────────
-- A cobrança e a rotina conhecem cancelamento agendado e troca de plano
-- ───────────────────────────────────────────────────────────────────────────
create or replace function gerar_cobranca(p_assinatura uuid)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass      assinaturas%rowtype;
  v_hoje     date := hoje_sp();
  v_inicio   date;   -- onde a cobrança está (proxima_cobranca)
  v_ini      date;   -- 1º dia contado na fatura
  v_fim      date;
  v_n        integer;
  v_freq     frequencia_plano;
  v_primeira boolean;
  v_venc     date;
  v_id       uuid;
  v_plano    smallint;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' or v_ass.proxima_cobranca is null then
    raise exception 'Só assinaturas ativas têm próxima cobrança.' using errcode = 'OV001';
  end if;
  if v_ass.cancelamento_agendado_para is not null then
    raise exception 'Cancelamento agendado: não há cobrança nova.' using errcode = 'OV001';
  end if;
  if v_ass.bloqueada_desde is not null then
    raise exception 'Assinatura bloqueada por inadimplência: não gera fatura nova até o pagamento.'
      using errcode = 'OV001';
  end if;

  -- D8: quem aguarda o 1º pagamento já tem a fatura certa em aberto (ver migration 427).
  if v_ass.aguardando_pagamento_desde is not null and exists (
       select 1 from faturas
        where assinatura_id = p_assinatura and status in ('pendente', 'atrasada')
     ) then
    raise exception 'Esta assinatura aguarda o pagamento da 1ª fatura, que já está em aberto: não há outra cobrança a gerar.'
      using errcode = 'OV001';
  end if;

  v_inicio   := v_ass.proxima_cobranca;
  -- D6: redução agendada vale a partir do mês marcado; a fatura desse mês já sai pelo plano novo.
  v_plano := case when v_ass.plano_proximo_id is not null and v_inicio >= v_ass.plano_proximo_a_partir_de
                  then v_ass.plano_proximo_id else v_ass.plano_id end;
  select frequencia into v_freq from planos where id = v_plano;
  v_primeira := not exists (select 1 from faturas where assinatura_id = p_assinatura and status <> 'cancelada');

  if v_primeira then
    -- 1ª fatura: da 1ª entrega (a real, se já existe; senão a projetada com o corte de agora) até o fim do mês dela.
    v_ini := coalesce(
      (select min(data_prevista) from entregas where assinatura_id = p_assinatura and status <> 'cancelada'),
      data_primeira_entrega(v_inicio, v_plano, case when v_inicio >= v_hoje then now() end)
    );
  elsif extract(day from v_inicio) = 1 then
    v_ini := v_inicio;                            -- mês cheio do calendário
  else
    -- Transição (assinatura que já cobrava no meio do mês, ou volta de pausa): do 1º dia
    -- do calendário possível até o fim do mês.
    -- (período passado: sem o corte de agora; só o futuro depende dele)
    v_ini := greatest(v_inicio, data_primeira_entrega(v_inicio, v_plano, case when v_inicio >= v_hoje then now() end));
  end if;

  v_fim := (date_trunc('month', v_ini) + interval '1 month')::date - 1;
  v_n   := entregas_do_calendario_no_periodo(v_ini, v_fim, v_freq);
  if v_n = 0 then
    -- Nenhuma entrega no que sobra do mês (ex.: mensal já entregue): cobra o mês seguinte inteiro.
    v_ini := v_fim + 1;
    v_fim := (date_trunc('month', v_ini) + interval '1 month')::date - 1;
    v_n   := entregas_do_calendario_no_periodo(v_ini, v_fim, v_freq);
  end if;

  -- Mês cheio: dia 3. 1ª fatura e transição: no dia em que a cobrança começa (proxima_cobranca);
  -- se esse dia já passou, a fatura nasce vencida (e atrasada, passada a tolerância).
  v_venc := case when not v_primeira and extract(day from v_ini) = 1
                 then v_ini + 2
                 else v_inicio end;

  select id into v_id from faturas
   where assinatura_id = p_assinatura and periodo_inicio = v_ini and status <> 'cancelada';

  if v_id is null then
    v_id := inserir_fatura_com_snapshot(
      p_assinatura, v_venc,
      case when fatura_atrasada_em(v_venc, v_hoje) then 'atrasada'::status_fatura else 'pendente'::status_fatura end,
      v_ini, v_fim,
      case v_ass.forma_cobranca
        when 'cartao' then 'Cartão (recorrência): confirme o pagamento e registre aqui.'
        else 'PIX: cobrança mensal manual.'
      end,
      null,
      v_n,
      v_plano
    );
  end if;

  update assinaturas set proxima_cobranca = v_fim + 1 where id = p_assinatura;
  return v_id;
end;
$$;
revoke execute on function gerar_cobranca(uuid) from public;

create or replace function processar_rotina_diaria()
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_hoje       date := hoje_sp();
  v_cfg        config_negocio%rowtype;
  v_r          record;
  v_reativadas int := 0;
  v_cobrancas  int := 0;
  v_canceladas int := 0;
  v_bloqueadas int := 0;
  v_canc_agend int := 0;
  v_trocas     int := 0;
  v_falhas     text[] := '{}';
  v_voltas     int;
  v_atrasadas  int;
begin
  perform pg_advisory_xact_lock(hashtext('ovo.processar_rotina_diaria'));
  select * into v_cfg from config_negocio where id = 1;

  for v_r in
    select id from assinaturas where status = 'pausada' and data_retorno_prevista <= v_hoje
  loop
    begin
      perform reativar_assinatura(v_r.id, v_hoje, 'Retorno programado da pausa');
      v_reativadas := v_reativadas + 1;
    exception when others then
      v_falhas := array_append(v_falhas, 'reativar ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  for v_r in
    select a.id, a.cliente_id
      from assinaturas a
     where a.status = 'ativa' and a.aguardando_pagamento_desde is not null
       and a.aguardando_pagamento_desde + v_cfg.dias_para_pagar_1a_fatura <= v_hoje
  loop
    begin
      perform cancelar_assinatura(v_r.id, 'Primeira fatura não paga no prazo');
      update clientes set status = 'cadastro_andamento' where id = v_r.cliente_id and status = 'cancelado';
      v_canceladas := v_canceladas + 1;
    exception when others then
      v_falhas := array_append(v_falhas, 'cancelar sem pagamento ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  -- D7: cancelamentos agendados cujo mês pago terminou. D6: reduções de plano do mês que começou.
  begin
    v_canc_agend := executar_cancelamentos_agendados();
  exception when others then
    v_falhas := array_append(v_falhas, 'cancelamentos agendados: ' || sqlerrm);
  end;
  begin
    v_trocas := aplicar_trocas_agendadas();
  exception when others then
    v_falhas := array_append(v_falhas, 'trocas de plano: ' || sqlerrm);
  end;

  -- Faturas do período: geradas com antecedência (a do mês seguinte sai dias_antecedencia_fatura dias
  -- antes), até 12 períodos por assinatura. Bloqueada não gera fatura nova (D2).
  for v_r in
    select id from assinaturas
     where status = 'ativa' and aguardando_pagamento_desde is null and bloqueada_desde is null
       and cancelamento_agendado_para is null
       and proxima_cobranca <= v_hoje + v_cfg.dias_antecedencia_fatura
  loop
    v_voltas := 0;
    begin
      while v_voltas < 12
            and (select proxima_cobranca <= v_hoje + v_cfg.dias_antecedencia_fatura
                   from assinaturas where id = v_r.id) loop
        perform gerar_cobranca(v_r.id);
        v_cobrancas := v_cobrancas + 1;
        v_voltas := v_voltas + 1;
      end loop;
    exception when others then
      v_falhas := array_append(v_falhas, 'cobrar ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  v_atrasadas := marcar_faturas_atrasadas();

  begin
    v_bloqueadas := bloquear_inadimplentes();
  exception when others then
    v_falhas := array_append(v_falhas, 'bloquear: ' || sqlerrm);
  end;

  return jsonb_build_object(
    'data', v_hoje,
    'reativadas', v_reativadas,
    'cobrancas_geradas', v_cobrancas,
    'canceladas_sem_pagamento', v_canceladas,
    'faturas_atrasadas', v_atrasadas,
    'assinaturas_bloqueadas', v_bloqueadas,
    'cancelamentos_executados', v_canc_agend,
    'trocas_aplicadas', v_trocas,
    'falhas', to_jsonb(v_falhas)
  );
end;
$$;
revoke execute on function processar_rotina_diaria() from public;


-- Down Migration

drop trigger if exists faturas_devolver_credito_tg on faturas;
drop function if exists faturas_devolver_credito();

-- Volta às funções do Bloco 9 e anteriores. (O valor 'troca_plano' do enum tipo_solicitacao
-- não pode ser removido do Postgres; fica sem uso.)
drop function if exists processar_rotina_diaria();
create or replace function processar_rotina_diaria()
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_hoje       date := hoje_sp();
  v_cfg        config_negocio%rowtype;
  v_r          record;
  v_reativadas int := 0;
  v_cobrancas  int := 0;
  v_canceladas int := 0;
  v_bloqueadas int := 0;
  v_falhas     text[] := '{}';
  v_voltas     int;
  v_atrasadas  int;
begin
  perform pg_advisory_xact_lock(hashtext('ovo.processar_rotina_diaria'));
  select * into v_cfg from config_negocio where id = 1;

  for v_r in
    select id from assinaturas where status = 'pausada' and data_retorno_prevista <= v_hoje
  loop
    begin
      perform reativar_assinatura(v_r.id, v_hoje, 'Retorno programado da pausa');
      v_reativadas := v_reativadas + 1;
    exception when others then
      v_falhas := array_append(v_falhas, 'reativar ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  for v_r in
    select a.id, a.cliente_id
      from assinaturas a
     where a.status = 'ativa' and a.aguardando_pagamento_desde is not null
       and a.aguardando_pagamento_desde + v_cfg.dias_para_pagar_1a_fatura <= v_hoje
  loop
    begin
      perform cancelar_assinatura(v_r.id, 'Primeira fatura não paga no prazo');
      update clientes set status = 'cadastro_andamento' where id = v_r.cliente_id and status = 'cancelado';
      v_canceladas := v_canceladas + 1;
    exception when others then
      v_falhas := array_append(v_falhas, 'cancelar sem pagamento ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  -- Faturas do período: geradas com antecedência (a do mês seguinte sai dias_antecedencia_fatura dias
  -- antes), até 12 períodos por assinatura. Bloqueada não gera fatura nova (D2).
  for v_r in
    select id from assinaturas
     where status = 'ativa' and aguardando_pagamento_desde is null and bloqueada_desde is null
       and proxima_cobranca <= v_hoje + v_cfg.dias_antecedencia_fatura
  loop
    v_voltas := 0;
    begin
      while v_voltas < 12
            and (select proxima_cobranca <= v_hoje + v_cfg.dias_antecedencia_fatura
                   from assinaturas where id = v_r.id) loop
        perform gerar_cobranca(v_r.id);
        v_cobrancas := v_cobrancas + 1;
        v_voltas := v_voltas + 1;
      end loop;
    exception when others then
      v_falhas := array_append(v_falhas, 'cobrar ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  v_atrasadas := marcar_faturas_atrasadas();

  begin
    v_bloqueadas := bloquear_inadimplentes();
  exception when others then
    v_falhas := array_append(v_falhas, 'bloquear: ' || sqlerrm);
  end;

  return jsonb_build_object(
    'data', v_hoje,
    'reativadas', v_reativadas,
    'cobrancas_geradas', v_cobrancas,
    'canceladas_sem_pagamento', v_canceladas,
    'faturas_atrasadas', v_atrasadas,
    'assinaturas_bloqueadas', v_bloqueadas,
    'falhas', to_jsonb(v_falhas)
  );
end;
$$;
revoke execute on function processar_rotina_diaria() from public;

create or replace function gerar_cobranca(p_assinatura uuid)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass      assinaturas%rowtype;
  v_hoje     date := hoje_sp();
  v_inicio   date;   -- onde a cobrança está (proxima_cobranca)
  v_ini      date;   -- 1º dia contado na fatura
  v_fim      date;
  v_n        integer;
  v_freq     frequencia_plano;
  v_primeira boolean;
  v_venc     date;
  v_id       uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' or v_ass.proxima_cobranca is null then
    raise exception 'Só assinaturas ativas têm próxima cobrança.' using errcode = 'OV001';
  end if;
  if v_ass.bloqueada_desde is not null then
    raise exception 'Assinatura bloqueada por inadimplência: não gera fatura nova até o pagamento.'
      using errcode = 'OV001';
  end if;

  -- D8: quem aguarda o 1º pagamento já tem a fatura certa em aberto (ver migration 427).
  if v_ass.aguardando_pagamento_desde is not null and exists (
       select 1 from faturas
        where assinatura_id = p_assinatura and status in ('pendente', 'atrasada')
     ) then
    raise exception 'Esta assinatura aguarda o pagamento da 1ª fatura, que já está em aberto: não há outra cobrança a gerar.'
      using errcode = 'OV001';
  end if;

  select frequencia into v_freq from planos where id = v_ass.plano_id;
  v_inicio   := v_ass.proxima_cobranca;
  v_primeira := not exists (select 1 from faturas where assinatura_id = p_assinatura and status <> 'cancelada');

  if v_primeira then
    -- 1ª fatura: da 1ª entrega (a real, se já existe; senão a projetada com o corte de agora) até o fim do mês dela.
    v_ini := coalesce(
      (select min(data_prevista) from entregas where assinatura_id = p_assinatura and status <> 'cancelada'),
      data_primeira_entrega(v_inicio, v_ass.plano_id, case when v_inicio >= v_hoje then now() end)
    );
  elsif extract(day from v_inicio) = 1 then
    v_ini := v_inicio;                            -- mês cheio do calendário
  else
    -- Transição (assinatura que já cobrava no meio do mês, ou volta de pausa): do 1º dia
    -- do calendário possível até o fim do mês.
    -- (período passado: sem o corte de agora; só o futuro depende dele)
    v_ini := greatest(v_inicio, data_primeira_entrega(v_inicio, v_ass.plano_id, case when v_inicio >= v_hoje then now() end));
  end if;

  v_fim := (date_trunc('month', v_ini) + interval '1 month')::date - 1;
  v_n   := entregas_do_calendario_no_periodo(v_ini, v_fim, v_freq);
  if v_n = 0 then
    -- Nenhuma entrega no que sobra do mês (ex.: mensal já entregue): cobra o mês seguinte inteiro.
    v_ini := v_fim + 1;
    v_fim := (date_trunc('month', v_ini) + interval '1 month')::date - 1;
    v_n   := entregas_do_calendario_no_periodo(v_ini, v_fim, v_freq);
  end if;

  -- Mês cheio: dia 3. 1ª fatura e transição: no dia em que a cobrança começa (proxima_cobranca);
  -- se esse dia já passou, a fatura nasce vencida (e atrasada, passada a tolerância).
  v_venc := case when not v_primeira and extract(day from v_ini) = 1
                 then v_ini + 2
                 else v_inicio end;

  select id into v_id from faturas
   where assinatura_id = p_assinatura and periodo_inicio = v_ini and status <> 'cancelada';

  if v_id is null then
    v_id := inserir_fatura_com_snapshot(
      p_assinatura, v_venc,
      case when fatura_atrasada_em(v_venc, v_hoje) then 'atrasada'::status_fatura else 'pendente'::status_fatura end,
      v_ini, v_fim,
      case v_ass.forma_cobranca
        when 'cartao' then 'Cartão (recorrência): confirme o pagamento e registre aqui.'
        else 'PIX: cobrança mensal manual.'
      end,
      null,
      v_n
    );
  end if;

  update assinaturas set proxima_cobranca = v_fim + 1 where id = p_assinatura;
  return v_id;
end;
$$;
revoke execute on function gerar_cobranca(uuid) from public;

drop function if exists inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer, integer, smallint);
create function inserir_fatura_com_snapshot(
  p_assinatura      uuid,
  p_vencimento      date,
  p_status          status_fatura,
  p_periodo_inicio  date,
  p_periodo_fim     date,
  p_observacao      text,
  p_valor_informado integer default null,
  p_entregas        integer default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass   assinaturas%rowtype;
  v_d     record;
  v_valor integer;
  v_id    uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;

  select * into v_d from calcular_detalhe_fatura(p_assinatura, p_entregas);
  v_valor := coalesce(p_valor_informado, v_d.valor_final_centavos);

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
    v_d.credito_centavos,
    v_valor - (v_d.valor_bruto_centavos - v_d.desconto_centavos - v_d.credito_centavos)
  )
  returning id into v_id;

  return v_id;
end;
$$;
revoke execute on function inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer, integer) from public;

drop function if exists calcular_detalhe_fatura(uuid, integer, smallint);
create function calcular_detalhe_fatura(p_assinatura uuid, p_entregas integer default null)
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
  v_final   integer;
  v_origem  text;
begin
  select * into v_ass from assinaturas where id = p_assinatura;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  select * into v_plano from planos where id = v_ass.plano_id;
  select * into v_cli   from clientes where id = v_ass.cliente_id;
  select * into v_cfg   from config_negocio where id = 1;

  -- Sem p_entregas: a conta antiga (mês fixo). Com: as entregas do período (D10).
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
    v_bruto - v_final,
    v_origem,
    0,
    v_final;
end;
$$;
revoke execute on function calcular_detalhe_fatura(uuid, integer) from public;

drop function if exists aplicar_trocas_agendadas();
drop function if exists reagendar_entregas_pelo_plano(uuid, date);
drop function if exists executar_cancelamentos_agendados();
drop function if exists desfazer_cancelamento_agendado(uuid);

CREATE OR REPLACE FUNCTION public.reativar_assinatura(p_assinatura uuid, p_retorno date DEFAULT NULL::date, p_motivo text DEFAULT NULL::text, p_agora timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_ass     assinaturas%rowtype;
  v_cliente clientes%rowtype;
  v_retorno date := coalesce(p_retorno, hoje_sp());
  v_primeira date;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status not in ('pausada', 'cancelada') then
    raise exception 'Só assinaturas pausadas ou canceladas podem ser reativadas.' using errcode = 'OV001';
  end if;
  if v_retorno < hoje_sp() then
    raise exception 'A data de retorno não pode estar no passado.' using errcode = 'OV001';
  end if;

  select * into v_cliente from clientes where id = v_ass.cliente_id for update;
  if not v_cliente.dentro_area_entrega then
    raise exception 'CEP fora da área de entrega.' using errcode = 'OV001';
  end if;

  if exists (
    select 1 from assinaturas
     where cliente_id = v_ass.cliente_id and id <> p_assinatura and status in ('ativa', 'pausada')
  ) then
    raise exception 'Este cliente já tem outra assinatura ativa ou pausada.' using errcode = 'OV001';
  end if;

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);

  update assinaturas
     set status = 'ativa', data_cancelamento = null, motivo_cancelamento = null,
         proxima_cobranca = v_retorno
   where id = p_assinatura;

  v_primeira := data_primeira_entrega(v_retorno, v_ass.plano_id, coalesce(p_agora, now()));
  while exists (
    select 1 from entregas
     where assinatura_id = p_assinatura and data_prevista = v_primeira
       and status in ('pendente', 'entregue')
  ) loop
    v_primeira := data_proxima_entrega(v_primeira, v_ass.plano_id);
  end loop;

  insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
  values (p_assinatura, v_ass.cliente_id, v_primeira,
          coalesce(v_cliente.pentes_padrao, 1), coalesce(v_cliente.duzias_padrao, 0));

  update clientes
     set status = case
                    when exists (select 1 from faturas where cliente_id = v_ass.cliente_id and status = 'paga')
                    then 'ativo'::status_cliente
                    else 'cadastro_andamento'::status_cliente
                  end
   where id = v_ass.cliente_id;

  perform set_config('app.motivo', '', true);
end;
$function$;
revoke execute on function reativar_assinatura(uuid, date, text, timestamptz) from public;

CREATE OR REPLACE FUNCTION public.resolver_solicitacao(p_solicitacao uuid, p_status status_solicitacao, p_resposta text DEFAULT NULL::text, p_executar boolean DEFAULT false, p_retorno_previsto date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
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

  -- Atender pode já executar o pedido, na mesma transação.
  if p_status = 'atendida' and p_executar then
    if v_s.tipo = 'pausa' then
      perform pausar_assinatura(v_s.assinatura_id,
        left('Pedido do assinante' || coalesce(': ' || v_s.motivo, ''), 500), p_retorno_previsto);
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
$function$;

drop function if exists solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text, text, smallint);
CREATE OR REPLACE FUNCTION public.solicitar_alteracao_assinatura(p_assinatura uuid, p_tipo tipo_solicitacao, p_motivo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  insert into solicitacoes_assinatura (assinatura_id, cliente_id, tipo, motivo)
  values (p_assinatura, v_ass.cliente_id, p_tipo, nullif(trim(p_motivo), ''))
  returning id into v_id;

  return v_id;
end;
$function$;
revoke execute on function solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text) from public;
grant  execute on function solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text) to app_usuario;

drop function if exists pausar_assinatura(uuid, text, date, text);
CREATE OR REPLACE FUNCTION public.pausar_assinatura(p_assinatura uuid, p_motivo text DEFAULT NULL::text, p_retorno_previsto date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_ass assinaturas%rowtype;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' then
    raise exception 'Só assinaturas ativas podem ser pausadas.' using errcode = 'OV001';
  end if;
  if v_ass.aguardando_pagamento_desde is not null then
    raise exception 'Esta assinatura aguarda o 1º pagamento: não há o que pausar. Cancele ou aguarde o pagamento.'
      using errcode = 'OV001';
  end if;
  if p_retorno_previsto is not null and p_retorno_previsto <= hoje_sp() then
    raise exception 'O retorno previsto precisa ser depois de hoje.' using errcode = 'OV001';
  end if;

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);

  update assinaturas
     set status = 'pausada', pausada_em = hoje_sp(), data_retorno_prevista = p_retorno_previsto
   where id = p_assinatura;
  perform cancelar_pendencias_da_assinatura(p_assinatura, 'assinatura pausada');
  update clientes set status = 'suspenso' where id = v_ass.cliente_id;

  perform set_config('app.motivo', '', true);
end;
$function$;
revoke execute on function pausar_assinatura(uuid, text, date) from public;

drop function if exists cancelar_assinatura(uuid, text, boolean);
CREATE OR REPLACE FUNCTION public.cancelar_assinatura(p_assinatura uuid, p_motivo text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_ass assinaturas%rowtype;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status not in ('ativa', 'pausada') then
    raise exception 'Só assinaturas ativas ou pausadas podem ser canceladas.' using errcode = 'OV001';
  end if;

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);

  update assinaturas
     set status = 'cancelada',
         data_cancelamento = hoje_sp(),
         motivo_cancelamento = nullif(trim(p_motivo), '')
   where id = p_assinatura;
  perform cancelar_pendencias_da_assinatura(p_assinatura, 'assinatura cancelada');
  update clientes set status = 'cancelado' where id = v_ass.cliente_id;

  perform set_config('app.motivo', '', true);
end;
$function$;
revoke execute on function cancelar_assinatura(uuid, text) from public;
drop function if exists cancelar_assinatura_agora(uuid, text);

create or replace function alterar_plano_assinatura(p_assinatura uuid, p_plano smallint)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_ass assinaturas%rowtype;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status not in ('ativa', 'pausada') then
    raise exception 'Só assinaturas ativas ou pausadas podem trocar de plano.' using errcode = 'OV001';
  end if;
  if v_ass.aguardando_pagamento_desde is not null then
    raise exception 'A 1ª fatura já saiu com o plano atual: cancele e assine de novo para trocar de plano.'
      using errcode = 'OV001';
  end if;
  if not exists (select 1 from planos where id = p_plano and ativo) then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;

  update assinaturas set plano_id = p_plano where id = p_assinatura;
  update clientes set plano_id = p_plano where id = v_ass.cliente_id and plano_id is distinct from p_plano;
end;
$$;
revoke execute on function alterar_plano_assinatura(uuid, smallint) from public;

drop function if exists saldo_credito(uuid);
drop table if exists creditos_assinatura;

alter table solicitacoes_assinatura drop column if exists plano_destino_id, drop column if exists preferencia;
alter table pausas_assinatura
  drop column if exists duzias_a_repor, drop column if exists pentes_a_repor, drop column if exists credito_centavos,
  drop column if exists entregas_pagas_nao_feitas, drop column if exists destino_credito;
alter table assinaturas
  drop constraint if exists assinaturas_troca_agendada_completa,
  drop column if exists plano_proximo_a_partir_de, drop column if exists plano_proximo_id,
  drop column if exists cancelamento_agendado_motivo, drop column if exists cancelamento_agendado_para;
alter table config_negocio drop column if exists dias_max_pausa;
