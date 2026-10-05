-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 9 — operação do dia a dia.
--
-- Regras de negócio informadas em 30/09/2026:
--   pente = 30 ovos; entrega = R$ 41; semanal R$ 164/mês (4 entregas),
--   quinzenal R$ 82 (2), mensal R$ 41 (1); 10% no 1º mês; PIX = cobrança
--   mensal manual; cartão = recorrência; sem fidelidade; sem carência; pausa
--   controlada; alterações importantes com histórico.
--
-- O que esta migration cria:
--   1. `cartao` como método de pagamento.
--   2. Ciclo de cobrança na assinatura: forma de cobrança (pix | cartao) e
--      data da próxima cobrança. `gerar_cobranca()` cria a fatura do período
--      (1 mês) e avança a data. NÃO há integração com operadora de cartão:
--      "cartão" registra a forma combinada; a confirmação do pagamento continua
--      sendo registrada pelo dono.
--   3. Pausa controlada: data de início e retorno previsto; a rotina diária
--      reativa sozinha quando o retorno chega.
--   4. Reposição de ovos com defeito (DECISOES #14): registro próprio que
--      aponta a entrega com defeito e a entrega em que será reposta; sem custo.
--   5. Resposta do dono aos pedidos de pausa/cancelamento do assinante.
--   6. Horário previsto (opcional) na entrega.
--   7. Rotina diária: retornos de pausa, cobranças do período, atrasadas.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Cartão como método de pagamento
-- (ADD VALUE pode rodar em transação desde o PG 12, desde que o valor novo
--  não seja usado nesta mesma transação — e não é.)
-- ───────────────────────────────────────────────────────────────────────────
alter type metodo_pagamento add value if not exists 'cartao';


-- ───────────────────────────────────────────────────────────────────────────
-- 2. Ciclo de cobrança e pausa controlada na assinatura
-- ───────────────────────────────────────────────────────────────────────────
create type forma_cobranca as enum ('pix', 'cartao');

alter table assinaturas
  add column forma_cobranca        forma_cobranca not null default 'pix',
  add column proxima_cobranca      date,
  add column pausada_em            date,
  add column data_retorno_prevista date,
  add constraint assinaturas_retorno_depois_da_pausa
    check (data_retorno_prevista is null or pausada_em is null or data_retorno_prevista > pausada_em);

comment on column assinaturas.forma_cobranca is
  'pix: cobrança mensal manual (o dono confere o comprovante). cartao: recorrência combinada com o cliente; sem integração com operadora, o pagamento é confirmado pelo dono.';
comment on column assinaturas.proxima_cobranca is
  'Início do próximo período a cobrar. gerar_cobranca() cria a fatura desse período e avança 1 mês. Nula enquanto pausada ou cancelada.';
comment on column assinaturas.data_retorno_prevista is
  'Pausa controlada: a rotina diária reativa a assinatura nesta data.';

-- Assinaturas que já existiam e estão ativas começam a ser cobradas hoje.
update assinaturas set proxima_cobranca = hoje_sp() where status = 'ativa' and proxima_cobranca is null;

create index assinaturas_proxima_cobranca_idx on assinaturas (proxima_cobranca) where status = 'ativa';
create index assinaturas_retorno_idx on assinaturas (data_retorno_prevista) where status = 'pausada';

-- Mantém o ciclo coerente com a situação, venha a mudança de onde vier.
create or replace function assinaturas_ciclo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'ativa' and new.proxima_cobranca is null then
      new.proxima_cobranca := new.data_inicio;   -- 1ª cobrança no início
    end if;
    return new;
  end if;

  if new.status is distinct from old.status then
    if new.status in ('pausada', 'cancelada', 'encerrada') then
      new.proxima_cobranca := null;               -- nada é cobrado parado
    end if;
    if new.status <> 'pausada' then
      new.pausada_em := null;
      new.data_retorno_prevista := null;
    end if;
    if new.status = 'ativa' and new.proxima_cobranca is null then
      new.proxima_cobranca := hoje_sp();
    end if;
  end if;
  return new;
end;
$$;

create trigger assinaturas_ciclo_tg
  before insert or update on assinaturas
  for each row execute function assinaturas_ciclo();

revoke execute on function assinaturas_ciclo() from public;


-- Faturas com período.
alter table faturas
  add column periodo_inicio date,
  add column periodo_fim    date,
  add constraint faturas_periodo_completo check ((periodo_inicio is null) = (periodo_fim is null)),
  add constraint faturas_periodo_ordem    check (periodo_fim is null or periodo_fim >= periodo_inicio);

comment on column faturas.periodo_inicio is
  'Período coberto pela fatura. Nulo = fatura avulsa criada à mão pelo dono.';

-- Um período vivo por assinatura: a rotina rodando duas vezes não cobra duas vezes.
create unique index faturas_periodo_unico_idx
  on faturas (assinatura_id, periodo_inicio)
  where status <> 'cancelada' and periodo_inicio is not null;


-- ───────────────────────────────────────────────────────────────────────────
-- 3. Entrega: horário previsto (opcional)
-- ───────────────────────────────────────────────────────────────────────────
alter table entregas add column horario_previsto time;
comment on column entregas.horario_previsto is
  'Horário combinado com o cliente, se houver. A data continua sendo a quarta-feira do plano.';


-- ───────────────────────────────────────────────────────────────────────────
-- 4. Reposição de ovos com defeito
-- ───────────────────────────────────────────────────────────────────────────
create type status_reposicao as enum ('pendente', 'reposta', 'cancelada');

create table reposicoes (
  id                    uuid primary key default gen_random_uuid(),
  assinatura_id         uuid not null references assinaturas (id) on delete restrict,
  cliente_id            uuid not null references clientes (id)    on delete restrict,
  entrega_origem_id     uuid not null references entregas (id)    on delete restrict,
  entrega_reposicao_id  uuid references entregas (id)             on delete restrict,
  quantidade_ovos       smallint not null check (quantidade_ovos between 1 and 1500),
  descricao             text not null check (char_length(descricao) between 3 and 500),
  status                status_reposicao not null default 'pendente',
  reposta_em            timestamptz,
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now(),
  check ((status = 'reposta') = (reposta_em is not null)),
  check (status <> 'reposta' or entrega_reposicao_id is not null),
  check (entrega_reposicao_id is distinct from entrega_origem_id)
);

comment on table reposicoes is
  'Ovos com defeito numa entrega, repostos sem custo na entrega seguinte (DECISOES #14). Não entra no valor da fatura.';

create index reposicoes_assinatura_idx on reposicoes (assinatura_id);
create index reposicoes_origem_idx     on reposicoes (entrega_origem_id);
create index reposicoes_reposicao_idx  on reposicoes (entrega_reposicao_id);
create index reposicoes_pendentes_idx  on reposicoes (assinatura_id) where status = 'pendente';

alter table reposicoes enable row level security;
revoke all on table reposicoes from app_anon, app_usuario;
grant select on table reposicoes to app_usuario;

create policy "reposicoes: le as proprias, dono le todas"
  on reposicoes for select to app_usuario
  using (
    (select sou_dono())
    or exists (
      select 1 from clientes c
      where c.id = reposicoes.cliente_id
        and c.usuario_id = app.usuario_id()
    )
  );

create or replace function reposicoes_antes_de_gravar()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    new.id                := old.id;
    new.assinatura_id     := old.assinatura_id;
    new.cliente_id        := old.cliente_id;
    new.entrega_origem_id := old.entrega_origem_id;
    new.criado_em         := old.criado_em;
  end if;
  new.atualizado_em := now();
  return new;
end;
$$;

create trigger reposicoes_antes_de_gravar_tg
  before insert or update on reposicoes
  for each row execute function reposicoes_antes_de_gravar();

revoke execute on function reposicoes_antes_de_gravar() from public;


-- A próxima entrega pendente da assinatura (a mais cedo), exceto uma.
create or replace function proxima_entrega_pendente(p_assinatura uuid, p_exceto uuid default null)
returns uuid
language sql
stable
set search_path = public
as $$
  select id from entregas
   where assinatura_id = p_assinatura and status = 'pendente'
     and id is distinct from p_exceto
   order by data_prevista, criado_em
   limit 1;
$$;

revoke execute on function proxima_entrega_pendente(uuid, uuid) from public;


create or replace function registrar_defeito(
  p_entrega    uuid,
  p_quantidade smallint,
  p_descricao  text
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_e  entregas%rowtype;
  v_id uuid;
begin
  select * into v_e from entregas where id = p_entrega for update;
  if not found then
    raise exception 'Entrega não encontrada.' using errcode = 'OV001';
  end if;
  if v_e.status <> 'entregue' then
    raise exception 'Só dá para registrar defeito de uma entrega já feita.' using errcode = 'OV001';
  end if;
  if p_quantidade is null or p_quantidade < 1 then
    raise exception 'Informe quantos ovos vieram com defeito.' using errcode = 'OV001';
  end if;
  if char_length(trim(coalesce(p_descricao, ''))) < 3 then
    raise exception 'Descreva o defeito (pelo menos 3 letras).' using errcode = 'OV001';
  end if;

  insert into reposicoes (assinatura_id, cliente_id, entrega_origem_id, entrega_reposicao_id,
                          quantidade_ovos, descricao)
  values (v_e.assinatura_id, v_e.cliente_id, p_entrega,
          proxima_entrega_pendente(v_e.assinatura_id, p_entrega),
          p_quantidade, trim(p_descricao))
  returning id into v_id;

  return v_id;
end;
$$;

comment on function registrar_defeito(uuid, smallint, text) is
  'Registra ovos com defeito numa entrega feita e liga a reposição à próxima entrega pendente (ou à primeira que for criada).';
revoke execute on function registrar_defeito(uuid, smallint, text) from public;


create or replace function cancelar_reposicao(p_reposicao uuid, p_motivo text default null)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_r reposicoes%rowtype;
begin
  select * into v_r from reposicoes where id = p_reposicao for update;
  if not found then
    raise exception 'Reposição não encontrada.' using errcode = 'OV001';
  end if;
  if v_r.status <> 'pendente' then
    raise exception 'Só uma reposição pendente pode ser cancelada.' using errcode = 'OV001';
  end if;
  perform set_config('app.motivo', coalesce(p_motivo, ''), true);
  update reposicoes set status = 'cancelada', entrega_reposicao_id = null where id = p_reposicao;
  perform set_config('app.motivo', '', true);
end;
$$;

revoke execute on function cancelar_reposicao(uuid, text) from public;


-- As entregas carregam as reposições: nova pendente pega as soltas; entregue
-- conclui; não entregue/cancelada passa para a próxima pendente.
create or replace function entregas_movem_reposicoes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'pendente' then
      update reposicoes set entrega_reposicao_id = new.id
       where assinatura_id = new.assinatura_id and status = 'pendente'
         and entrega_reposicao_id is null;
    end if;
    return null;
  end if;

  if new.status is distinct from old.status and old.status = 'pendente' then
    if new.status = 'entregue' then
      update reposicoes set status = 'reposta', reposta_em = now()
       where entrega_reposicao_id = new.id and status = 'pendente';
    else
      update reposicoes
         set entrega_reposicao_id = proxima_entrega_pendente(new.assinatura_id, new.id)
       where entrega_reposicao_id = new.id and status = 'pendente';
    end if;
  end if;
  return null;
end;
$$;

create trigger entregas_movem_reposicoes_tg
  after insert or update of status on entregas
  for each row execute function entregas_movem_reposicoes();

revoke execute on function entregas_movem_reposicoes() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- 5. Horário da entrega
-- ───────────────────────────────────────────────────────────────────────────
create or replace function definir_horario_entrega(p_entrega uuid, p_horario time)
returns void
language plpgsql
set search_path = public
as $$
begin
  update entregas set horario_previsto = p_horario
   where id = p_entrega and status = 'pendente';
  if not found then
    raise exception 'Só dá para definir horário de uma entrega pendente.' using errcode = 'OV001';
  end if;
end;
$$;

revoke execute on function definir_horario_entrega(uuid, time) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- 6. Pausa controlada
-- ───────────────────────────────────────────────────────────────────────────
drop function if exists pausar_assinatura(uuid, text);

create or replace function pausar_assinatura(
  p_assinatura       uuid,
  p_motivo           text default null,
  p_retorno_previsto date default null
)
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
  if v_ass.status <> 'ativa' then
    raise exception 'Só assinaturas ativas podem ser pausadas.' using errcode = 'OV001';
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
$$;

comment on function pausar_assinatura(uuid, text, date) is
  'Pausa: cancela entregas e faturas pendentes (atrasadas continuam cobráveis), suspende o cliente e para o ciclo de cobrança. Com retorno previsto, a rotina diária reativa na data.';
revoke execute on function pausar_assinatura(uuid, text, date) from public;


-- Reativar: igual à Fase 5, e o ciclo de cobrança recomeça na data do retorno.
create or replace function reativar_assinatura(
  p_assinatura uuid,
  p_retorno    date default null,
  p_motivo     text default null
)
returns void
language plpgsql
set search_path = public
as $$
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

  v_primeira := data_primeira_entrega(v_retorno, v_ass.plano_id);
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
$$;

revoke execute on function reativar_assinatura(uuid, date, text) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- 7. Cobrança do período
-- ───────────────────────────────────────────────────────────────────────────
create or replace function definir_forma_cobranca(p_assinatura uuid, p_forma forma_cobranca)
returns void
language plpgsql
set search_path = public
as $$
begin
  if p_forma is null then
    raise exception 'Informe a forma de cobrança.' using errcode = 'OV001';
  end if;
  update assinaturas set forma_cobranca = p_forma where id = p_assinatura;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
end;
$$;

revoke execute on function definir_forma_cobranca(uuid, forma_cobranca) from public;


-- Cria a fatura do período que começa em proxima_cobranca e avança 1 mês.
-- Vencimento = início do período. Valor = calcular_valor_fatura (inclui os
-- 10% da 1ª fatura).
create or replace function gerar_cobranca(p_assinatura uuid)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass    assinaturas%rowtype;
  v_inicio date;
  v_fim    date;
  v_id     uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' or v_ass.proxima_cobranca is null then
    raise exception 'Só assinaturas ativas têm próxima cobrança.' using errcode = 'OV001';
  end if;

  v_inicio := v_ass.proxima_cobranca;
  v_fim    := (v_inicio + interval '1 month')::date - 1;

  select id into v_id from faturas
   where assinatura_id = p_assinatura and periodo_inicio = v_inicio and status <> 'cancelada';

  if v_id is null then
    insert into faturas (cliente_id, assinatura_id, valor_centavos, vencimento, status,
                         periodo_inicio, periodo_fim, observacao)
    values (v_ass.cliente_id, p_assinatura, calcular_valor_fatura(p_assinatura), v_inicio,
            case when v_inicio < hoje_sp() then 'atrasada'::status_fatura else 'pendente'::status_fatura end,
            v_inicio, v_fim,
            case v_ass.forma_cobranca
              when 'cartao' then 'Cartão (recorrência): confirme o pagamento e registre aqui.'
              else 'PIX: cobrança mensal manual.'
            end)
    returning id into v_id;
  end if;

  update assinaturas set proxima_cobranca = v_fim + 1 where id = p_assinatura;
  return v_id;
end;
$$;

comment on function gerar_cobranca(uuid) is
  'Fatura do próximo período (1 mês) da assinatura ativa; avança proxima_cobranca. Idempotente por período.';
revoke execute on function gerar_cobranca(uuid) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- 8. Resposta aos pedidos do assinante
-- ───────────────────────────────────────────────────────────────────────────
alter table solicitacoes_assinatura
  add column resposta text check (char_length(resposta) <= 500);

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
$$;

revoke execute on function resolver_solicitacao(uuid, status_solicitacao, text, boolean, date) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- 9. Rotina diária
-- ───────────────────────────────────────────────────────────────────────────
create or replace function processar_rotina_diaria()
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_hoje       date := hoje_sp();
  v_r          record;
  v_reativadas int := 0;
  v_cobrancas  int := 0;
  v_falhas     text[] := '{}';
  v_voltas     int;
  v_atrasadas  int;
begin
  -- Retorno programado da pausa.
  for v_r in
    select id from assinaturas where status = 'pausada' and data_retorno_prevista <= v_hoje
  loop
    begin
      perform reativar_assinatura(v_r.id, v_hoje, 'Retorno programado da pausa');
      v_reativadas := v_reativadas + 1;
    exception when sqlstate 'OV001' then
      v_falhas := array_append(v_falhas, 'reativar ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  -- Cobranças vencidas até hoje (até 12 períodos atrasados por assinatura).
  for v_r in
    select id from assinaturas where status = 'ativa' and proxima_cobranca <= v_hoje
  loop
    v_voltas := 0;
    begin
      while v_voltas < 12
            and (select proxima_cobranca from assinaturas where id = v_r.id) <= v_hoje loop
        perform gerar_cobranca(v_r.id);
        v_cobrancas := v_cobrancas + 1;
        v_voltas := v_voltas + 1;
      end loop;
    exception when sqlstate 'OV001' or unique_violation then
      v_falhas := array_append(v_falhas, 'cobrar ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  v_atrasadas := marcar_faturas_atrasadas();

  return jsonb_build_object(
    'data', v_hoje,
    'reativadas', v_reativadas,
    'cobrancas_geradas', v_cobrancas,
    'faturas_atrasadas', v_atrasadas,
    'falhas', to_jsonb(v_falhas)
  );
end;
$$;

comment on function processar_rotina_diaria() is
  'Retornos de pausa programados, cobranças do período e faturas atrasadas. Pode rodar mais de uma vez por dia sem duplicar nada.';
revoke execute on function processar_rotina_diaria() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- 10. Auditoria: nomes para as novas ações e reposições auditadas
-- ───────────────────────────────────────────────────────────────────────────
create or replace function auditar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old     jsonb;
  v_new     jsonb;
  v_acao    text;
  v_id      text;
  v_ignorar text[] := array['atualizado_em'];
  v_st_ant  text;
  v_st_nov  text;
  v_st_mudou boolean;
  v_us_ant  text;
  v_us_nov  text;
  v_usuario text := nullif(current_setting('app.usuario_id', true), '');
  v_motivo  text := nullif(current_setting('app.motivo', true), '');
begin
  if tg_op <> 'INSERT' then v_old := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_new := to_jsonb(new); end if;
  v_id := coalesce(v_new, v_old) ->> 'id';

  -- Campos que mudam sozinhos, sem ninguém ter decidido nada, não geram linha.
  if tg_table_name = 'assinaturas' then
    v_ignorar := v_ignorar || array['proxima_entrega', 'proxima_cobranca'];
  end if;

  if tg_op = 'UPDATE' and (v_old - v_ignorar) = (v_new - v_ignorar) then
    return null;
  end if;

  v_st_ant := v_old ->> 'status';
  v_st_nov := v_new ->> 'status';
  v_st_mudou := v_st_ant is distinct from v_st_nov;
  v_us_ant := v_old ->> 'usuario_id';
  v_us_nov := v_new ->> 'usuario_id';

  v_acao := case tg_table_name

    when 'clientes' then case
      when tg_op = 'INSERT' then 'cliente_criado'
      when tg_op = 'DELETE' then 'cliente_removido'
      when v_us_ant is distinct from v_us_nov and v_us_nov is not null then 'conta_vinculada'
      when v_us_ant is distinct from v_us_nov then 'conta_desvinculada'
      else 'cliente_alterado'
    end

    when 'assinaturas' then case
      when tg_op = 'INSERT' then 'assinatura_criada'
      when tg_op = 'DELETE' then 'assinatura_removida'
      when v_st_mudou and v_st_nov = 'pausada'   then 'assinatura_pausada'
      when v_st_mudou and v_st_nov = 'cancelada' then 'assinatura_cancelada'
      when v_st_mudou and v_st_nov = 'encerrada' then 'assinatura_encerrada'
      when v_st_mudou and v_st_nov = 'ativa'     then 'assinatura_reativada'
      when (v_old ->> 'plano_id') is distinct from (v_new ->> 'plano_id') then 'plano_da_assinatura_alterado'
      when (v_old ->> 'forma_cobranca') is distinct from (v_new ->> 'forma_cobranca') then 'forma_cobranca_alterada'
      else 'assinatura_alterada'
    end

    when 'entregas' then case
      when tg_op = 'INSERT' then 'entrega_criada'
      when tg_op = 'DELETE' then 'entrega_removida'
      when v_st_mudou then 'entrega_marcada_' || v_st_nov
      else 'entrega_alterada'
    end

    when 'faturas' then case
      when tg_op = 'INSERT' then 'fatura_criada'
      when tg_op = 'DELETE' then 'fatura_removida'
      when v_st_mudou and v_st_nov = 'paga'      then 'pagamento_registrado'
      when v_st_mudou and v_st_nov = 'cancelada' then 'fatura_cancelada'
      when v_st_mudou and v_st_nov = 'atrasada'  then 'fatura_atrasada'
      else 'fatura_alterada'
    end

    when 'reposicoes' then case
      when tg_op = 'INSERT' then 'defeito_registrado'
      when tg_op = 'DELETE' then 'reposicao_removida'
      when v_st_mudou and v_st_nov = 'reposta'   then 'reposicao_realizada'
      when v_st_mudou and v_st_nov = 'cancelada' then 'reposicao_cancelada'
      else 'reposicao_alterada'
    end

    when 'solicitacoes_assinatura' then case
      when tg_op = 'INSERT' then 'solicitacao_criada'
      when v_st_mudou and v_st_nov = 'atendida' then 'solicitacao_atendida'
      when v_st_mudou and v_st_nov = 'recusada' then 'solicitacao_recusada'
      else 'solicitacao_alterada'
    end

    when 'config_negocio' then 'configuracao_alterada'
    when 'planos'         then 'plano_alterado'
    when 'faixas_cep_atendidas' then case tg_op
      when 'INSERT' then 'faixa_criada'
      when 'DELETE' then 'faixa_removida'
      else 'faixa_alterada'
    end

    else tg_table_name || '_' || lower(tg_op)
  end;

  insert into auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos, motivo)
  values (v_usuario, v_acao, tg_table_name, v_id, v_old, v_new, v_motivo);

  return null;
end;
$$;

revoke execute on function auditar() from public;

create trigger reposicoes_auditoria_tg
  after insert or update or delete on reposicoes
  for each row execute function auditar();


-- Down Migration

drop trigger if exists reposicoes_auditoria_tg on reposicoes;
drop function if exists processar_rotina_diaria();
drop function if exists resolver_solicitacao(uuid, status_solicitacao, text, boolean, date);
alter table solicitacoes_assinatura drop column if exists resposta;
drop function if exists gerar_cobranca(uuid);
drop function if exists definir_forma_cobranca(uuid, forma_cobranca);
drop function if exists definir_horario_entrega(uuid, time);
drop trigger if exists entregas_movem_reposicoes_tg on entregas;
drop function if exists entregas_movem_reposicoes();
drop function if exists cancelar_reposicao(uuid, text);
drop function if exists registrar_defeito(uuid, smallint, text);
drop function if exists proxima_entrega_pendente(uuid, uuid);
drop table if exists reposicoes;
drop function if exists reposicoes_antes_de_gravar();
drop type if exists status_reposicao;
alter table entregas drop column if exists horario_previsto;
drop index if exists faturas_periodo_unico_idx;
alter table faturas drop constraint if exists faturas_periodo_ordem,
                    drop constraint if exists faturas_periodo_completo,
                    drop column if exists periodo_fim,
                    drop column if exists periodo_inicio;
drop trigger if exists assinaturas_ciclo_tg on assinaturas;
drop function if exists assinaturas_ciclo();
drop index if exists assinaturas_retorno_idx;
drop index if exists assinaturas_proxima_cobranca_idx;
alter table assinaturas drop constraint if exists assinaturas_retorno_depois_da_pausa,
                        drop column if exists data_retorno_prevista,
                        drop column if exists pausada_em,
                        drop column if exists proxima_cobranca,
                        drop column if exists forma_cobranca;
drop type if exists forma_cobranca;
drop function if exists pausar_assinatura(uuid, text, date);

-- Volta pausar/reativar da Fase 5 (as versões acima usam colunas que saíram).
create or replace function pausar_assinatura(p_assinatura uuid, p_motivo text default null)
returns void language plpgsql set search_path = public as $$
declare v_ass assinaturas%rowtype;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then raise exception 'Assinatura não encontrada.' using errcode = 'OV001'; end if;
  if v_ass.status <> 'ativa' then raise exception 'Só assinaturas ativas podem ser pausadas.' using errcode = 'OV001'; end if;
  perform set_config('app.motivo', coalesce(p_motivo, ''), true);
  update assinaturas set status = 'pausada' where id = p_assinatura;
  perform cancelar_pendencias_da_assinatura(p_assinatura, 'assinatura pausada');
  update clientes set status = 'suspenso' where id = v_ass.cliente_id;
  perform set_config('app.motivo', '', true);
end; $$;
revoke execute on function pausar_assinatura(uuid, text) from public;

create or replace function reativar_assinatura(p_assinatura uuid, p_retorno date default null, p_motivo text default null)
returns void language plpgsql set search_path = public as $$
declare
  v_ass assinaturas%rowtype; v_cliente clientes%rowtype;
  v_retorno date := coalesce(p_retorno, hoje_sp()); v_primeira date;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then raise exception 'Assinatura não encontrada.' using errcode = 'OV001'; end if;
  if v_ass.status not in ('pausada', 'cancelada') then
    raise exception 'Só assinaturas pausadas ou canceladas podem ser reativadas.' using errcode = 'OV001'; end if;
  if v_retorno < hoje_sp() then raise exception 'A data de retorno não pode estar no passado.' using errcode = 'OV001'; end if;
  select * into v_cliente from clientes where id = v_ass.cliente_id for update;
  if not v_cliente.dentro_area_entrega then raise exception 'CEP fora da área de entrega.' using errcode = 'OV001'; end if;
  if exists (select 1 from assinaturas where cliente_id = v_ass.cliente_id and id <> p_assinatura and status in ('ativa', 'pausada')) then
    raise exception 'Este cliente já tem outra assinatura ativa ou pausada.' using errcode = 'OV001'; end if;
  perform set_config('app.motivo', coalesce(p_motivo, ''), true);
  update assinaturas set status = 'ativa', data_cancelamento = null, motivo_cancelamento = null where id = p_assinatura;
  v_primeira := data_primeira_entrega(v_retorno, v_ass.plano_id);
  while exists (select 1 from entregas where assinatura_id = p_assinatura and data_prevista = v_primeira and status in ('pendente', 'entregue')) loop
    v_primeira := data_proxima_entrega(v_primeira, v_ass.plano_id);
  end loop;
  insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
  values (p_assinatura, v_ass.cliente_id, v_primeira, coalesce(v_cliente.pentes_padrao, 1), coalesce(v_cliente.duzias_padrao, 0));
  update clientes set status = case when exists (select 1 from faturas where cliente_id = v_ass.cliente_id and status = 'paga')
    then 'ativo'::status_cliente else 'cadastro_andamento'::status_cliente end where id = v_ass.cliente_id;
  perform set_config('app.motivo', '', true);
end; $$;
revoke execute on function reativar_assinatura(uuid, date, text) from public;
-- auditar() fica na versão desta fase (compatível: só acrescenta nomes).
-- O valor 'cartao' de metodo_pagamento não sai sem recriar o tipo.
