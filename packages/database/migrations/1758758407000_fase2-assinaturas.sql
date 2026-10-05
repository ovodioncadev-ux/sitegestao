-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 2 — assinaturas.
--
-- A assinatura é uma entidade PRÓPRIA, ligada a `clientes` e a `planos`:
--
--     cliente ──< assinatura >── plano
--
-- O cliente continua sendo o registro de negócio (quem é, onde mora). A
-- assinatura é o contrato no tempo: qual plano, desde quando, em que situação.
-- Cancelar NUNCA apaga: a linha continua, com status e data de cancelamento.
--
-- Convenção de erro: regra de negócio quebrada dentro do banco usa o código
-- SQLSTATE 'OV001'. É o sinal, para a aplicação, de que a mensagem é escrita
-- para a pessoa e pode ser exibida. Qualquer outro erro é tratado como interno.
--
-- Regras já decididas (DECISOES.md) que estas funções implementam:
--   • #13  intervalo em dias (7, 15, 30), com `planos.ancorar_em_quarta`
--          decidindo se a data é arredondada para a quarta mais próxima.
--   • #3   ao voltar de pausa, o calendário recomeça de hoje, ancorado na
--          próxima quarta (usado na Fase 5).
--   • #8   histórico completo: nenhuma chave estrangeira em cascade.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

create type status_assinatura as enum ('ativa', 'pausada', 'cancelada', 'encerrada');

comment on type status_assinatura is
  'ativa: recebe entregas. pausada: existe, sem entregas até reativar. '
  'cancelada: decisão de parar (com data e motivo). encerrada: chegou ao fim (data_fim).';

create table assinaturas (
  id                   uuid primary key default gen_random_uuid(),

  -- restrict nas duas: cliente ou plano com assinatura não se apaga.
  cliente_id           uuid     not null references clientes (id) on delete restrict,
  plano_id             smallint not null references planos (id)   on delete restrict,

  status               status_assinatura not null default 'ativa',
  data_inicio          date not null,
  data_fim             date,
  proxima_entrega      date,
  data_cancelamento    date,
  motivo_cancelamento  text check (char_length(motivo_cancelamento) <= 500),

  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now(),

  check (data_fim is null or data_fim >= data_inicio),
  -- Cancelada TEM data de cancelamento, e só ela tem.
  check ((status = 'cancelada') = (data_cancelamento is not null)),
  check (motivo_cancelamento is null or status = 'cancelada')
);

comment on table assinaturas is
  'Contrato no tempo: cliente + plano + situação. Nunca é apagada; cancelar muda o status.';
comment on column assinaturas.proxima_entrega is
  'Data prevista da próxima entrega pendente. Mantida pelo banco a partir de `entregas`; ninguém a escreve à mão.';
comment on column assinaturas.data_cancelamento is
  'Preenchida só enquanto status = cancelada. Ao reativar ela é zerada — o valor anterior fica na auditoria.';

create index assinaturas_cliente_idx on assinaturas (cliente_id);
create index assinaturas_plano_idx   on assinaturas (plano_id);
create index assinaturas_status_idx  on assinaturas (status);

-- Uma assinatura VIGENTE (ativa ou pausada) por cliente. Cancelada e
-- encerrada podem se acumular: é o histórico.
create unique index assinaturas_vigente_idx
  on assinaturas (cliente_id)
  where status in ('ativa', 'pausada');

comment on index assinaturas_vigente_idx is
  'No máximo uma assinatura ativa ou pausada por cliente. Impede duas assinaturas correndo ao mesmo tempo por descuido.';


-- ───────────────────────────────────────────────────────────────────────────
-- Gatilho: imutáveis e carimbo de atualização
-- ───────────────────────────────────────────────────────────────────────────
create or replace function assinaturas_antes_de_gravar()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    new.id         := old.id;
    new.cliente_id := old.cliente_id;   -- assinatura não muda de dono
    new.criado_em  := old.criado_em;
  end if;
  new.atualizado_em := now();
  return new;
end;
$$;

create trigger assinaturas_antes_de_gravar_tg
  before insert or update on assinaturas
  for each row execute function assinaturas_antes_de_gravar();

revoke execute on function assinaturas_antes_de_gravar() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- RLS — o assinante lê só a própria; o dono lê todas; ninguém escreve direto
-- ───────────────────────────────────────────────────────────────────────────
alter table assinaturas enable row level security;

revoke all on table assinaturas from app_anon, app_usuario;
grant select on table assinaturas to app_usuario;
-- Nenhum grant de insert/update/delete. Escrita só pela conexão administrativa
-- (painel do dono), depois de exigirDono().

create policy "assinaturas: le a propria, dono le todas"
  on assinaturas for select to app_usuario
  using (
    (select sou_dono())
    or exists (
      select 1 from clientes c
      where c.id = assinaturas.cliente_id
        and c.usuario_id = app.usuario_id()
    )
  );


-- ───────────────────────────────────────────────────────────────────────────
-- Datas. "Hoje" é sempre o de São Paulo, nunca o do servidor (que é UTC).
-- ───────────────────────────────────────────────────────────────────────────
create or replace function hoje_sp()
returns date
language sql
stable
set search_path = public
as $$
  select (now() at time zone 'America/Sao_Paulo')::date;
$$;

-- Primeira quarta-feira a partir de p_data, contando o próprio dia.
create or replace function proxima_quarta(p_data date)
returns date
language sql
immutable
set search_path = public
as $$
  select p_data + ((3 - extract(dow from p_data)::int + 7) % 7);
$$;

-- A quarta-feira mais perto de p_data (para trás ou para a frente).
create or replace function quarta_mais_proxima(p_data date)
returns date
language sql
immutable
set search_path = public
as $$
  select p_data + (case when d > 3 then d - 7 else d end)
  from (select ((3 - extract(dow from p_data)::int + 7) % 7) as d) x;
$$;

-- Data da PRIMEIRA entrega de uma assinatura que começa em p_inicio.
create or replace function data_primeira_entrega(p_inicio date, p_plano smallint)
returns date
language plpgsql
stable
set search_path = public
as $$
declare
  v_ancorar boolean;
begin
  select ancorar_em_quarta into v_ancorar from planos where id = p_plano;
  if not found then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;
  return case when v_ancorar then proxima_quarta(p_inicio) else p_inicio end;
end;
$$;

-- Data da entrega seguinte à de p_base: soma o intervalo do plano (7, 15 ou
-- 30 dias) e, se o plano ancora em quarta, arredonda para a quarta mais perto.
-- Nunca devolve uma data igual ou anterior à base.
create or replace function data_proxima_entrega(p_base date, p_plano smallint)
returns date
language plpgsql
stable
set search_path = public
as $$
declare
  v_plano planos%rowtype;
  v_data  date;
begin
  select * into v_plano from planos where id = p_plano;
  if not found then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;

  v_data := p_base + v_plano.intervalo_dias;
  if v_plano.ancorar_em_quarta then
    v_data := quarta_mais_proxima(v_data);
  end if;
  if v_data <= p_base then
    v_data := p_base + v_plano.intervalo_dias;
  end if;
  return v_data;
end;
$$;

revoke execute on function hoje_sp()                              from public;
revoke execute on function proxima_quarta(date)                   from public;
revoke execute on function quarta_mais_proxima(date)              from public;
revoke execute on function data_primeira_entrega(date, smallint)  from public;
revoke execute on function data_proxima_entrega(date, smallint)   from public;


-- ───────────────────────────────────────────────────────────────────────────
-- Criar assinatura
--
-- Só a conexão administrativa executa (nenhum grant): o painel chama depois
-- de exigirDono(). Confere tudo aqui dentro também — a aplicação valida o
-- formato, o banco decide o que é verdade.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function criar_assinatura(
  p_cliente uuid,
  p_plano   smallint,
  p_inicio  date default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_cliente clientes%rowtype;
  v_inicio  date := coalesce(p_inicio, hoje_sp());
  v_id      uuid;
begin
  select * into v_cliente from clientes where id = p_cliente for update;
  if not found then
    raise exception 'Cliente não encontrado.' using errcode = 'OV001';
  end if;

  if not exists (select 1 from planos where id = p_plano and ativo) then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;

  if v_cliente.cep is null or v_cliente.endereco is null then
    raise exception 'Cliente sem endereço: preencha o CEP e o endereço antes de criar a assinatura.'
      using errcode = 'OV001';
  end if;

  if not v_cliente.dentro_area_entrega then
    raise exception 'CEP fora da área de entrega.' using errcode = 'OV001';
  end if;

  if exists (
    select 1 from assinaturas where cliente_id = p_cliente and status in ('ativa', 'pausada')
  ) then
    raise exception 'Este cliente já tem uma assinatura ativa ou pausada.' using errcode = 'OV001';
  end if;

  insert into assinaturas (cliente_id, plano_id, status, data_inicio, proxima_entrega)
  values (p_cliente, p_plano, 'ativa', v_inicio, data_primeira_entrega(v_inicio, p_plano))
  returning id into v_id;

  -- O plano do cliente acompanha a assinatura (fonte da verdade: a assinatura).
  update clientes set plano_id = p_plano where id = p_cliente and plano_id is distinct from p_plano;

  return v_id;
end;
$$;

revoke execute on function criar_assinatura(uuid, smallint, date) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- Trocar o plano de uma assinatura vigente
-- ───────────────────────────────────────────────────────────────────────────
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
  if not exists (select 1 from planos where id = p_plano and ativo) then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;

  update assinaturas set plano_id = p_plano where id = p_assinatura;
  update clientes set plano_id = p_plano where id = v_ass.cliente_id and plano_id is distinct from p_plano;
end;
$$;

revoke execute on function alterar_plano_assinatura(uuid, smallint) from public;


-- Down Migration

drop function if exists alterar_plano_assinatura(uuid, smallint);
drop function if exists criar_assinatura(uuid, smallint, date);
drop function if exists data_proxima_entrega(date, smallint);
drop function if exists data_primeira_entrega(date, smallint);
drop function if exists quarta_mais_proxima(date);
drop function if exists proxima_quarta(date);
drop function if exists hoje_sp();
drop policy if exists "assinaturas: le a propria, dono le todas" on assinaturas;
drop trigger if exists assinaturas_antes_de_gravar_tg on assinaturas;
drop function if exists assinaturas_antes_de_gravar();
drop table if exists assinaturas;
drop type if exists status_assinatura;
