-- ═══════════════════════════════════════════════════════════════════════
-- Bloco 4 — funil de conversão.
--
--   pnpm --filter @ovo/database teste:bloco4
--
-- Tudo dentro de uma transação que termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total  int := 0;
  v_falhas int := 0;
  v_int    int;
  v_ok     boolean;
  v_bool   boolean;
  id_dono  text := 'teste-b4-dono';
  id_user  text := 'teste-b4-user';
begin
  insert into "user" (id, name, email) values (id_dono, 'Dono B4', 'dono-b4@exemplo.test');
  insert into "user" (id, name, email) values (id_user, 'Assinante B4', 'user-b4@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;

  raise notice '═══ Bloco 4: funil de conversão ═══';

  -- B4.1 ── anon registra etapa e plano públicos ─────────────────────────────
  v_total := v_total + 1;
  set local role app_anon;
  perform registrar_evento_funil('plano_clicado', 'semanal');
  perform registrar_evento_funil('plano_clicado');
  reset role;
  select count(*) into v_int from eventos_funil where etapa = 'plano_clicado';
  if v_int = 2 and exists (select 1 from eventos_funil where plano = 'semanal') then
    raise notice '  OK    B4.1  anon registra "plano_clicado" com e sem plano';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B4.1  eventos gravados: %', v_int;
  end if;

  -- B4.2 ── etapa e plano inventados são recusados ───────────────────────────
  v_total := v_total + 1;
  v_ok := true;
  begin perform registrar_evento_funil('etapa_inventada'); v_ok := false;
  exception when raise_exception then null; end;
  begin perform registrar_evento_funil('conta_criada', 'plano-que-nao-existe'); v_ok := false;
  exception when raise_exception then null; end;
  begin perform registrar_evento_funil(null); v_ok := false;
  exception when raise_exception then null; end;
  if v_ok then
    raise notice '  OK    B4.2  etapa desconhecida, plano desconhecido e etapa nula são recusados';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B4.2  evento inválido foi aceito';
  end if;

  -- B4.3 ── ninguém da aplicação escreve direto na tabela ─────────────────────
  v_total := v_total + 1;
  v_ok := true;
  begin
    set local role app_anon;
    insert into eventos_funil (etapa) values ('conta_criada');
    v_ok := false;
  exception when insufficient_privilege then null; end;
  reset role;
  begin
    perform set_config('app.usuario_id', id_user, true);
    set local role app_usuario;
    delete from eventos_funil;
    v_ok := false;
  exception when insufficient_privilege then null; end;
  reset role;
  if v_ok then
    raise notice '  OK    B4.3  app_anon e app_usuario sem INSERT/DELETE direto (privilégio negado)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B4.3  escrita direta em eventos_funil permitida';
  end if;

  -- B4.4 ── só o dono lê o funil ───────────────────────────────────────────────
  v_total := v_total + 1;
  v_ok := true;
  perform set_config('app.usuario_id', id_user, true);
  set local role app_usuario;
  select count(*) into v_int from eventos_funil;
  if v_int <> 0 then v_ok := false; end if;
  reset role;
  perform set_config('app.usuario_id', id_dono, true);
  set local role app_usuario;
  select count(*) into v_int from eventos_funil;
  reset role;
  if v_ok and v_int = 2 then
    raise notice '  OK    B4.4  assinante vê 0 linhas; dono vê as 2 registradas';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B4.4  leitura do funil (assinante viu ok=%, dono viu %)', v_ok, v_int;
  end if;

  -- B4.5 ── a tabela não guarda nada que identifique a pessoa ────────────────
  v_total := v_total + 1;
  select count(*) into v_int
    from information_schema.columns
   where table_schema = 'public' and table_name = 'eventos_funil'
     and column_name not in ('id', 'etapa', 'plano', 'criado_em');
  if v_int = 0 then
    raise notice '  OK    B4.5  eventos_funil só tem id, etapa, plano e instante (sem IP, e-mail ou sessão)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B4.5  eventos_funil ganhou % coluna(s) fora do contrato', v_int;
  end if;

  -- B4.6 ── rota "evento" do limitador: 60 por minuto ─────────────────────────
  v_total := v_total + 1;
  set local role app_anon;
  v_ok := true;
  for i in 1..60 loop
    if limitar_acesso_publico('203.0.113.70', 'evento') then v_ok := false; end if;
  end loop;
  v_bool := limitar_acesso_publico('203.0.113.70', 'evento');
  reset role;
  if v_ok and v_bool then
    raise notice '  OK    B4.6  60 eventos por minuto passam; o 61º do mesmo IP é bloqueado';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B4.6  limite de eventos (60 livres: %, 61º bloqueado: %)', v_ok, v_bool;
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception 'Bloco 4: % de % verificações falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações do Bloco 4 passaram.', v_total;
end;
$$;

rollback;
