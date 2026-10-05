-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 7 — área do assinante.
--
-- O assinante entra com a conta de login (Better Auth); o registro de negócio
-- dele é `clientes`. O elo entre os dois é `clientes.usuario_id`.
--
-- ⚠ DECISÃO DO DONO (25/09/2026), tomada contra a recomendação: o vínculo é
--   AUTOMÁTICO quando o e-mail da conta é igual ao e-mail do cliente.
--   Risco conhecido e aceito: o sistema ainda NÃO confirma e-mail. Quem criar
--   uma conta usando o e-mail de outra pessoa passa a ver os dados dela.
--   Salvaguardas (não mudam o comportamento escolhido):
--     • só vincula cliente que ainda não tem conta;
--     • só vincula conta de ASSINANTE (nunca a do dono);
--     • uma conta liga a um único cliente;
--     • o vínculo fica na auditoria (`conta_vinculada`), e o dono pode
--       desvincular na ficha do cliente;
--     • desvincular NÃO religa sozinho: o vínculo automático só roda na criação
--       da conta, na criação do cliente e quando o e-mail do cliente MUDA.
--   Recomendação registrada: exigir e-mail verificado antes de vincular, assim
--   que o sistema passar a enviar e-mail.
--
-- O assinante nunca escreve nas tabelas: lê o que é dele (RLS) e chama duas
-- funções — `atualizar_meus_dados` e `solicitar_alteracao_assinatura` — que
-- conferem a posse na primeira instrução.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Vínculo automático por e-mail
-- ───────────────────────────────────────────────────────────────────────────

-- Conta nova → procura um cliente sem conta com o mesmo e-mail.
create or replace function vincular_conta_ao_cliente()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from clientes where usuario_id = new.id) then
    update clientes
       set usuario_id = new.id
     where lower(email) = lower(new.email)
       and usuario_id is null;
  end if;
  return null;
end;
$$;

create trigger user_vincula_cliente_tg
  after insert on "user"
  for each row execute function vincular_conta_ao_cliente();

revoke execute on function vincular_conta_ao_cliente() from public;


-- Cliente novo (ou com e-mail que MUDOU) → procura uma conta de assinante.
create or replace function clientes_vincula_conta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.usuario_id is not null or new.email is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.email is not distinct from new.email then
    return new;      -- salvar sem trocar o e-mail não religa uma conta desvinculada
  end if;

  select u.id into new.usuario_id
    from "user" u
    join perfis p on p.id = u.id
   where lower(u.email) = lower(new.email)
     and p.papel = 'assinante'
     and not exists (select 1 from clientes c where c.usuario_id = u.id and c.id is distinct from new.id)
   limit 1;

  return new;
end;
$$;

create trigger clientes_vincula_conta_tg
  before insert or update of email on clientes
  for each row execute function clientes_vincula_conta();

revoke execute on function clientes_vincula_conta() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- 2. atualizar_meus_dados com o endereço completo
--
-- Mesmas garantias de antes (posse conferida na 1ª instrução, lista fechada de
-- campos). Nova: as mensagens de erro passam a ter o código OV001, que a
-- aplicação exibe. Campos novos entram no FIM, com default: quem chama por
-- nome não é afetado.
-- ───────────────────────────────────────────────────────────────────────────
drop function if exists atualizar_meus_dados(uuid, text, text, text, text, text, text, date, text);

create or replace function atualizar_meus_dados(
  p_cliente_id       uuid,
  p_nome             text default null,
  p_apelido          text default null,
  p_telefone         text default null,
  p_cep              text default null,
  p_endereco         text default null,
  p_complemento      text default null,
  p_data_nascimento  date default null,
  p_codigo_indicacao text default null,
  p_numero           text default null,
  p_bairro           text default null,
  p_cidade           text default null,
  p_estado           text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_telefone text;
  v_cep      text;
  v_codigo   text;
  v_estado   text;
begin
  -- SEMPRE a primeira instrução, antes de ler ou gravar qualquer coisa.
  if not (
    coalesce(sou_dono(), false)
    or exists (
      select 1 from clientes
      where id = p_cliente_id and usuario_id = app.usuario_id()
    )
  ) then
    raise exception 'Você não tem permissão para realizar esta ação.' using errcode = 'OV001';
  end if;

  if p_telefone is not null then
    v_telefone := regexp_replace(p_telefone, '\D', '', 'g');
    if length(v_telefone) not between 10 and 11 then
      raise exception 'Telefone precisa ter 10 ou 11 dígitos (com DDD).' using errcode = 'OV001';
    end if;
    v_telefone := '+55' || v_telefone;
  end if;

  if p_cep is not null then
    v_cep := regexp_replace(p_cep, '\D', '', 'g');
    if length(v_cep) <> 8 then
      raise exception 'CEP precisa ter 8 dígitos.' using errcode = 'OV001';
    end if;
  end if;

  if p_estado is not null then
    v_estado := upper(trim(p_estado));
    if v_estado !~ '^[A-Z]{2}$' then
      raise exception 'Estado inválido. Use a sigla, como MG.' using errcode = 'OV001';
    end if;
  end if;

  if p_codigo_indicacao is not null then
    v_codigo := upper(trim(p_codigo_indicacao));
    if v_codigo !~ '^[A-Z0-9-]{4,20}$' then
      raise exception 'Código de indicação inválido: use 4 a 20 letras, números ou hífen.' using errcode = 'OV001';
    end if;
    if exists (select 1 from clientes where codigo_indicacao = v_codigo and id <> p_cliente_id) then
      raise exception 'Esse código de indicação já está em uso.' using errcode = 'OV001';
    end if;
  end if;

  update clientes set
    nome             = coalesce(nullif(trim(p_nome), ''), nome),
    apelido          = coalesce(nullif(trim(p_apelido), ''), apelido),
    telefone         = coalesce(v_telefone, telefone),
    cep              = coalesce(v_cep, cep),
    endereco         = coalesce(nullif(trim(p_endereco), ''), endereco),
    numero           = coalesce(nullif(trim(p_numero), ''), numero),
    complemento      = coalesce(nullif(trim(p_complemento), ''), complemento),
    bairro           = coalesce(nullif(trim(p_bairro), ''), bairro),
    cidade           = coalesce(nullif(trim(p_cidade), ''), cidade),
    estado           = coalesce(v_estado, estado),
    data_nascimento  = coalesce(p_data_nascimento, data_nascimento),
    codigo_indicacao = coalesce(v_codigo, codigo_indicacao)
  where id = p_cliente_id;

  if not found then
    raise exception 'Cliente não encontrado.' using errcode = 'OV001';
  end if;
end;
$$;

comment on function atualizar_meus_dados(uuid, text, text, text, text, text, text, date, text, text, text, text, text) is
  'Único caminho para o cliente alterar os próprios dados. Lista fechada: status, plano, tipo, preço, e-mail e vínculo de conta não estão aqui.';

revoke execute on function atualizar_meus_dados(uuid, text, text, text, text, text, text, date, text, text, text, text, text) from public;
grant  execute on function atualizar_meus_dados(uuid, text, text, text, text, text, text, date, text, text, text, text, text) to app_usuario;


-- ───────────────────────────────────────────────────────────────────────────
-- 3. Solicitações do assinante (pedir pausa ou cancelamento)
--
-- O assinante PEDE; quem pausa ou cancela é o dono, na assinatura. Assim uma
-- conta comprometida não consegue cancelar um contrato sozinha.
-- ───────────────────────────────────────────────────────────────────────────
create type tipo_solicitacao   as enum ('pausa', 'cancelamento');
create type status_solicitacao as enum ('pendente', 'atendida', 'recusada');

create table solicitacoes_assinatura (
  id             uuid primary key default gen_random_uuid(),
  assinatura_id  uuid not null references assinaturas (id) on delete restrict,
  cliente_id     uuid not null references clientes (id)    on delete restrict,
  tipo           tipo_solicitacao   not null,
  motivo         text check (char_length(motivo) <= 500),
  status         status_solicitacao not null default 'pendente',
  criado_em      timestamptz not null default now(),
  resolvida_em   timestamptz,
  resolvida_por  text,
  check ((status = 'pendente') = (resolvida_em is null))
);

comment on table solicitacoes_assinatura is
  'Pedidos do assinante (pausa ou cancelamento). O dono trata: marca atendida ou recusada.';

create index solicitacoes_assinatura_idx on solicitacoes_assinatura (assinatura_id);
create index solicitacoes_status_idx     on solicitacoes_assinatura (status, criado_em);

-- Um pedido pendente de cada tipo por assinatura: clique duplo não enfileira dois.
create unique index solicitacoes_pendente_idx
  on solicitacoes_assinatura (assinatura_id, tipo)
  where status = 'pendente';

alter table solicitacoes_assinatura enable row level security;

revoke all on table solicitacoes_assinatura from app_anon, app_usuario;
grant select on table solicitacoes_assinatura to app_usuario;

create policy "solicitacoes: le as proprias, dono le todas"
  on solicitacoes_assinatura for select to app_usuario
  using (
    (select sou_dono())
    or exists (
      select 1 from clientes c
      where c.id = solicitacoes_assinatura.cliente_id
        and c.usuario_id = app.usuario_id()
    )
  );

create or replace function solicitar_alteracao_assinatura(
  p_assinatura uuid,
  p_tipo       tipo_solicitacao,
  p_motivo     text default null
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

  insert into solicitacoes_assinatura (assinatura_id, cliente_id, tipo, motivo)
  values (p_assinatura, v_ass.cliente_id, p_tipo, nullif(trim(p_motivo), ''))
  returning id into v_id;

  return v_id;
end;
$$;

comment on function solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text) is
  'O assinante pede pausa ou cancelamento da PRÓPRIA assinatura. Quem executa é o dono.';

revoke execute on function solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text) from public;
grant  execute on function solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text) to app_usuario;

create trigger solicitacoes_auditoria_tg
  after insert or update on solicitacoes_assinatura
  for each row execute function auditar();


-- Down Migration

drop trigger if exists solicitacoes_auditoria_tg on solicitacoes_assinatura;
drop function if exists solicitar_alteracao_assinatura(uuid, tipo_solicitacao, text);
drop policy if exists "solicitacoes: le as proprias, dono le todas" on solicitacoes_assinatura;
drop table if exists solicitacoes_assinatura;
drop type if exists status_solicitacao;
drop type if exists tipo_solicitacao;

drop function if exists atualizar_meus_dados(uuid, text, text, text, text, text, text, date, text, text, text, text, text);
create or replace function atualizar_meus_dados(
  p_cliente_id uuid, p_nome text default null, p_apelido text default null, p_telefone text default null,
  p_cep text default null, p_endereco text default null, p_complemento text default null,
  p_data_nascimento date default null, p_codigo_indicacao text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_telefone text; v_cep text; v_codigo text;
begin
  if not (coalesce(sou_dono(), false)
          or exists (select 1 from clientes where id = p_cliente_id and usuario_id = app.usuario_id())) then
    raise exception 'sem permissão para esta operação';
  end if;
  if p_telefone is not null then
    v_telefone := regexp_replace(p_telefone, '\D', '', 'g');
    if length(v_telefone) not between 10 and 11 then raise exception 'telefone inválido'; end if;
    v_telefone := '+55' || v_telefone;
  end if;
  if p_cep is not null then
    v_cep := regexp_replace(p_cep, '\D', '', 'g');
    if length(v_cep) <> 8 then raise exception 'CEP inválido'; end if;
  end if;
  if p_codigo_indicacao is not null then
    v_codigo := upper(trim(p_codigo_indicacao));
    if v_codigo !~ '^[A-Z0-9-]{4,20}$' then raise exception 'código de indicação inválido'; end if;
    if exists (select 1 from clientes where codigo_indicacao = v_codigo and id <> p_cliente_id) then
      raise exception 'esse código de indicação já está em uso';
    end if;
  end if;
  update clientes set
    nome = coalesce(nullif(trim(p_nome), ''), nome), apelido = coalesce(nullif(trim(p_apelido), ''), apelido),
    telefone = coalesce(v_telefone, telefone), cep = coalesce(v_cep, cep),
    endereco = coalesce(nullif(trim(p_endereco), ''), endereco),
    complemento = coalesce(nullif(trim(p_complemento), ''), complemento),
    data_nascimento = coalesce(p_data_nascimento, data_nascimento),
    codigo_indicacao = coalesce(v_codigo, codigo_indicacao)
  where id = p_cliente_id;
  if not found then raise exception 'cliente não encontrado'; end if;
end;
$$;
revoke execute on function atualizar_meus_dados(uuid, text, text, text, text, text, text, date, text) from public;
grant  execute on function atualizar_meus_dados(uuid, text, text, text, text, text, text, date, text) to app_usuario;

drop trigger if exists clientes_vincula_conta_tg on clientes;
drop function if exists clientes_vincula_conta();
drop trigger if exists user_vincula_cliente_tg on "user";
drop function if exists vincular_conta_ao_cliente();
