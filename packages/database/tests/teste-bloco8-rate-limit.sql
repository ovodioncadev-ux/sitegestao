-- ═══════════════════════════════════════════════════════════════════════
-- Bloco 8 — limite de login/cadastro compartilhado (consumir_rate_limit).
--
--   pnpm --filter @ovo/database teste:bloco8
--
-- (A concorrência de verdade — várias conexões ao mesmo tempo — está em
--  scripts/teste-concorrencia-rate-limit.mjs: um bloco SQL só tem uma conexão.)
-- Tudo dentro de uma transação que termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total  int := 0;
  v_falhas int := 0;
  v_ok     boolean;
  v_row    record;
  v_int    int;
  v_n      int;
begin
  raise notice '═══ Bloco 8: contador atômico de tentativas ═══';

  -- B8.1 ── 5 passam, a 6ª é bloqueada, com tempo de espera coerente ────────
  v_total := v_total + 1;
  v_ok := true;
  for i in 1..5 loop
    select * into v_row from consumir_rate_limit('203.0.113.1|/sign-in/email', 5, 60);
    if not v_row.permitido then v_ok := false; end if;
  end loop;
  select * into v_row from consumir_rate_limit('203.0.113.1|/sign-in/email', 5, 60);
  if v_ok and not v_row.permitido and v_row.retry_apos between 1 and 60 then
    raise notice '  OK    B8.1  5 tentativas passam; a 6ª é bloqueada e manda esperar % s (≤ 60)', v_row.retry_apos;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B8.1  passaram as 5: %, 6ª permitida: %, retry %', v_ok, v_row.permitido, v_row.retry_apos;
  end if;

  -- B8.2 ── bloqueado continua bloqueado; chaves diferentes são independentes ─
  v_total := v_total + 1;
  select * into v_row from consumir_rate_limit('203.0.113.1|/sign-in/email', 5, 60);
  v_ok := not v_row.permitido;
  select * into v_row from consumir_rate_limit('203.0.113.2|/sign-in/email', 5, 60);   -- outro IP
  v_ok := v_ok and v_row.permitido;
  select * into v_row from consumir_rate_limit('203.0.113.1|/sign-up/email', 5, 3600); -- outra rota
  v_ok := v_ok and v_row.permitido;
  if v_ok then
    raise notice '  OK    B8.2  quem estourou segue bloqueado; outro IP e outra rota do mesmo IP seguem livres';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B8.2';
  end if;

  -- B8.3 ── a janela vence e o contador reinicia em 1 ──────────────────────
  v_total := v_total + 1;
  update rateLimit set reset_at = now() - interval '1 second' where ip = '203.0.113.1|/sign-in/email' and endpoint = 'auth';
  select * into v_row from consumir_rate_limit('203.0.113.1|/sign-in/email', 5, 60);
  select count into v_int from rateLimit where ip = '203.0.113.1|/sign-in/email' and endpoint = 'auth';
  if v_row.permitido and v_int = 1 then
    raise notice '  OK    B8.3  janela vencida: libera de novo e o contador recomeça em 1';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B8.3  permitido %, contador %', v_row.permitido, v_int;
  end if;

  -- B8.4 ── limite 1: a 1ª passa, a 2ª não ─────────────────────────────────
  v_total := v_total + 1;
  select * into v_row from consumir_rate_limit('limite-um', 1, 60);
  v_ok := v_row.permitido;
  select * into v_row from consumir_rate_limit('limite-um', 1, 60);
  if v_ok and not v_row.permitido then
    raise notice '  OK    B8.4  com limite 1: a primeira passa e a segunda é bloqueada';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B8.4';
  end if;

  -- B8.5 ── parâmetros inválidos são recusados ─────────────────────────────
  v_total := v_total + 1;
  v_ok := true;
  begin perform * from consumir_rate_limit(null, 5, 60);                   v_ok := false; exception when raise_exception then null; end;
  begin perform * from consumir_rate_limit('', 5, 60);                     v_ok := false; exception when raise_exception then null; end;
  begin perform * from consumir_rate_limit(repeat('x', 301), 5, 60);       v_ok := false; exception when raise_exception then null; end;
  begin perform * from consumir_rate_limit('k', 0, 60);                    v_ok := false; exception when raise_exception then null; end;
  begin perform * from consumir_rate_limit('k', 5, 0);                     v_ok := false; exception when raise_exception then null; end;
  if v_ok then
    raise notice '  OK    B8.5  chave vazia/nula/gigante, limite 0 e janela 0 são recusados';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B8.5  parâmetro inválido aceito';
  end if;

  -- B8.6 ── nenhum papel de aplicação alcança ──────────────────────────────
  v_total := v_total + 1;
  v_ok := true;
  begin set local role app_anon;    perform * from consumir_rate_limit('x', 5, 60); v_ok := false; exception when insufficient_privilege then null; end;
  reset role;
  begin set local role app_usuario; perform * from consumir_rate_limit('x', 5, 60); v_ok := false; exception when insufficient_privilege then null; end;
  reset role;
  if v_ok then
    raise notice '  OK    B8.6  app_anon e app_usuario não executam o contador (privilégio negado)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B8.6  um papel de aplicação alcançou consumir_rate_limit';
  end if;

  -- B8.7 ── não mistura com o limite das rotas públicas ────────────────────
  v_total := v_total + 1;
  v_ok := true;
  for i in 1..30 loop
    if limitar_acesso_publico('203.0.113.77', 'area') then v_ok := false; end if;
  end loop;
  select * into v_row from consumir_rate_limit('203.0.113.77|/sign-in/email', 5, 60);
  if v_ok and v_row.permitido then
    raise notice '  OK    B8.7  o contador de login é independente do das rotas públicas (mesmo IP, endpoints diferentes)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B8.7';
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception 'Bloco 8: % de % verificações falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações do Bloco 8 passaram.', v_total;
end;
$$;

rollback;
