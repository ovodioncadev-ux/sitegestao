-- ═══════════════════════════════════════════════════════════════════════
-- Fase 7 — área do assinante: isolamento entre contas em todas as tabelas
-- de negócio, atualizar_meus_dados e solicitações de pausa/cancelamento.
--
--   pnpm --filter @ovo/database teste:fase7
--
-- (O vínculo conta↔cliente por e-mail confirmado é testado na Fase 8.)
-- Tudo dentro de uma transação que termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total   int := 0;
  v_falhas  int := 0;
  v_int     int;
  v_txt     text;
  v_uuid    uuid;
  v_plano_s smallint;
  id_dono   text := 'teste7-dono';
  id_a      text := 'teste7-conta-a';
  id_b      text := 'teste7-conta-b';
  cli_a     uuid;
  cli_b     uuid;
  ass_a     uuid;
  ass_b     uuid;
  sol_a     uuid;
begin
  select id into v_plano_s from planos where frequencia = 'semanal';
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste F7');
  update config_negocio set preco_pente_centavos = 4100;

  insert into "user" (id, name, email) values (id_dono, 'Dono F7', 'dono-f7@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;
  perform set_config('app.usuario_id', id_dono, true);

  -- Duas contas confirmadas, cada uma vinculada ao seu cliente.
  insert into "user" (id, name, email, "emailVerified") values (id_a, 'Ana', 'ana.f7@exemplo.test', true);
  insert into "user" (id, name, email, "emailVerified") values (id_b, 'Bruno', 'bruno.f7@exemplo.test', true);
  insert into clientes (nome, email, cep, endereco, origem)
    values ('Ana F7', 'ana.f7@exemplo.test', '30140000', 'Rua A 1', 'organico') returning id into cli_a;
  insert into clientes (nome, email, cep, endereco, origem)
    values ('Bruno F7', 'bruno.f7@exemplo.test', '30150000', 'Rua B 1', 'organico') returning id into cli_b;
  ass_a := criar_assinatura(cli_a, v_plano_s);
  ass_b := criar_assinatura(cli_b, v_plano_s);
  perform criar_fatura(ass_a, hoje_sp() + 5);
  perform criar_fatura(ass_b, hoje_sp() + 5);

  -- F7.1 ── cada conta vê só o que é seu, em todas as tabelas ────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_a, true);
  set local role app_usuario;
  select (select count(*) from clientes)::int * 1000
       + (select count(*) from assinaturas where cliente_id = cli_b)::int * 100
       + (select count(*) from entregas where cliente_id = cli_b)::int * 10
       + (select count(*) from faturas where cliente_id = cli_b)::int
    into v_int;
  reset role;
  if v_int = 1000 then
    raise notice '  OK    F7.1  A vê só o próprio cliente e nenhuma assinatura, entrega ou fatura de B';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.1  visibilidade de A = % (esperava 1000)', v_int;
  end if;

  -- F7.2 ── controle positivo: A enxerga o que é dela ────────────────────────
  v_total := v_total + 1;
  set local role app_usuario;
  select (select count(*) from assinaturas where cliente_id = cli_a)::int
       + (select count(*) from entregas where cliente_id = cli_a)::int
       + (select count(*) from faturas where cliente_id = cli_a)::int
    into v_int;
  reset role;
  if v_int = 3 then
    raise notice '  OK    F7.2  CONTROLE POSITIVO: A vê a própria assinatura, entrega e fatura';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.2  A vê % linha(s) próprias (esperava 3)', v_int;
  end if;

  -- F7.3 ── A altera os próprios dados ────────────────────────────────────────
  v_total := v_total + 1;
  set local role app_usuario;
  perform atualizar_meus_dados(p_cliente_id => cli_a, p_nome => 'Ana Editada', p_bairro => 'Savassi', p_cidade => 'Belo Horizonte', p_estado => 'mg', p_numero => '77');
  reset role;
  if (select nome from clientes where id = cli_a) = 'Ana Editada'
     and (select estado from clientes where id = cli_a) = 'MG'
     and (select numero from clientes where id = cli_a) = '77' then
    raise notice '  OK    F7.3  A altera nome, número, bairro, cidade e estado do próprio cadastro';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.3  dados de A não mudaram';
  end if;

  -- F7.4 ── A NÃO altera B ─────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    set local role app_usuario;
    perform atualizar_meus_dados(p_cliente_id => cli_b, p_nome => 'Invadido');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.4  A alterou o cadastro de B';
  exception when sqlstate 'OV001' then
    reset role;
    raise notice '  OK    F7.4  A não altera o cadastro de B (%)', sqlerrm;
  end;

  -- F7.5 ── estado inválido ────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    set local role app_usuario;
    perform atualizar_meus_dados(p_cliente_id => cli_a, p_estado => 'XYZ');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.5  estado inválido aceito';
  exception when sqlstate 'OV001' then
    reset role;
    raise notice '  OK    F7.5  estado inválido é recusado (%)', sqlerrm;
  end;

  -- F7.6 ── assinante não escreve status/plano/e-mail direto ─────────────────
  v_total := v_total + 1;
  begin
    set local role app_usuario;
    update clientes set status = 'ativo', email = 'outro@exemplo.test' where id = cli_a;
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.6  assinante fez UPDATE direto em clientes';
  exception when others then
    reset role;
    raise notice '  OK    F7.6  UPDATE direto em clientes é negado ao assinante';
  end;

  -- F7.7 ── solicitar pausa da PRÓPRIA assinatura ────────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_a, true);
  set local role app_usuario;
  sol_a := solicitar_alteracao_assinatura(ass_a, 'pausa', 'viagem');
  reset role;
  if (select status::text from solicitacoes_assinatura where id = sol_a) = 'pendente'
     and (select status::text from assinaturas where id = ass_a) = 'ativa' then
    raise notice '  OK    F7.7  A pede pausa: fica "pendente" e a assinatura NÃO muda sozinha';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.7  pedido de pausa incorreto';
  end if;

  -- F7.8 ── pedido duplicado ─────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    set local role app_usuario;
    perform solicitar_alteracao_assinatura(ass_a, 'pausa', 'de novo');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.8  pedido pendente duplicado aceito';
  exception when unique_violation then
    reset role;
    raise notice '  OK    F7.8  pedido pendente duplicado é recusado';
  end;

  -- F7.9 ── assinatura alheia ────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    set local role app_usuario;
    perform solicitar_alteracao_assinatura(ass_b, 'cancelamento');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.9  A pediu cancelamento da assinatura de B';
  exception when sqlstate 'OV001' then
    reset role;
    raise notice '  OK    F7.9  A não pede nada sobre a assinatura de B (%)', sqlerrm;
  end;

  -- F7.10 ── assinante não insere solicitação direto ─────────────────────────
  v_total := v_total + 1;
  begin
    set local role app_usuario;
    insert into solicitacoes_assinatura (assinatura_id, cliente_id, tipo) values (ass_a, cli_a, 'cancelamento');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.10 INSERT direto em solicitacoes_assinatura';
  exception when others then
    reset role;
    raise notice '  OK    F7.10 INSERT direto em solicitacoes_assinatura é negado';
  end;

  -- F7.11 ── B não vê a solicitação de A; o dono vê ──────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_b, true);
  set local role app_usuario;
  select count(*) into v_int from solicitacoes_assinatura;
  reset role;
  perform set_config('app.usuario_id', id_dono, true);
  set local role app_usuario;
  select v_int * 10 + count(*)::int into v_int from solicitacoes_assinatura where id = sol_a;
  reset role;
  if v_int = 1 then
    raise notice '  OK    F7.11 B não vê o pedido de A, e o dono vê (CONTROLE POSITIVO)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.11 visibilidade de solicitações = %', v_int;
  end if;

  -- F7.12 ── anônimo não lê nenhuma tabela de negócio ─────────────────────────
  v_total := v_total + 1;
  v_int := 0;
  set local role app_anon;
  begin perform 1 from clientes;                exception when others then v_int := v_int + 1; end;
  begin perform 1 from assinaturas;             exception when others then v_int := v_int + 1; end;
  begin perform 1 from entregas;                exception when others then v_int := v_int + 1; end;
  begin perform 1 from faturas;                 exception when others then v_int := v_int + 1; end;
  begin perform 1 from solicitacoes_assinatura; exception when others then v_int := v_int + 1; end;
  begin perform 1 from auditoria;               exception when others then v_int := v_int + 1; end;
  reset role;
  if v_int = 6 then
    raise notice '  OK    F7.12 anônimo não lê clientes, assinaturas, entregas, faturas, solicitações nem auditoria';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.12 só % de 6 leituras foram recusadas', v_int;
  end if;

  -- F7.13 ── auditoria registra o pedido com quem agiu ────────────────────────
  v_total := v_total + 1;
  select count(*) into v_int from auditoria
   where acao = 'solicitacao_criada' and entidade_id = sol_a::text and usuario_id = id_a;
  if v_int = 1 then
    raise notice '  OK    F7.13 a auditoria registra o pedido com o id da conta que agiu';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F7.13 linhas de auditoria do pedido = %', v_int;
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificações da Fase 7 falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações da Fase 7 passaram.', v_total;
end;
$$;

rollback;
