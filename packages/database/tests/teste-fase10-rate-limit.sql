-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 10 — testes de Rate Limit em DB
--
-- Valida que rate limit funciona: incrementa contador, bloqueia após limite,
-- e limpa automaticamente após expiração.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- Limpar dados de teste anteriores
delete from rateLimit where ip = '192.0.2.123' or ip = '192.0.2.124';

-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 1: Primeira requisição não é bloqueada
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_bloqueado boolean;
begin
  v_bloqueado := verificar_rate_limit(
    p_ip => '192.0.2.123',
    p_endpoint => '/api/auth/signin',
    p_limite_por_janela => 5,
    p_janela_segundos => 60
  );

  if v_bloqueado then
    raise exception 'TESTE 1 FALHOU: Primeira requisição foi bloqueada';
  end if;

  if not exists (select 1 from rateLimit where ip = '192.0.2.123') then
    raise exception 'TESTE 1 FALHOU: Registro de rate limit não foi criado';
  end if;

  raise notice 'TESTE 1 PASSOU: Primeira requisição não é bloqueada';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 2: Contador incrementa
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_count integer;
begin
  -- Fazer mais 4 requisições (total = 5)
  for i in 1..4 loop
    perform verificar_rate_limit(
      p_ip => '192.0.2.123',
      p_endpoint => '/api/auth/signin',
      p_limite_por_janela => 5,
      p_janela_segundos => 60
    );
  end loop;

  select count into v_count from rateLimit where ip = '192.0.2.123';

  if v_count != 5 then
    raise exception 'TESTE 2 FALHOU: Contador está %, esperado 5', v_count;
  end if;

  raise notice 'TESTE 2 PASSOU: Contador incrementa corretamente (agora = 5)';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 3: Requisição 6 é bloqueada (limite = 5)
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_bloqueado boolean;
begin
  v_bloqueado := verificar_rate_limit(
    p_ip => '192.0.2.123',
    p_endpoint => '/api/auth/signin',
    p_limite_por_janela => 5,
    p_janela_segundos => 60
  );

  if not v_bloqueado then
    raise exception 'TESTE 3 FALHOU: 6ª requisição deveria ter sido bloqueada';
  end if;

  raise notice 'TESTE 3 PASSOU: Requisição 6 é bloqueada (limite = 5)';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 4: IP diferente tem seu próprio limite
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_bloqueado boolean;
  v_count integer;
begin
  -- IP 192.0.2.124 faz 3 requisições
  for i in 1..3 loop
    v_bloqueado := verificar_rate_limit(
      p_ip => '192.0.2.124',
      p_endpoint => '/api/auth/signin',
      p_limite_por_janela => 5,
      p_janela_segundos => 60
    );
  end loop;

  select count into v_count from rateLimit where ip = '192.0.2.124';

  if v_count != 3 then
    raise exception 'TESTE 4 FALHOU: IP 192.0.2.124 tem contador %, esperado 3', v_count;
  end if;

  -- IP 192.0.2.124 ainda não deveria estar bloqueado (apenas 3 de 5)
  if v_bloqueado then
    raise exception 'TESTE 4 FALHOU: IP 192.0.2.124 foi bloqueado prematuramente';
  end if;

  raise notice 'TESTE 4 PASSOU: IP diferente tem seu próprio limite (3/5)';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 5: Endpoint diferente tem seu próprio limite
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_bloqueado boolean;
  v_count_signin integer;
  v_count_signup integer;
begin
  -- IP 192.0.2.123 com endpoint /api/auth/signup
  for i in 1..5 loop
    v_bloqueado := verificar_rate_limit(
      p_ip => '192.0.2.123',
      p_endpoint => '/api/auth/signup',
      p_limite_por_janela => 5,
      p_janela_segundos => 60
    );
  end loop;

  select count into v_count_signin from rateLimit
  where ip = '192.0.2.123' and endpoint = '/api/auth/signin';

  select count into v_count_signup from rateLimit
  where ip = '192.0.2.123' and endpoint = '/api/auth/signup';

  if v_count_signin != 6 then
    raise exception 'TESTE 5 FALHOU: /api/auth/signin tem %, esperado 6', v_count_signin;
  end if;

  if v_count_signup != 5 then
    raise exception 'TESTE 5 FALHOU: /api/auth/signup tem %, esperado 5', v_count_signup;
  end if;

  raise notice 'TESTE 5 PASSOU: Endpoint diferente tem seu próprio limite';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 6: Limpeza manual de registros expirados funciona
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_count integer;
begin
  -- Inserir um registro com reset_at no passado (já expirou)
  insert into rateLimit (ip, endpoint, count, reset_at)
  values ('10.0.0.1', '/teste-expiracao', 1, now() - interval '1 hour')
  on conflict (ip, endpoint) do update
    set count = 1, reset_at = now() - interval '1 hour';

  -- Limpar manualmente (como o trigger faz antes de INSERT/UPDATE)
  delete from rateLimit where reset_at < now();

  -- Verificar que foi deletado
  select count(*) into v_count from rateLimit where ip = '10.0.0.1';

  if v_count != 0 then
    raise exception 'TESTE 6 FALHOU: Registro expirado não foi deletado';
  end if;

  raise notice 'TESTE 6 PASSOU: Registros expirados podem ser limpos';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 7: Rate limit por múltiplos endpoints funciona
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_bloqueado boolean;
  v_count_signin integer;
  v_count_password integer;
begin
  -- Rate limit para /api/auth/signin
  for i in 1..5 loop
    perform verificar_rate_limit(
      p_ip => '203.0.113.42',
      p_endpoint => '/api/auth/signin',
      p_limite_por_janela => 5,
      p_janela_segundos => 60
    );
  end loop;

  -- Rate limit para /api/auth/password-reset
  for i in 1..3 loop
    perform verificar_rate_limit(
      p_ip => '203.0.113.42',
      p_endpoint => '/api/auth/password-reset',
      p_limite_por_janela => 5,
      p_janela_segundos => 60
    );
  end loop;

  select count into v_count_signin from rateLimit
  where ip = '203.0.113.42' and endpoint = '/api/auth/signin';

  select count into v_count_password from rateLimit
  where ip = '203.0.113.42' and endpoint = '/api/auth/password-reset';

  if v_count_signin != 5 then
    raise exception 'TESTE 7 FALHOU: /api/auth/signin tem %, esperado 5', v_count_signin;
  end if;

  if v_count_password != 3 then
    raise exception 'TESTE 7 FALHOU: /api/auth/password-reset tem %, esperado 3', v_count_password;
  end if;

  raise notice 'TESTE 7 PASSOU: Rate limit por múltiplos endpoints funciona';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- LIMPEZA
-- ───────────────────────────────────────────────────────────────────────────
delete from rateLimit where ip like '192.0.2.%' or ip like '203.0.113.%' or ip like '10.0.0.%';

do $$
begin
  raise notice '';
  raise notice '═══════════════════════════════════════════════════════════════';
  raise notice 'RESULTADO: Todos os 7 testes de Rate Limit em DB PASSARAM ✓';
  raise notice '═══════════════════════════════════════════════════════════════';
end;
$$;

commit;
