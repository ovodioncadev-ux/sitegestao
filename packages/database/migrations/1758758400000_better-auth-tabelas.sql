-- ═══════════════════════════════════════════════════════════════════════════
-- Tabelas do Better Auth.
--
-- Os nomes são ditados pela biblioteca, não por nós: a tabela se chama
-- "user" (palavra reservada no Postgres, por isso sempre entre aspas) e as
-- colunas são camelCase, também entre aspas. Não renomeie nada aqui.
--
-- Confira contra a saída de `npx @better-auth/cli generate` sempre que
-- atualizar a biblioteca: se ela acrescentar coluna, é aqui que entra.
--
-- ⚠️  Estas quatro tabelas guardam HASH DE SENHA e TOKEN DE SESSÃO.
--     Nenhum papel de aplicação as alcança: RLS ligada, nenhuma policy,
--     nenhum grant. Só a conexão administrativa (dona das tabelas), que é
--     por onde o próprio Better Auth fala com o banco.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

create table "user" (
  id              text primary key,
  name            text not null,
  email           text not null unique,
  "emailVerified" boolean not null default false,
  image           text,
  "createdAt"     timestamptz not null default now(),
  "updatedAt"     timestamptz not null default now()
);

create table "session" (
  id           text primary key,
  "userId"     text not null references "user" (id) on delete cascade,
  token        text not null unique,
  "expiresAt"  timestamptz not null,
  "ipAddress"  text,
  "userAgent"  text,
  "createdAt"  timestamptz not null default now(),
  "updatedAt"  timestamptz not null default now()
);

create index session_user_idx on "session" ("userId");
create index session_expira_idx on "session" ("expiresAt");

create table "account" (
  id                        text primary key,
  "userId"                  text not null references "user" (id) on delete cascade,
  "accountId"               text not null,
  "providerId"              text not null,
  "accessToken"             text,
  "refreshToken"            text,
  "accessTokenExpiresAt"    timestamptz,
  "refreshTokenExpiresAt"   timestamptz,
  scope                     text,
  "idToken"                 text,
  password                  text,
  "createdAt"               timestamptz not null default now(),
  "updatedAt"               timestamptz not null default now()
);

create index account_user_idx on "account" ("userId");
create unique index account_provider_idx on "account" ("providerId", "accountId");

create table "verification" (
  id           text primary key,
  identifier   text not null,
  value        text not null,
  "expiresAt"  timestamptz not null,
  "createdAt"  timestamptz not null default now(),
  "updatedAt"  timestamptz not null default now()
);

create index verification_identificador_idx on "verification" (identifier);

-- RLS ligada na mesma migration que cria a tabela, sem exceção.
-- Sem policy nenhuma: ninguém além da dona das tabelas passa por aqui.
alter table "user" enable row level security;
alter table "session" enable row level security;
alter table "account" enable row level security;
alter table "verification" enable row level security;

comment on table "user" is 'Better Auth — identidade. Nomes ditados pela biblioteca.';
comment on table "session" is 'Better Auth — sessões ativas. Contém token: nenhum papel de aplicação alcança.';
comment on table "account" is 'Better Auth — credenciais. Contém hash de senha: nenhum papel de aplicação alcança.';
comment on table "verification" is 'Better Auth — códigos de verificação e recuperação.';

-- Down Migration

drop table if exists "verification";
drop table if exists "account";
drop table if exists "session";
drop table if exists "user";
