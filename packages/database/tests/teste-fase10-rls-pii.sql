-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 10 — testes de RLS em tabelas PII
--
-- Valida que usuários veem apenas dados do seu cliente e dona vê tudo.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- Limpar dados de teste anteriores
delete from "user" where email like '%teste-fase10%';

-- ───────────────────────────────────────────────────────────────────────────
-- Dados de teste
-- ───────────────────────────────────────────────────────────────────────────

-- User 1: usuário autenticado (cliente 1)
insert into "user" (id, email, "emailVerified", name)
values ('user-teste1', 'usuario-teste1@example.teste-fase10.com', true, 'Usuário Teste 1')
on conflict (id) do nothing;

-- User 2: outro usuário autenticado (cliente 2)
insert into "user" (id, email, "emailVerified", name)
values ('user-teste2', 'usuario-teste2@example.teste-fase10.com', true, 'Usuário Teste 2')
on conflict (id) do nothing;

-- User 3: o dono
insert into "user" (id, email, "emailVerified", name)
values ('user-dono-teste', 'dono@example.teste-fase10.com', true, 'Dono Teste')
on conflict (id) do nothing;

-- Perfis
insert into perfis (id, papel, nome, telefone)
values
  ('user-teste1', 'assinante', 'Usuário Teste 1', '+5511999999991'),
  ('user-teste2', 'assinante', 'Usuário Teste 2', '+5511999999992'),
  ('user-dono-teste', 'dono', 'Dono Teste', '+5511999999990')
on conflict (id) do nothing;

-- Clientes linkados aos usuários
insert into clientes (id, usuario_id, tipo, status, nome, apelido, telefone, email, cep, endereco, origem, codigo_indicacao)
values
  ('12345678-1234-5678-1234-567812345678'::uuid, 'user-teste1', 'b2c', 'ativo', 'Cliente Teste 1', 'Cliente 1', '+5511999999991', 'cliente1@example.teste-fase10.com', '01310100', 'Rua Teste 1', 'organico', 'ONCA-TST1'),
  ('87654321-4321-8765-4321-876543218765'::uuid, 'user-teste2', 'b2c', 'ativo', 'Cliente Teste 2', 'Cliente 2', '+5511999999992', 'cliente2@example.teste-fase10.com', '01310200', 'Rua Teste 2', 'organico', 'ONCA-TST2'),
  ('11111111-1111-1111-1111-111111111111'::uuid, null,        'b2c', 'ativo', 'Cliente Sem User',  null,          '+5511999999993', null,                                  '01310300', 'Rua Teste 3', 'organico', 'ONCA-TST3')
on conflict (id) do nothing;

-- Planos (semanal já deve estar cadastrado pelas migrations)
-- Apenas garantindo que o plano 1 existe, mas sem inserir (as migrations já criaram os planos)

-- Assinaturas
insert into assinaturas (id, cliente_id, plano_id, status, data_inicio)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '12345678-1234-5678-1234-567812345678'::uuid, 1, 'ativa', '2026-01-01'::date),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, '87654321-4321-8765-4321-876543218765'::uuid, 1, 'ativa', '2026-01-01'::date),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 1, 'ativa', '2026-01-01'::date)
on conflict (id) do nothing;

-- Entregas
insert into entregas (id, assinatura_id, cliente_id, data_prevista, status)
values
  ('dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '12345678-1234-5678-1234-567812345678'::uuid, '2026-10-08'::date, 'pendente'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, '87654321-4321-8765-4321-876543218765'::uuid, '2026-10-08'::date, 'pendente'),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid, 'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, '2026-10-08'::date, 'pendente')
on conflict (id) do nothing;

-- Faturas
insert into faturas (id, cliente_id, assinatura_id, valor_centavos, vencimento, status)
values
  ('22222222-2222-2222-2222-222222222222'::uuid, '12345678-1234-5678-1234-567812345678'::uuid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 16400, '2026-10-05'::date, 'pendente'),
  ('33333333-3333-3333-3333-333333333333'::uuid, '87654321-4321-8765-4321-876543218765'::uuid, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, 16400, '2026-10-05'::date, 'pendente'),
  ('44444444-4444-4444-4444-444444444444'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid, 16400, '2026-10-05'::date, 'pendente')
on conflict (id) do nothing;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 1: Usuário vê apenas seu cliente
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_count int;
begin
  set local role app_usuario;
  set local app.usuario_id = 'user-teste1';

  -- Usuário 1 deveria ver apenas 1 cliente (o seu)
  select count(*) into v_count from clientes;

  if v_count != 1 then
    raise exception 'TESTE 1 FALHOU: Usuário 1 vê % clientes, esperado 1', v_count;
  end if;

  -- Confirmar que é o cliente correto
  if not exists (select 1 from clientes where id = '12345678-1234-5678-1234-567812345678'::uuid) then
    raise exception 'TESTE 1 FALHOU: Usuário 1 não consegue ver seu próprio cliente';
  end if;

  raise notice 'TESTE 1 PASSOU: Usuário vê apenas seu cliente';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 2: Usuário não consegue ver cliente de outro usuário
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_count int;
begin
  set local role app_usuario;
  set local app.usuario_id = 'user-teste1';

  -- Usuário 1 NÃO deveria conseguir ver cliente-teste2
  select count(*) into v_count from clientes where id = '87654321-4321-8765-4321-876543218765'::uuid;

  if v_count > 0 then
    raise exception 'TESTE 2 FALHOU: Usuário 1 conseguiu ver cliente de outro usuário';
  end if;

  raise notice 'TESTE 2 PASSOU: Usuário não vê cliente de outro usuário';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 3: Usuário vê apenas assinaturas do seu cliente
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_count int;
begin
  set local role app_usuario;
  set local app.usuario_id = 'user-teste1';

  -- Usuário 1 deveria ver apenas 1 assinatura
  select count(*) into v_count from assinaturas;

  if v_count != 1 then
    raise exception 'TESTE 3 FALHOU: Usuário 1 vê % assinaturas, esperado 1', v_count;
  end if;

  if not exists (select 1 from assinaturas where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) then
    raise exception 'TESTE 3 FALHOU: Usuário 1 não consegue ver sua assinatura';
  end if;

  raise notice 'TESTE 3 PASSOU: Usuário vê apenas suas assinaturas';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 4: Usuário não consegue alterar cliente_id de seu cliente
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_success boolean := false;
begin
  set local role app_usuario;
  set local app.usuario_id = 'user-teste1';

  begin
    -- Tentar alterar usuario_id do cliente (deveria falhar)
    update clientes
    set usuario_id = 'user-teste2'
    where id = '12345678-1234-5678-1234-567812345678'::uuid;

    -- Se chegou aqui, a operação foi permitida (BUG!)
    raise exception 'TESTE 4 FALHOU: Usuário conseguiu alterar usuario_id do cliente';
  exception
    when check_violation then
      -- Esperado: a política WITH CHECK falha
      raise notice 'TESTE 4 PASSOU: Usuário não consegue alterar usuario_id (check constraint)';
      rollback;
  end;
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 5: Dono vê todos os clientes
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_count int;
begin
  set local role app_usuario;
  set local app.usuario_id = 'user-dono-teste';

  -- Dono deveria ver todos os clientes (3)
  select count(*) into v_count from clientes;

  if v_count != 3 then
    raise exception 'TESTE 5 FALHOU: Dono vê % clientes, esperado 3', v_count;
  end if;

  -- Confirmar que dono vê os 3 clientes de teste
  if not exists (select 1 from clientes where id in ('12345678-1234-5678-1234-567812345678'::uuid, '87654321-4321-8765-4321-876543218765'::uuid, '11111111-1111-1111-1111-111111111111'::uuid)) then
    raise exception 'TESTE 5 FALHOU: Dono não consegue ver alguns clientes';
  end if;

  raise notice 'TESTE 5 PASSOU: Dono vê todos os clientes';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 6: Usuário não consegue ver entregas de outro cliente
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_count int;
begin
  set local role app_usuario;
  set local app.usuario_id = 'user-teste1';

  -- Usuário 1 deveria ver apenas 1 entrega
  select count(*) into v_count from entregas;

  if v_count != 1 then
    raise exception 'TESTE 6 FALHOU: Usuário 1 vê % entregas, esperado 1', v_count;
  end if;

  -- Usuário 1 não deveria conseguir ver entrega-teste2
  if exists (select 1 from entregas where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid) then
    raise exception 'TESTE 6 FALHOU: Usuário 1 conseguiu ver entrega de outro cliente';
  end if;

  raise notice 'TESTE 6 PASSOU: Usuário não vê entregas de outro cliente';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- TESTE 7: Usuário não consegue ver faturas de outro cliente
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare
  v_count int;
begin
  set local role app_usuario;
  set local app.usuario_id = 'user-teste1';

  -- Usuário 1 deveria ver apenas 1 fatura
  select count(*) into v_count from faturas;

  if v_count != 1 then
    raise exception 'TESTE 7 FALHOU: Usuário 1 vê % faturas, esperado 1', v_count;
  end if;

  -- Usuário 1 não deveria conseguir ver fatura-teste2
  if exists (select 1 from faturas where id = '33333333-3333-3333-3333-333333333333'::uuid) then
    raise exception 'TESTE 7 FALHOU: Usuário 1 conseguiu ver fatura de outro cliente';
  end if;

  raise notice 'TESTE 7 PASSOU: Usuário não vê faturas de outro cliente';
end;
$$;


-- ───────────────────────────────────────────────────────────────────────────
-- LIMPEZA
-- ───────────────────────────────────────────────────────────────────────────
delete from "user" where email like '%teste-fase10%';

do $$
begin
  raise notice '';
  raise notice '═══════════════════════════════════════════════════════════════';
  raise notice 'RESULTADO: Todos os 7 testes de RLS em tabelas PII PASSARAM ✓';
  raise notice '═══════════════════════════════════════════════════════════════';
end;
$$;

commit;
