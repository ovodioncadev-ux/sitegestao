-- ═══════════════════════════════════════════════════════════════════════
-- Bloco 6 (rodada 1) — D8: 1ª entrega só depois do 1º pagamento, e a
-- confirmação automática do pagamento online.
--
--   pnpm --filter @ovo/database teste:bloco6
--
-- Cobre: chave desligada (= comportamento antigo), chave ligada (fatura na
-- hora, sem entrega), liberação ao pagar, corte da D9 no instante da
-- confirmação, rotina, cancelamento por falta de pagamento, guardas, e a
-- segurança de confirmar_pagamento_online (papel mínimo, idempotência, valor
-- divergente, posse da fatura). Tudo em transação que termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_val integer;
  v_total  int := 0;
  v_falhas int := 0;
  v_int    int;
  v_txt    text;
  v_data   date;
  v_data2  date;
  v_int2   int;
  v_int3   int;
  v_ok     boolean;
  v_row    record;
  v_s      smallint;
  v_q      smallint;
  v_hoje   date := hoje_sp();
  id_dono  text := 'teste-b6-dono';
  id_a     text := 'teste-b6-conta-a';
  id_b     text := 'teste-b6-conta-b';
  cli1 uuid; cli2 uuid; cli3 uuid; cli4 uuid; cli5 uuid; cli_a uuid; cli_b uuid;
  ass1 uuid; ass2 uuid; ass3 uuid; ass4 uuid; ass5 uuid; ass_a uuid;
  f1 uuid; f2 uuid; f3 uuid; f_a uuid; f_b uuid; f_av uuid;
begin
  select id into v_s from planos where frequencia = 'semanal';
  select id into v_q from planos where frequencia = 'quinzenal';
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste B6');
  update config_negocio set preco_pente_centavos = 4100, hora_corte = '18:00', dia_corte = 1;

  insert into "user" (id, name, email) values (id_dono, 'Dono B6', 'dono-b6@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;
  perform set_config('app.usuario_id', id_dono, true);

  insert into clientes (nome, email, cep, endereco, numero, bairro, origem) values ('B6 Um',     'b6-1@exemplo.test', '30140000', 'Rua', '1', 'Savassi', 'organico') returning id into cli1;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem) values ('B6 Dois',   'b6-2@exemplo.test', '30140001', 'Rua', '2', 'Savassi', 'organico') returning id into cli2;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem) values ('B6 Tres',   'b6-3@exemplo.test', '30140002', 'Rua', '3', 'Savassi', 'organico') returning id into cli3;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem) values ('B6 Quatro', 'b6-4@exemplo.test', '30140003', 'Rua', '4', 'Savassi', 'organico') returning id into cli4;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem) values ('B6 Cinco',  'b6-5@exemplo.test', '30140004', 'Rua', '5', 'Savassi', 'organico') returning id into cli5;

  raise notice '═══ D8 — chave desligada: nada muda ═══';

  -- D8.1 ────────────────────────────────────────────────────────────────────
  v_total := v_total + 1;
  ass1 := criar_assinatura(cli1, v_s);
  select count(*) into v_int from entregas where assinatura_id = ass1;
  select count(*) into v_row from faturas where assinatura_id = ass1;
  if v_int = 1 and v_row.count = 0
     and (select aguardando_pagamento_desde from assinaturas where id = ass1) is null
     and (select proxima_entrega from assinaturas where id = ass1) is not null then
    raise notice '  OK    D8.1  com a chave DESLIGADA (padrão): 1ª entrega agendada na hora, sem fatura, sem espera — como antes';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA D8.1  entregas %, faturas %', v_int, v_row.count;
  end if;

  raise notice '═══ D8 — chave ligada: fatura na hora, entrega só depois de pagar ═══';
  update config_negocio set exigir_pagamento_antes_da_1a_entrega = true;

  -- D8.2 ────────────────────────────────────────────────────────────────────
  v_total := v_total + 1;
  ass2 := criar_assinatura(cli2, v_s);
  select * into v_row from assinaturas where id = ass2;
  select count(*) into v_int from entregas where assinatura_id = ass2;
  select id, valor_centavos, vencimento, status into f1, v_int, v_data, v_txt from faturas where assinatura_id = ass2;
  if v_row.aguardando_pagamento_desde = v_hoje and v_row.proxima_entrega is null and v_row.status = 'ativa'
     and (select count(*) from entregas where assinatura_id = ass2) = 0
     and f1 is not null and v_int = round((select preco_pente_centavos from config_negocio) * 0.9 * (select calculo_entregas from faturas where id = f1)) and v_data = v_hoje and v_txt = 'pendente'
     and v_row.proxima_cobranca > v_hoje then
    raise notice '  OK    D8.2  chave LIGADA: sem entrega, aguardando pagamento; 1ª fatura com 10%% off pelas entregas do período, vence hoje; próxima cobrança no mês seguinte';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA D8.2  aguardando=%, proxima_entrega=%, fatura=% % % %', v_row.aguardando_pagamento_desde, v_row.proxima_entrega, v_int, v_data, v_txt, f1;
  end if;

  -- D8.3 ── pagar a 1ª fatura libera a entrega ──────────────────────────────
  v_total := v_total + 1;
  perform registrar_pagamento(f1, v_hoje, 'pix');
  select count(*) into v_int from entregas where assinatura_id = ass2;
  select proxima_entrega into v_data from assinaturas where id = ass2;
  if v_int = 1 and v_data is not null and extract(dow from v_data) = 3
     and (select aguardando_pagamento_desde from assinaturas where id = ass2) is null
     and (select status from clientes where id = cli2) = 'ativo' then
    raise notice '  OK    D8.3  pagar a 1ª fatura cria a 1ª entrega (%, uma quarta), tira a espera e ativa o cliente', v_data;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA D8.3  entregas %, proxima %', v_int, v_data;
  end if;

  -- D8.4 ── o corte (D9) vale para o instante da confirmação ────────────────
  v_total := v_total + 1;
  ass3 := criar_assinatura(cli3, v_s);
  ass4 := criar_assinatura(cli4, v_s);
  -- segunda-feira 05/10/2026: 17:59 ainda entra na quarta 07/10; 18:01 vai para 14/10.
  v_data := liberar_primeira_entrega(ass3, timestamp '2026-10-05 17:59' at time zone 'America/Sao_Paulo');
  v_data2 := liberar_primeira_entrega(ass4, timestamp '2026-10-05 18:01' at time zone 'America/Sao_Paulo');
  if v_data = date '2026-10-07' and v_data2 = date '2026-10-14' then
    raise notice '  OK    D8.4  confirmado segunda 17:59 → entrega 07/10; segunda 18:01 → 14/10 (corte contado na confirmação)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA D8.4  17:59 → %, 18:01 → %', v_data, v_data2;
  end if;

  -- D8.5 ── liberar duas vezes não duplica ──────────────────────────────────
  v_total := v_total + 1;
  perform liberar_primeira_entrega(ass3, timestamp '2026-10-12 10:00' at time zone 'America/Sao_Paulo');
  select count(*) into v_int from entregas where assinatura_id = ass3;
  if v_int = 1 then
    raise notice '  OK    D8.5  liberar de novo não cria 2ª entrega (idempotente)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.5  % entregas', v_int;
  end if;

  raise notice '═══ D8 — rotina, prazo e guardas ═══';
  -- cli5 fica aguardando para os testes seguintes
  ass5 := criar_assinatura(cli5, v_q);
  select id into f3 from faturas where assinatura_id = ass5;

  -- D8.6 ── a rotina não empilha fatura para quem não pagou ─────────────────
  v_total := v_total + 1;
  update assinaturas set proxima_cobranca = v_hoje where id = ass5;    -- simula um período "vencido"
  perform processar_rotina_diaria();
  select count(*) into v_int from faturas where assinatura_id = ass5;
  if v_int = 1 then
    raise notice '  OK    D8.6  a rotina NÃO gera fatura nova para assinatura que aguarda o 1º pagamento';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.6  % faturas', v_int;
  end if;

  -- D8.7 ── guardas ─────────────────────────────────────────────────────────
  v_total := v_total + 1;
  v_ok := true;
  begin perform pausar_assinatura(ass5, 'teste'); v_ok := false;          exception when sqlstate 'OV001' then null; end;
  begin perform alterar_plano_assinatura(ass5, v_s); v_ok := false;       exception when sqlstate 'OV001' then null; end;
  begin perform agendar_entrega(ass5, v_hoje + 7); v_ok := false;         exception when sqlstate 'OV001' then null; end;
  if v_ok then
    raise notice '  OK    D8.7  aguardando pagamento: não pausa, não troca de plano e não agenda entrega à mão';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.7  uma operação proibida passou';
  end if;

  -- D8.7b ─ "Gerar cobrança" manual não empilha fatura em quem aguarda o 1º pagamento ──
  v_total := v_total + 1;
  v_ok := true;
  begin perform gerar_cobranca(ass5); v_ok := false; exception when sqlstate 'OV001' then null; end;
  select count(*) into v_int from faturas where assinatura_id = ass5;
  if v_ok and v_int = 1 then
    raise notice '  OK    D8.7b "Gerar cobrança" manual é recusada enquanto a 1ª fatura está em aberto: continua 1 fatura só';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.7b  recusou: %, faturas: %', v_ok, v_int;
  end if;

  -- D8.8 ── fatura avulsa paga não libera a entrega ─────────────────────────
  v_total := v_total + 1;
  f_av := criar_fatura(ass5, v_hoje + 1, 1000, 'avulsa de teste');
  perform registrar_pagamento(f_av, v_hoje, 'dinheiro');
  if (select aguardando_pagamento_desde from assinaturas where id = ass5) is not null
     and (select count(*) from entregas where assinatura_id = ass5) = 0 then
    raise notice '  OK    D8.8  pagar uma fatura avulsa NÃO libera a entrega: só a 1ª fatura do período';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.8  a avulsa liberou a entrega';
  end if;

  -- D8.9 ── prazo: 7 dias sem pagar → cancelada; 6 dias → segue ──────────────
  v_total := v_total + 1;
  update assinaturas set aguardando_pagamento_desde = v_hoje - 6 where id = ass5;
  perform processar_rotina_diaria();
  v_ok := (select status from assinaturas where id = ass5) = 'ativa';
  update assinaturas set aguardando_pagamento_desde = v_hoje - 7 where id = ass5;
  v_txt := (processar_rotina_diaria() ->> 'canceladas_sem_pagamento');
  if v_ok and (select status from assinaturas where id = ass5) = 'cancelada' and v_txt = '1'
     and (select status from faturas where id = f3) = 'cancelada'
     and (select status from clientes where id = cli5) = 'cadastro_andamento' then
    raise notice '  OK    D8.9  6 dias: segue aguardando; 7 dias: assinatura e 1ª fatura canceladas, cliente volta a "cadastro em andamento"';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA D8.9  seguiu aos 6 dias: %, status: %, canceladas: %', v_ok, (select status from assinaturas where id = ass5), v_txt;
  end if;

  -- D8.10 ─ o prazo é configurável ───────────────────────────────────────────
  v_total := v_total + 1;
  update config_negocio set dias_para_pagar_1a_fatura = 3;
  update clientes set status = 'cadastro_andamento' where id = cli5;
  ass5 := criar_assinatura(cli5, v_s);
  update assinaturas set aguardando_pagamento_desde = v_hoje - 3 where id = ass5;
  perform processar_rotina_diaria();
  if (select status from assinaturas where id = ass5) = 'cancelada' then
    raise notice '  OK    D8.10 com prazo de 3 dias, a assinatura de 3 dias atrás é cancelada';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.10';
  end if;
  update config_negocio set dias_para_pagar_1a_fatura = 7;

  raise notice '═══ D8 — pelo assinante (sessão real, RLS) ═══';
  insert into "user" (id, name, email, "emailVerified") values (id_a, 'Conta A', 'conta-a-b6@exemplo.test', true);
  insert into "user" (id, name, email, "emailVerified") values (id_b, 'Conta B', 'conta-b-b6@exemplo.test', true);

  -- D8.11 ─ assinar_plano com a chave ligada ─────────────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_a, true);
  set local role app_usuario;
  perform criar_meu_cadastro('Conta A B6', '31999990001', '30150000', 'Rua A', '10', null, 'Savassi', 'Belo Horizonte', 'MG');
  ass_a := assinar_plano(v_s);
  select count(*) into v_int from faturas;                       -- RLS: só a própria
  select count(*) into v_row from entregas;
  reset role;
  select id into f_a from faturas where assinatura_id = ass_a;
  if ass_a is not null and v_int = 1 and v_row.count = 0 then
    raise notice '  OK    D8.11 assinar_plano (conta A): a assinatura nasce aguardando, o assinante vê a PRÓPRIA fatura e nenhuma entrega';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.11  faturas visíveis %, entregas %', v_int, v_row.count;
  end if;

  select valor_centavos into v_val from faturas where id = f_a;
  -- D8.12 ─ iniciar_pagamento_online: só a própria fatura ────────────────────
  v_total := v_total + 1;
  v_ok := true;
  perform set_config('app.usuario_id', id_a, true);
  set local role app_usuario;
  select valor_centavos, referencia into v_row from iniciar_pagamento_online(f_a);
  if v_row.valor_centavos <> v_val or v_row.referencia <> f_a::text then v_ok := false; end if;
  perform anexar_link_pagamento(f_a, 'https://pagamento.exemplo.test/c/abc123');
  begin perform anexar_link_pagamento(f_a, 'http://inseguro.exemplo.test/x'); v_ok := false; exception when check_violation then null; end;
  reset role;
  perform set_config('app.usuario_id', id_b, true);
  set local role app_usuario;
  begin perform * from iniciar_pagamento_online(f_a);               v_ok := false; exception when sqlstate 'OV001' then null; end;
  begin perform anexar_link_pagamento(f_a, 'https://x.exemplo.test/y'); v_ok := false; exception when sqlstate 'OV001' then null; end;
  reset role;
  if v_ok and (select link_pagamento_url from faturas where id = f_a) = 'https://pagamento.exemplo.test/c/abc123' then
    raise notice '  OK    D8.12 a conta A inicia o pagamento da própria fatura e anexa link https; http é recusado; a conta B não alcança a fatura da A';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.12';
  end if;

  raise notice '═══ D8 — confirmação automática (papel app_pagamentos) ═══';

  -- D8.13 ─ nenhum papel de aplicação executa a confirmação ──────────────────
  v_total := v_total + 1;
  v_ok := true;
  begin set local role app_anon;    perform confirmar_pagamento_online(f_a, 'sim', 'tx-x', v_val, 'pix'); v_ok := false; exception when insufficient_privilege then null; end;
  reset role;
  begin set local role app_usuario; perform confirmar_pagamento_online(f_a, 'sim', 'tx-x', v_val, 'pix'); v_ok := false; exception when insufficient_privilege then null; end;
  reset role;
  if v_ok and (select status from faturas where id = f_a) = 'pendente' then
    raise notice '  OK    D8.13 app_anon e app_usuario NÃO conseguem confirmar pagamento (privilégio negado); a fatura segue pendente';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.13  um papel de aplicação alcançou a confirmação';
  end if;

  -- D8.14 ─ app_pagamentos só faz isso ───────────────────────────────────────
  v_total := v_total + 1;
  v_ok := true;
  set local role app_pagamentos;
  begin perform 1 from faturas limit 1;                         v_ok := false; exception when insufficient_privilege then null; end;
  begin perform 1 from clientes limit 1;                        v_ok := false; exception when insufficient_privilege then null; end;
  begin perform registrar_pagamento(f_a, v_hoje, 'pix');        v_ok := false; exception when insufficient_privilege then null; end;
  begin perform liberar_primeira_entrega(ass_a);                v_ok := false; exception when insufficient_privilege then null; end;
  begin insert into pagamentos_online (fatura_id, provedor, transacao_id, valor_pago_centavos, status)
          values (f_a, 'x', 'y', 1, 'confirmado');              v_ok := false; exception when insufficient_privilege then null; end;
  reset role;
  if v_ok then
    raise notice '  OK    D8.14 app_pagamentos não lê faturas nem clientes, não paga nem libera entrega por conta própria, não escreve na tabela: só executa a confirmação';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.14  o papel do webhook tem privilégio demais';
  end if;

  -- D8.15 ─ confirmação válida: paga, libera a entrega ───────────────────────
  v_total := v_total + 1;
  set local role app_pagamentos;
  v_txt := confirmar_pagamento_online(f_a, 'simulado', 'tx-001', v_val, 'pix');
  reset role;
  select status, metodo into v_row from faturas where id = f_a;
  if v_txt = 'confirmado' and v_row.status = 'paga' and v_row.metodo = 'pix'
     and (select count(*) from entregas where assinatura_id = ass_a) = 1
     and (select aguardando_pagamento_desde from assinaturas where id = ass_a) is null
     and (select count(*) from pagamentos_online where fatura_id = f_a and status = 'confirmado') = 1 then
    raise notice '  OK    D8.15 confirmação automática: fatura paga (pix), 1ª entrega liberada, pagamento registrado como "confirmado"';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.15  resultado %, fatura %, entregas %', v_txt, v_row.status, (select count(*) from entregas where assinatura_id = ass_a);
  end if;

  -- D8.16 ─ aviso repetido não duplica nada ───────────────────────────────────
  v_total := v_total + 1;
  set local role app_pagamentos;
  v_txt := confirmar_pagamento_online(f_a, 'simulado', 'tx-001', v_val, 'pix');
  reset role;
  if v_txt = 'ja_processado' and (select count(*) from pagamentos_online where fatura_id = f_a) = 1
     and (select count(*) from entregas where assinatura_id = ass_a) = 1 then
    raise notice '  OK    D8.16 o mesmo aviso de novo devolve "ja_processado": 1 pagamento, 1 entrega';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.16  % / % pagamentos', v_txt, (select count(*) from pagamentos_online where fatura_id = f_a);
  end if;

  -- D8.17 ─ transação nova para fatura já paga: sem efeito, fica registrada ───
  v_total := v_total + 1;
  set local role app_pagamentos;
  v_txt := confirmar_pagamento_online(f_a, 'simulado', 'tx-002', v_val, 'pix');
  reset role;
  if v_txt = 'sem_efeito' and (select status from pagamentos_online where transacao_id = 'tx-002') = 'sem_efeito' then
    raise notice '  OK    D8.17 pagamento a mais para fatura já paga: "sem_efeito", registrado para o dono avaliar estorno';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.17  %', v_txt;
  end if;

  -- D8.18 ─ valor menor que o da fatura: divergente, NÃO paga ─────────────────
  v_total := v_total + 1;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem)
    values ('B6 Seis', 'b6-6@exemplo.test', '30140005', 'Rua', '6', 'Savassi', 'organico') returning id into cli_b;
  ass_a := criar_assinatura(cli_b, v_s);
  select id, valor_centavos into f_b, v_val from faturas where assinatura_id = ass_a;
  set local role app_pagamentos;
  v_txt := confirmar_pagamento_online(f_b, 'simulado', 'tx-003', v_val - 1, 'pix');
  reset role;
  if v_txt = 'divergente' and (select status from faturas where id = f_b) = 'pendente'
     and (select count(*) from entregas where assinatura_id = ass_a) = 0 then
    raise notice '  OK    D8.18 1 centavo a menos que a fatura: "divergente", fatura segue pendente, nenhuma entrega liberada';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.18  %', v_txt;
  end if;

  -- D8.19 ─ valor maior é aceito (e fica registrado) ─────────────────────────
  v_total := v_total + 1;
  set local role app_pagamentos;
  v_txt := confirmar_pagamento_online(f_b, 'simulado', 'tx-004', v_val + 300, 'cartao');
  reset role;
  if v_txt = 'confirmado' and (select status from faturas where id = f_b) = 'paga'
     and (select valor_pago_centavos from pagamentos_online where transacao_id = 'tx-004') = v_val + 300 then
    raise notice '  OK    D8.19 valor igual ou maior que o da fatura confirma; o valor realmente pago fica guardado';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.19  %', v_txt;
  end if;

  -- D8.20 ─ dados inválidos e fatura inexistente ─────────────────────────────
  v_total := v_total + 1;
  v_ok := true;
  set local role app_pagamentos;
  begin perform confirmar_pagamento_online(gen_random_uuid(), 'simulado', 'tx-005', 100, 'pix'); v_ok := false; exception when sqlstate 'OV001' then null; end;
  begin perform confirmar_pagamento_online(f_b, '', 'tx-006', 100, 'pix');                        v_ok := false; exception when sqlstate 'OV001' then null; end;
  begin perform confirmar_pagamento_online(f_b, 'simulado', '', 100, 'pix');                      v_ok := false; exception when sqlstate 'OV001' then null; end;
  begin perform confirmar_pagamento_online(f_b, 'simulado', 'tx-007', -1, 'pix');                 v_ok := false; exception when sqlstate 'OV001' then null; end;
  reset role;
  if v_ok then
    raise notice '  OK    D8.20 fatura inexistente, provedor/transação vazios e valor negativo são recusados';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.20  uma entrada inválida foi aceita';
  end if;

  -- D8.21 ─ RLS de pagamentos_online: cada um vê o seu ────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_b, true);
  set local role app_usuario;
  select count(*) into v_int from pagamentos_online;
  reset role;
  perform set_config('app.usuario_id', id_a, true);
  set local role app_usuario;
  select count(*) into v_int2 from pagamentos_online;
  reset role;
  perform set_config('app.usuario_id', id_dono, true);
  set local role app_usuario;
  select count(*) into v_int3 from pagamentos_online;
  reset role;
  if v_int = 0 and v_int2 = 2 and v_int3 = 4 then
    raise notice '  OK    D8.21 a conta B vê 0 pagamentos; a conta A vê só os 2 da própria fatura; o dono vê os 4';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.21  B viu %, A viu %', v_int, v_int2;
  end if;

  -- D8.22 ─ ninguém depende de chave: religando a chave, o fluxo antigo volta ─
  v_total := v_total + 1;
  update config_negocio set exigir_pagamento_antes_da_1a_entrega = false;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem)
    values ('B6 Sete', 'b6-7@exemplo.test', '30140006', 'Rua', '7', 'Savassi', 'organico') returning id into cli_a;
  ass_a := criar_assinatura(cli_a, v_s);
  if (select count(*) from entregas where assinatura_id = ass_a) = 1
     and (select aguardando_pagamento_desde from assinaturas where id = ass_a) is null then
    raise notice '  OK    D8.22 desligando a chave de novo, a assinatura volta a nascer com a 1ª entrega (a chave é reversível)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D8.22';
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception 'Bloco 6: % de % verificações falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações do Bloco 6 passaram.', v_total;
end;
$$;

rollback;
