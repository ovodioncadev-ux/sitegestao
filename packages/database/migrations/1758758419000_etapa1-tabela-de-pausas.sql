-- ═══════════════════════════════════════════════════════════════════════════
-- Etapa 1 (2/4) — histórico permanente de pausas.
--
-- Até aqui a pausa vivia em duas colunas de `assinaturas` (`pausada_em`,
-- `data_retorno_prevista`) que o gatilho `assinaturas_ciclo` APAGA ao
-- reativar: a única memória de uma pausa passada era o JSON da auditoria.
-- Agora cada pausa é uma linha própria, que nunca some.
--
--   assinatura ──< pausas_assinatura       (uma assinatura, várias pausas)
--
-- É só ESTRUTURA. Esta migration não implementa nenhuma regra de pausa
-- (crédito, extensão de ciclo, redução de fatura, limite de 60 dias, aviso
-- ao dono): D3, D4 e D5 chegam em etapa própria e vão usar esta tabela.
--
-- Compatibilidade: as colunas antigas de `assinaturas` continuam existindo e
-- sendo usadas por pausar_assinatura / reativar_assinatura / rotina diária,
-- sem nenhuma alteração. Um gatilho só ESPELHA a mudança de status na tabela
-- nova (abre a pausa ao pausar, fecha ao sair de `pausada`), para o histórico
-- já começar a ser escrito e não haver buraco entre as etapas.
-- Quando D3–D5 forem implementados, decidir se as colunas antigas saem.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

create type status_pausa as enum ('ativa', 'encerrada');

create table pausas_assinatura (
  id                uuid primary key default gen_random_uuid(),

  -- Histórico nunca é apagado (DECISOES #8): restrict, não cascade.
  assinatura_id     uuid not null references assinaturas (id) on delete restrict,
  cliente_id        uuid not null references clientes (id)    on delete restrict,

  inicio            date not null,
  retorno_previsto  date,
  retorno_efetivo   date,
  status            status_pausa not null default 'ativa',
  motivo            text check (char_length(motivo) <= 500),

  -- Quem agiu: id do usuário (`app.usuario_id`) no momento; nulo para a rotina
  -- automática, que não tem usuário. Sem FK: o registro sobrevive à conta.
  criada_por        text,
  encerrada_por     text,

  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),

  check (retorno_previsto is null or retorno_previsto > inicio),
  check (retorno_efetivo  is null or retorno_efetivo  >= inicio),
  -- Ativa não tem retorno efetivo; encerrada tem.
  check ((status = 'ativa') = (retorno_efetivo is null))
);

comment on table pausas_assinatura is
  'Histórico de pausas de cada assinatura. Uma linha por pausa; nunca apagada. Base de D3, D4 e D5 (ainda não implementadas).';
comment on column pausas_assinatura.retorno_previsto is 'Retorno combinado ao pausar, se houve. Pode ser nulo (pausa sem data).';
comment on column pausas_assinatura.retorno_efetivo  is 'Dia em que a pausa realmente terminou. Nulo enquanto ativa.';
comment on column pausas_assinatura.criada_por is 'usuario_id de quem pausou; nulo se foi a rotina automática.';

create index pausas_assinatura_idx on pausas_assinatura (assinatura_id, inicio desc);
create index pausas_cliente_idx    on pausas_assinatura (cliente_id);
create index pausas_retorno_idx    on pausas_assinatura (retorno_previsto) where status = 'ativa';

-- No máximo uma pausa ativa por assinatura.
create unique index pausas_uma_ativa_idx on pausas_assinatura (assinatura_id) where status = 'ativa';


create or replace function pausas_antes_de_gravar()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if not exists (
      select 1 from assinaturas where id = new.assinatura_id and cliente_id = new.cliente_id
    ) then
      raise exception 'A pausa precisa ser do mesmo cliente da assinatura.' using errcode = 'OV001';
    end if;
  else
    -- O que identifica e originou a pausa não muda. (O início pode ser corrigido.)
    new.id            := old.id;
    new.assinatura_id := old.assinatura_id;
    new.cliente_id    := old.cliente_id;
    new.criada_por    := old.criada_por;
    new.criado_em     := old.criado_em;
  end if;

  -- Duas pausas da mesma assinatura não se sobrepõem no tempo.
  if exists (
    select 1 from pausas_assinatura p
     where p.assinatura_id = new.assinatura_id
       and p.id <> new.id
       and daterange(p.inicio,   coalesce(p.retorno_efetivo,   'infinity'::date), '[)')
        && daterange(new.inicio, coalesce(new.retorno_efetivo, 'infinity'::date), '[)')
  ) then
    raise exception 'Esta assinatura já tem uma pausa nesse período.' using errcode = 'OV001';
  end if;

  new.atualizado_em := now();
  return new;
end;
$$;

create trigger pausas_antes_de_gravar_tg
  before insert or update on pausas_assinatura
  for each row execute function pausas_antes_de_gravar();

revoke execute on function pausas_antes_de_gravar() from public;


-- RLS: o assinante vê as próprias pausas; o dono, todas; ninguém escreve direto.
alter table pausas_assinatura enable row level security;

revoke all on table pausas_assinatura from app_anon, app_usuario;
grant select on table pausas_assinatura to app_usuario;

create policy "pausas: le as proprias, dono le todas"
  on pausas_assinatura for select to app_usuario
  using (
    (select sou_dono())
    or exists (
      select 1 from clientes c
      where c.id = pausas_assinatura.cliente_id
        and c.usuario_id = app.usuario_id()
    )
  );


-- ───────────────────────────────────────────────────────────────────────────
-- Espelho: a mudança de status da assinatura escreve o histórico.
-- Não altera nada na assinatura; só reage a ela. E NUNCA deve bloquear a
-- operação: um retorno que não seja posterior ao início (estado que a própria
-- assinatura já impede quando há `pausada_em`) fica de fora do espelho em vez
-- de derrubar a pausa.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function assinaturas_espelham_pausa()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_usuario text := nullif(current_setting('app.usuario_id', true), '');
  v_motivo  text := nullif(current_setting('app.motivo', true), '');
  v_inicio  date := coalesce(new.pausada_em, hoje_sp());
begin
  if new.status = 'pausada' and old.status is distinct from 'pausada' then
    insert into pausas_assinatura (assinatura_id, cliente_id, inicio, retorno_previsto, motivo, criada_por)
    values (new.id, new.cliente_id, v_inicio,
            case when new.data_retorno_prevista > v_inicio then new.data_retorno_prevista end,
            left(v_motivo, 500), v_usuario);

  elsif old.status = 'pausada' and new.status <> 'pausada' then
    update pausas_assinatura
       set status = 'encerrada',
           retorno_efetivo = greatest(hoje_sp(), inicio),
           encerrada_por = v_usuario
     where assinatura_id = new.id and status = 'ativa';

  elsif new.status = 'pausada'
        and (new.data_retorno_prevista is distinct from old.data_retorno_prevista
             or new.pausada_em is distinct from old.pausada_em) then
    update pausas_assinatura
       set inicio = coalesce(new.pausada_em, inicio),
           retorno_previsto = case
             when new.data_retorno_prevista is null then null
             when new.data_retorno_prevista > coalesce(new.pausada_em, inicio) then new.data_retorno_prevista
             else retorno_previsto
           end
     where assinatura_id = new.id and status = 'ativa';
  end if;
  return null;
end;
$$;

create trigger assinaturas_espelham_pausa_tg
  after update of status, data_retorno_prevista, pausada_em on assinaturas
  for each row execute function assinaturas_espelham_pausa();

revoke execute on function assinaturas_espelham_pausa() from public;


-- Assinaturas que JÁ estão pausadas agora e têm data de início da pausa:
-- informação inequívoca, entra no histórico. Pausas passadas (já encerradas)
-- só existem na auditoria e NÃO são reconstruídas aqui.
insert into pausas_assinatura (assinatura_id, cliente_id, inicio, retorno_previsto)
select a.id, a.cliente_id, a.pausada_em, a.data_retorno_prevista
  from assinaturas a
 where a.status = 'pausada' and a.pausada_em is not null
   and not exists (select 1 from pausas_assinatura p where p.assinatura_id = a.id and p.status = 'ativa');


-- Down Migration

drop trigger if exists assinaturas_espelham_pausa_tg on assinaturas;
drop function if exists assinaturas_espelham_pausa();
drop policy if exists "pausas: le as proprias, dono le todas" on pausas_assinatura;
drop trigger if exists pausas_antes_de_gravar_tg on pausas_assinatura;
drop function if exists pausas_antes_de_gravar();
drop table if exists pausas_assinatura;
drop type if exists status_pausa;
