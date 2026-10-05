-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 3 — entregas.
--
--     cliente ──< assinatura ──< entrega
--
-- Uma entrega é uma data prevista para uma assinatura, com a situação dela
-- (pendente, entregue, não entregue, cancelada). O calendário NÃO é gerado
-- de uma vez para meses à frente: existe sempre UMA entrega pendente por
-- assinatura ativa, e ao marcar a atual como entregue o banco cria a seguinte
-- (data da atual + intervalo do plano, ancorada na quarta — ver Fase 2).
-- Isso evita ter que decidir "quantos meses gerar" e evita calendário velho
-- quando o plano muda.
--
-- Regras já decididas (DECISOES.md) que estas funções implementam:
--   • #5   entrega que falha REAGENDA: ao marcar "não entregue" o dono informa
--          a nova data e o banco cria a nova entrega pendente. Não cobra a mais.
--   • #8   nada de cascade; entrega nunca some com o cliente.
--   • #3   pausa/cancelamento cancelam as entregas pendentes (Fase 5).
--
-- O que NÃO foi decidido e está sinalizado, não inventado:
--   • quantidade por entrega: vem de clientes.pentes_padrao / duzias_padrao;
--     se o pente padrão estiver vazio, usa 1 (o pente é o produto).
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

create type status_entrega as enum ('pendente', 'entregue', 'nao_entregue', 'cancelada');

create table entregas (
  id              uuid primary key default gen_random_uuid(),

  assinatura_id   uuid not null references assinaturas (id) on delete restrict,
  -- Redundante com a assinatura, de propósito: é o que a agenda e a RLS
  -- consultam. O gatilho abaixo garante que os dois nunca discordem.
  cliente_id      uuid not null references clientes (id)    on delete restrict,

  data_prevista   date not null,
  data_realizada  timestamptz,
  status          status_entrega not null default 'pendente',
  observacao      text check (char_length(observacao) <= 500),

  pentes          smallint not null default 1 check (pentes between 1 and 50),
  duzias          smallint not null default 0 check (duzias between 0 and 50),

  -- Preenchido quando esta entrega nasceu de um reagendamento.
  reagendada_de   uuid references entregas (id) on delete restrict,

  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),

  -- Entregue TEM data de realização, e só ela tem.
  check ((status = 'entregue') = (data_realizada is not null))
);

comment on table entregas is
  'Uma data prevista de entrega para uma assinatura. Sempre existe uma pendente por assinatura ativa; ao marcar a atual como entregue, a seguinte é criada.';
comment on column entregas.cliente_id is
  'Redundante com assinaturas.cliente_id, para a agenda e a RLS. Um gatilho garante que coincidem.';
comment on column entregas.reagendada_de is
  'Entrega "não entregue" que originou esta (DECISOES.md #5: falha reagenda).';

create index entregas_assinatura_idx on entregas (assinatura_id);
create index entregas_cliente_idx    on entregas (cliente_id);
create index entregas_status_idx     on entregas (status);
create index entregas_pendentes_idx  on entregas (data_prevista) where status = 'pendente';

-- Nunca duas entregas vivas (pendente ou entregue) da mesma assinatura no
-- mesmo dia. Não entregue e cancelada não contam: são o histórico.
create unique index entregas_data_unica_idx
  on entregas (assinatura_id, data_prevista)
  where status in ('pendente', 'entregue');


-- ───────────────────────────────────────────────────────────────────────────
-- Gatilhos
-- ───────────────────────────────────────────────────────────────────────────
create or replace function entregas_antes_de_gravar()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if not exists (
      select 1 from assinaturas where id = new.assinatura_id and cliente_id = new.cliente_id
    ) then
      raise exception 'A entrega precisa ser do mesmo cliente da assinatura.' using errcode = 'OV001';
    end if;
  else
    new.id            := old.id;
    new.assinatura_id := old.assinatura_id;
    new.cliente_id    := old.cliente_id;
    new.reagendada_de := old.reagendada_de;
    new.criado_em     := old.criado_em;
  end if;
  new.atualizado_em := now();
  return new;
end;
$$;

create trigger entregas_antes_de_gravar_tg
  before insert or update on entregas
  for each row execute function entregas_antes_de_gravar();

revoke execute on function entregas_antes_de_gravar() from public;

-- assinaturas.proxima_entrega é sempre a menor data pendente. Ninguém a
-- escreve à mão, então ela não pode ficar velha.
create or replace function entregas_sincroniza_assinatura()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_ass  uuid := coalesce(new.assinatura_id, old.assinatura_id);
  v_prox date;
begin
  select min(data_prevista) into v_prox
    from entregas where assinatura_id = v_ass and status = 'pendente';

  update assinaturas set proxima_entrega = v_prox
   where id = v_ass and proxima_entrega is distinct from v_prox;
  return null;
end;
$$;

create trigger entregas_sincroniza_assinatura_tg
  after insert or update of status, data_prevista or delete on entregas
  for each row execute function entregas_sincroniza_assinatura();

revoke execute on function entregas_sincroniza_assinatura() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- RLS — o assinante lê as próprias; o dono lê todas; ninguém escreve direto
-- ───────────────────────────────────────────────────────────────────────────
alter table entregas enable row level security;

revoke all on table entregas from app_anon, app_usuario;
grant select on table entregas to app_usuario;

create policy "entregas: le as proprias, dono le todas"
  on entregas for select to app_usuario
  using (
    (select sou_dono())
    or exists (
      select 1 from clientes c
      where c.id = entregas.cliente_id
        and c.usuario_id = app.usuario_id()
    )
  );


-- ───────────────────────────────────────────────────────────────────────────
-- criar_assinatura agora também cria a primeira entrega
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
  v_primeira date;
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

  v_primeira := data_primeira_entrega(v_inicio, p_plano);

  insert into assinaturas (cliente_id, plano_id, status, data_inicio, proxima_entrega)
  values (p_cliente, p_plano, 'ativa', v_inicio, v_primeira)
  returning id into v_id;

  insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
  values (v_id, p_cliente, v_primeira,
          coalesce(v_cliente.pentes_padrao, 1), coalesce(v_cliente.duzias_padrao, 0));

  update clientes set plano_id = p_plano where id = p_cliente and plano_id is distinct from p_plano;

  return v_id;
end;
$$;

revoke execute on function criar_assinatura(uuid, smallint, date) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- Marcar uma entrega pendente
--
--   entregue      grava a data/hora e, se a assinatura está ativa e não há outra
--                 pendente, cria a próxima (data da atual, ou de hoje se a
--                 entrega atrasou, + intervalo do plano, ancorada na quarta).
--   nao_entregue  se vier p_reagendar, cria a nova pendente nessa data.
--   cancelada     só encerra esta entrega.
--
-- Só sai de "pendente": uma entrega já resolvida não é reaberta por engano.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function marcar_entrega(
  p_entrega    uuid,
  p_status     status_entrega,
  p_observacao text default null,
  p_reagendar  date default null
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_e    entregas%rowtype;
  v_ass  assinaturas%rowtype;
  v_obs  text;
  v_base date;
begin
  select * into v_e from entregas where id = p_entrega for update;
  if not found then
    raise exception 'Entrega não encontrada.' using errcode = 'OV001';
  end if;

  if p_status not in ('entregue', 'nao_entregue', 'cancelada') then
    raise exception 'Situação inválida para a entrega.' using errcode = 'OV001';
  end if;

  if v_e.status <> 'pendente' then
    raise exception 'Só entregas pendentes podem ser marcadas.' using errcode = 'OV001';
  end if;

  select * into v_ass from assinaturas where id = v_e.assinatura_id for update;

  if p_reagendar is not null then
    if p_status <> 'nao_entregue' then
      raise exception 'Só é possível reagendar uma entrega marcada como não entregue.' using errcode = 'OV001';
    end if;
    if v_ass.status <> 'ativa' then
      raise exception 'Só assinaturas ativas podem ter entrega reagendada.' using errcode = 'OV001';
    end if;
    if p_reagendar < hoje_sp() then
      raise exception 'A nova data não pode estar no passado.' using errcode = 'OV001';
    end if;
  end if;

  v_obs := coalesce(nullif(trim(p_observacao), ''), v_e.observacao);

  update entregas
     set status         = p_status,
         data_realizada = case when p_status = 'entregue' then now() else null end,
         observacao     = v_obs
   where id = p_entrega;

  if p_status = 'entregue'
     and v_ass.status = 'ativa'
     and not exists (
       select 1 from entregas where assinatura_id = v_e.assinatura_id and status = 'pendente'
     )
  then
    v_base := greatest(v_e.data_prevista, hoje_sp());
    insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
    values (v_e.assinatura_id, v_e.cliente_id,
            data_proxima_entrega(v_base, v_ass.plano_id), v_e.pentes, v_e.duzias);
  end if;

  if p_status = 'nao_entregue' and p_reagendar is not null then
    insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias, reagendada_de, observacao)
    values (v_e.assinatura_id, v_e.cliente_id, p_reagendar, v_e.pentes, v_e.duzias, p_entrega,
            'Reagendada da entrega de ' || to_char(v_e.data_prevista, 'DD/MM/YYYY'));
  end if;
end;
$$;

revoke execute on function marcar_entrega(uuid, status_entrega, text, date) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- Agendar uma entrega à mão (assinatura sem entrega pendente, ou extra)
-- ───────────────────────────────────────────────────────────────────────────
create or replace function agendar_entrega(p_assinatura uuid, p_data date)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass     assinaturas%rowtype;
  v_cliente clientes%rowtype;
  v_id      uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' then
    raise exception 'Só assinaturas ativas recebem entregas.' using errcode = 'OV001';
  end if;
  if p_data is null then
    raise exception 'Informe a data da entrega.' using errcode = 'OV001';
  end if;
  if p_data < hoje_sp() then
    raise exception 'A data da entrega não pode estar no passado.' using errcode = 'OV001';
  end if;

  select * into v_cliente from clientes where id = v_ass.cliente_id;

  insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
  values (p_assinatura, v_ass.cliente_id, p_data,
          coalesce(v_cliente.pentes_padrao, 1), coalesce(v_cliente.duzias_padrao, 0))
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function agendar_entrega(uuid, date) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- Observação da entrega — pode ser escrita a qualquer momento
-- ───────────────────────────────────────────────────────────────────────────
create or replace function observacao_entrega(p_entrega uuid, p_observacao text)
returns void
language plpgsql
set search_path = public
as $$
begin
  update entregas set observacao = nullif(trim(p_observacao), '') where id = p_entrega;
  if not found then
    raise exception 'Entrega não encontrada.' using errcode = 'OV001';
  end if;
end;
$$;

revoke execute on function observacao_entrega(uuid, text) from public;


-- Down Migration

drop function if exists observacao_entrega(uuid, text);
drop function if exists agendar_entrega(uuid, date);
drop function if exists marcar_entrega(uuid, status_entrega, text, date);

-- Volta o criar_assinatura da Fase 2 (sem criar entrega).
create or replace function criar_assinatura(p_cliente uuid, p_plano smallint, p_inicio date default null)
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
  if not found then raise exception 'Cliente não encontrado.' using errcode = 'OV001'; end if;
  if not exists (select 1 from planos where id = p_plano and ativo) then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;
  if v_cliente.cep is null or v_cliente.endereco is null then
    raise exception 'Cliente sem endereço: preencha o CEP e o endereço antes de criar a assinatura.' using errcode = 'OV001';
  end if;
  if not v_cliente.dentro_area_entrega then
    raise exception 'CEP fora da área de entrega.' using errcode = 'OV001';
  end if;
  if exists (select 1 from assinaturas where cliente_id = p_cliente and status in ('ativa', 'pausada')) then
    raise exception 'Este cliente já tem uma assinatura ativa ou pausada.' using errcode = 'OV001';
  end if;
  insert into assinaturas (cliente_id, plano_id, status, data_inicio, proxima_entrega)
  values (p_cliente, p_plano, 'ativa', v_inicio, data_primeira_entrega(v_inicio, p_plano))
  returning id into v_id;
  update clientes set plano_id = p_plano where id = p_cliente and plano_id is distinct from p_plano;
  return v_id;
end;
$$;
revoke execute on function criar_assinatura(uuid, smallint, date) from public;

drop policy if exists "entregas: le as proprias, dono le todas" on entregas;
drop trigger if exists entregas_sincroniza_assinatura_tg on entregas;
drop function if exists entregas_sincroniza_assinatura();
drop trigger if exists entregas_antes_de_gravar_tg on entregas;
drop function if exists entregas_antes_de_gravar();
drop table if exists entregas;
drop type if exists status_entrega;
