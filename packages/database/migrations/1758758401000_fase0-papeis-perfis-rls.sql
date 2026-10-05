-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 0 — fundação de autorização, em PostgreSQL puro.
--
-- Este arquivo é a tradução do desenho do Supabase para papéis nossos:
--
--   chave anon            → papel app_anon    (NOLOGIN)
--   chave anon + sessão   → papel app_usuario (NOLOGIN)
--   chave service_role    → a dona das tabelas, em conexão SEPARADA
--   auth.uid()            → app.usuario_id()
--
-- A conexão normal entra como app_servidor, que é membro de app_anon e
-- app_usuario e NÃO consegue virar a dona. A cada requisição o servidor
-- abre uma transação e executa, antes de qualquer consulta:
--
--   set local role app_usuario;
--   set local app.usuario_id = '<id de quem está logado>';
--
-- O `set local` morre junto com a transação, então nem com pool de conexão
-- o contexto de um usuário vaza para o próximo.
--
-- O teste que decide se isto vale: logado como assinante, tentar virar dono.
-- Precisa falhar. Enquanto não falhar, não existe sistema.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

-- ───────────────────────────────────────────────────────────────────────────
-- 0. Função nova não nasce chamável por qualquer um
--
-- No Postgres, `create or replace function` PRESERVA as permissões, mas
-- `drop` + `create` NÃO: a função nova nasce com EXECUTE concedido a PUBLIC.
-- Foi assim que funções internas ficaram públicas no sistema anterior — a
-- migration de hardening revogou, uma migration posterior deu drop e recriou,
-- e o revoke se perdeu em silêncio.
--
-- ⚠️  A forma `in schema public` NÃO funciona para funções: o Postgres aceita
--     o comando sem reclamar, não grava nada em pg_default_acl, e a função
--     seguinte continua executável por PUBLIC. Conferido no Postgres 16.
--     A forma que vale é esta, do banco inteiro, sem `in schema`.
--
-- Isto é a terceira camada, não a primeira: toda função `security definer`
-- continua conferindo autorização no próprio corpo, e toda migration que
-- recria uma função reaplica o revoke dela.
-- ───────────────────────────────────────────────────────────────────────────
alter default privileges revoke execute on functions from public;


-- ───────────────────────────────────────────────────────────────────────────
-- 1. Os dois papéis de aplicação
--
-- NOLOGIN: ninguém se conecta como eles. Eles só existem para o servidor
-- vestir com `set local role` depois de já saber quem é a pessoa.
-- ───────────────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_anon') then
    create role app_anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'app_usuario') then
    create role app_usuario nologin;
  end if;
end;
$$;

comment on role app_anon    is 'Visitante sem login. Não alcança nada por padrão.';
comment on role app_usuario is 'Qualquer pessoa autenticada. O que ela vê é o que a RLS deixar.';


-- ───────────────────────────────────────────────────────────────────────────
-- 2. O contexto da requisição
--
-- `app` guarda só a plumbing de contexto. O negócio fica em `public`.
-- ───────────────────────────────────────────────────────────────────────────
create schema if not exists app;
grant usage on schema app to app_anon, app_usuario;
grant usage on schema public to app_anon, app_usuario;

create or replace function app.usuario_id()
returns text
language sql
stable
set search_path = app, public
as $$
  -- O `true` no current_setting é o que evita erro quando o parâmetro
  -- nunca foi setado: devolve null em vez de estourar.
  select nullif(current_setting('app.usuario_id', true), '');
$$;

comment on function app.usuario_id() is
  'Quem está logado nesta transação, ou null. Equivale ao auth.uid() do Supabase.';

revoke execute on function app.usuario_id() from public;
grant execute on function app.usuario_id() to app_anon, app_usuario;


-- ───────────────────────────────────────────────────────────────────────────
-- 3. Papéis de negócio
--
-- Dois papéis, e só. Decidido em 24/09/2026 (ver DECISOES.md):
--
--   • `entregador` não existe — o Fred e a Bruna entregam, não há entregador.
--   • `producao`  não existe aqui — a granja já tem um app próprio, que não
--     será conectado a este sistema por enquanto.
--
-- Acrescentar papel depois é barato (`alter type ... add value`). Tirar um que
-- já virou dependência de policy é caro. Por isso nenhum dos dois entra "por
-- garantia".
-- ───────────────────────────────────────────────────────────────────────────
create type papel_usuario as enum ('dono', 'assinante');

comment on type papel_usuario is
  'Administrador (Fred e Bruna) e cliente. Decidido em 24/09/2026 — ver DECISOES.md.';


-- ───────────────────────────────────────────────────────────────────────────
-- 4. Perfis
--
-- Um perfil não é um cliente. `perfis` é a conta de acesso, espelhando a
-- tabela "user" do Better Auth; `clientes` (Fase 1) é o registro de negócio.
-- Cliente sem conta é normal e precisa continuar funcionando: lead de
-- evento, comprador avulso, cliente importado de planilha.
--
-- O id é `text` porque o Better Auth gera id em texto, não uuid.
-- ───────────────────────────────────────────────────────────────────────────
create table perfis (
  id            text primary key references "user" (id) on delete cascade,
  papel         papel_usuario not null default 'assinante',
  nome          text          not null check (char_length(nome) between 1 and 120),
  telefone      text          check (telefone ~ '^\+55\d{10,11}$'),
  pin_hash      text,
  criado_em     timestamptz   not null default now(),
  atualizado_em timestamptz   not null default now()
);

comment on table perfis is
  'Conta de acesso. O papel é lido SEMPRE daqui, no servidor — nunca do corpo da requisição, nunca de token editável, nunca de estado do cliente.';
comment on column perfis.papel is
  'Só o dono altera, e apenas por definir_papel(). Grant de coluna, policy e gatilho guardam isso em três camadas.';
comment on column perfis.pin_hash is
  'HASH do PIN do app de produção (Fase 3). O PIN em texto puro nunca é gravado, e sozinho ele não autentica.';
comment on column perfis.telefone is
  'E.164 com DDI do Brasil: +55 seguido de 10 ou 11 dígitos.';

create index perfis_papel_idx on perfis (papel);

alter table perfis enable row level security;


-- ───────────────────────────────────────────────────────────────────────────
-- 5. Privilégios de tabela — a camada abaixo da RLS
--
-- A RLS diz QUAIS LINHAS a pessoa alcança. O grant diz QUAIS COLUNAS ela
-- pode escrever. Mesmo que uma policy futura saia errada, app_usuario não
-- grava em `papel` nem em `pin_hash`: o privilégio de coluna não existe.
--
-- Sem insert e sem delete para ninguém: perfil nasce pelo gatilho do signup
-- e morre em cascata com "user".
-- ───────────────────────────────────────────────────────────────────────────
revoke all on table perfis from app_anon, app_usuario;
grant select on table perfis to app_usuario;
grant update (nome, telefone) on table perfis to app_usuario;
-- app_anon não recebe nada. Ninguém sem login lê a base de contas.


-- ───────────────────────────────────────────────────────────────────────────
-- 6. Funções de papel
--
-- `security definer` porque são chamadas DENTRO das policies de `perfis`:
-- sem isso, a policy consultaria `perfis`, que dispara a policy de novo, em
-- recursão infinita.
--
-- `set search_path = public` é obrigatório: search_path mutável é vetor de
-- escalada de privilégio. Por isso `app.usuario_id()` aparece qualificado.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function meu_papel()
returns papel_usuario
language sql
stable
security definer
set search_path = public
as $$
  select papel from perfis where id = app.usuario_id();
$$;

create or replace function sou_dono()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select papel from perfis where id = app.usuario_id()) = 'dono',
    false
  );
$$;

comment on function meu_papel() is 'Papel de quem chama. Null se não houver sessão.';
comment on function sou_dono()  is 'true se quem chama é o dono. Nunca devolve null — policy com null não protege nada.';

revoke execute on function meu_papel() from public;
revoke execute on function sou_dono()  from public;
-- Precisam de execute para app_usuario: expressão de policy roda com os
-- privilégios de quem consulta.
grant execute on function meu_papel() to app_usuario;
grant execute on function sou_dono()  to app_usuario;


-- ───────────────────────────────────────────────────────────────────────────
-- 7. Policies — uma por operação, nunca um `for all` genérico
-- ───────────────────────────────────────────────────────────────────────────

create policy "perfis: le o proprio, dono le todos"
  on perfis
  for select
  to app_usuario
  using (
    id = app.usuario_id()
    or (select sou_dono())
  );

-- Lei 1 — toda policy de update tem `with check`.
--
--   using      → QUAIS LINHAS a pessoa alcança
--   with check → O QUE ela pode deixar gravado
--
-- Policy de update só com `using` deixa a pessoa escrever qualquer valor na
-- linha que ela alcança. Foi assim que um assinante virava dono.
--
-- `meu_papel()` aqui lê o papel ANTERIOR: a função enxerga o snapshot do
-- início da instrução, não a linha sendo gravada. A condição diz, na
-- prática, "o papel tem que continuar o mesmo".
create policy "perfis: atualiza o proprio sem mexer no papel"
  on perfis
  for update
  to app_usuario
  using (
    id = app.usuario_id()
    or (select sou_dono())
  )
  with check (
    (select sou_dono())
    or (
      id = app.usuario_id()
      and papel = (select meu_papel())
    )
  );

-- INSERT e DELETE: nenhuma policy, de propósito.


-- ───────────────────────────────────────────────────────────────────────────
-- 8. Gatilho de proteção de colunas — a camada de dentro
-- ───────────────────────────────────────────────────────────────────────────
create or replace function perfis_protege_colunas()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.id            := old.id;
  new.criado_em     := old.criado_em;
  new.atualizado_em := now();

  -- Só restringe quando a instrução roda vestindo um papel de aplicação.
  -- A conexão administrativa é confiável por definição, e definir_papel()
  -- é `security definer`, então já rodou a própria checagem antes de chegar aqui.
  if new.papel is distinct from old.papel
     and current_role in ('app_usuario', 'app_anon')
     and not coalesce(sou_dono(), false)
  then
    raise exception 'sem permissão para alterar o papel';
  end if;

  return new;
end;
$$;

comment on function perfis_protege_colunas() is
  'Congela id e criado_em, atualiza atualizado_em, e recusa troca de papel fora do caminho autorizado.';

create trigger perfis_antes_de_atualizar
  before update on perfis
  for each row
  execute function perfis_protege_colunas();

revoke execute on function perfis_protege_colunas() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- 9. Troca de papel — caminho único
--
-- Lei 4: ninguém escreve `papel` direto na tabela.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function definir_papel(p_usuario_id text, p_papel papel_usuario)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- SEMPRE a primeira instrução, antes de ler ou gravar qualquer coisa.
  if not coalesce(sou_dono(), false) then
    raise exception 'sem permissão para esta operação';
  end if;

  -- O dono não se rebaixa por acidente e deixa o sistema sem dono.
  if p_usuario_id = app.usuario_id() and p_papel <> 'dono' then
    raise exception 'o dono não pode rebaixar a própria conta';
  end if;

  update perfis set papel = p_papel where id = p_usuario_id;

  if not found then
    raise exception 'perfil não encontrado';
  end if;
end;
$$;

comment on function definir_papel(text, papel_usuario) is
  'Único caminho para alterar perfis.papel. Confere sou_dono() na primeira instrução.';

revoke execute on function definir_papel(text, papel_usuario) from public;
grant execute on function definir_papel(text, papel_usuario) to app_usuario;


-- ───────────────────────────────────────────────────────────────────────────
-- 10. Criação do perfil no cadastro
--
-- O Better Auth insere em "user"; o perfil nasce atrás dele, sempre como
-- assinante. Nenhum dado vindo do formulário decide papel.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function criar_perfil_no_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome text;
begin
  v_nome := left(trim(coalesce(new.name, '')), 120);
  if v_nome = '' then
    v_nome := 'Sem nome';
  end if;

  insert into public.perfis (id, nome, papel)
  values (new.id, v_nome, 'assinante')
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function criar_perfil_no_signup() is
  'Único caminho para criar perfil. O papel é sempre assinante — nunca vem do cadastro.';

create trigger ao_criar_usuario
  after insert on "user"
  for each row
  execute function criar_perfil_no_signup();

revoke execute on function criar_perfil_no_signup() from public;


-- Down Migration

drop trigger if exists ao_criar_usuario on "user";
drop function if exists criar_perfil_no_signup();
drop function if exists definir_papel(text, papel_usuario);
drop trigger if exists perfis_antes_de_atualizar on perfis;
drop function if exists perfis_protege_colunas();
drop function if exists sou_dono();
drop function if exists meu_papel();
drop table if exists perfis;
drop type if exists papel_usuario;
drop function if exists app.usuario_id();
drop schema if exists app;
