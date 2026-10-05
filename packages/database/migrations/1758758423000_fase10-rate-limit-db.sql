-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 10 — Rate Limit em DB
--
-- Problema: Better Auth armazena rate limit em memória (por instância).
-- Em serverless (múltiplas instâncias), cada uma tem seu próprio limite,
-- tornando-o frouxo: atacante com múltiplos IPs consegue bypass.
--
-- Solução: Armazenar rate limit no banco de dados. Todas as instâncias
-- consultam e atualizam o mesmo contador, sincronizado.
--
-- Estrutura:
--   ip TEXT — IPv4 ou IPv6 do cliente
--   endpoint TEXT — qual rota (NULL = global, ou "/api/auth/signin")
--   count INT — tentativas já feitas nesta janela
--   reset_at TIMESTAMP — quando o contador zera
--
-- Limpeza: Trigger automático remove registros expirados (reset_at < now())
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

-- ───────────────────────────────────────────────────────────────────────────
-- Tabela de rate limit
-- ───────────────────────────────────────────────────────────────────────────
create table rateLimit (
  ip              text           not null,
  endpoint        text,
  count           integer        not null default 1 check (count > 0),
  reset_at        timestamptz    not null,

  primary key (ip, endpoint)
);

comment on table rateLimit is
  'Contador de requisições por IP e endpoint, persistido no banco. Todas as instâncias consultam aqui em vez de memória (serverless-safe).';
comment on column rateLimit.ip is
  'Endereço IP do cliente. Pode ser IPv4 (ex: 192.0.2.1) ou IPv6 (ex: 2001:db8::1).';
comment on column rateLimit.endpoint is
  'Rota monitorada (ex: /api/auth/signin). NULL = global (aplica a qualquer rota).';
comment on column rateLimit.count is
  'Número de tentativas nesta janela. Incrementado a cada requisição, zerado quando reset_at passa.';
comment on column rateLimit.reset_at is
  'Timestamp quando o contador volta para 1. Cada intervalo (ex: 60s) gera um novo reset_at.';


-- ───────────────────────────────────────────────────────────────────────────
-- Índices para performance
-- ───────────────────────────────────────────────────────────────────────────
create index rateLimit_reset_at_idx on rateLimit (reset_at);

comment on index rateLimit_reset_at_idx is
  'Usado pela limpeza automática (DELETE WHERE reset_at < now()). Evita varredura completa.';


-- ───────────────────────────────────────────────────────────────────────────
-- Trigger: limpeza automática de registros expirados
--
-- Executa ANTES de INSERT ou UPDATE em rateLimit. Se um registro expirou
-- (reset_at < now()), ele é deletado. Mantém a tabela sempre enxuta.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function limpar_rateLimit_expirados()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Deletar todos os registros com reset_at no passado
  delete from rateLimit where reset_at < now();

  return new;
end;
$$;

create trigger limpar_rateLimit_expirados_tg
  before insert or update on rateLimit
  for each statement execute function limpar_rateLimit_expirados();

revoke execute on function limpar_rateLimit_expirados() from public;

comment on function limpar_rateLimit_expirados() is
  'Trigger que limpa rate limit expirados ANTES de cada escrita. Mantém a tabela pequena.';
comment on trigger limpar_rateLimit_expirados_tg on rateLimit is
  'Executa BEFORE INSERT ou UPDATE: deleta registros com reset_at no passado.';


-- ───────────────────────────────────────────────────────────────────────────
-- Função: incrementar rate limit (ou criar novo se não existe)
--
-- Chamada por Better Auth ao processar cada requisição.
-- Retorna TRUE se limite foi ultrapassado (bloquear requisição).
-- ───────────────────────────────────────────────────────────────────────────
create or replace function verificar_rate_limit(
  p_ip text,
  p_endpoint text default null,
  p_limite_por_janela integer default 100,
  p_janela_segundos integer default 60
)
returns boolean
language plpgsql
set search_path = public
as $$
declare
  v_reset_at timestamptz;
  v_count integer;
  v_bloqueado boolean;
begin
  -- Calcular quando a janela atual expira
  v_reset_at := now() + (p_janela_segundos || ' seconds')::interval;

  -- Tentar incrementar registro existente
  update rateLimit
  set count = count + 1
  where ip = p_ip and endpoint is not distinct from p_endpoint
    and reset_at > now();

  if found then
    -- Registro existente e ainda válido, incrementou
    select count > p_limite_por_janela into v_bloqueado
    from rateLimit
    where ip = p_ip and endpoint is not distinct from p_endpoint;
  else
    -- Nenhum registro válido encontrado, criar novo
    insert into rateLimit (ip, endpoint, count, reset_at)
    values (p_ip, p_endpoint, 1, v_reset_at)
    on conflict (ip, endpoint) do update
      set count = 1, reset_at = v_reset_at;

    v_bloqueado := false;
  end if;

  return v_bloqueado;
end;
$$;

revoke execute on function verificar_rate_limit(text, text, integer, integer) from public;
grant execute on function verificar_rate_limit(text, text, integer, integer) to app_usuario;

comment on function verificar_rate_limit(text, text, integer, integer) is
  'Verifica se IP+endpoint ultrapassou o limite. Retorna TRUE se bloqueado. Chamada por Better Auth.';


-- Down Migration

drop trigger if exists limpar_rateLimit_expirados_tg on rateLimit;
drop function if exists limpar_rateLimit_expirados();
drop function if exists verificar_rate_limit(text, text, integer, integer);
drop table if exists rateLimit;
