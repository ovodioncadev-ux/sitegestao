-- ═══════════════════════════════════════════════════════════════════════
-- Fase 4 — faturas: valor calculado, ciclo de vida, restrições e RLS.
--
--   pnpm --filter @ovo/database teste:fase4
--
-- Tudo dentro de uma transação que termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total   int := 0;
  v_falhas  int := 0;
  v_int     int;
  v_int2    int;
  v_txt     text;
  v_txt2    text;
  v_uuid    uuid;
  v_plano_s smallint;
  v_plano_q smallint;
  v_plano_m smallint;
  cli_s     uuid;   -- semanal, com desconto
  cli_q     uuid;   -- quinzenal, com desconto
  cli_m     uuid;   -- mensal, com desconto
  cli_sd    uuid;   -- semanal, SEM desconto
  cli_2p    uuid;   -- semanal, 2 pentes
  ass_s     uuid;
  ass_q     uuid;
  ass_m     uuid;
  ass_sd    uuid;
  ass_2p    uuid;
  fat_1     uuid;
  fat_2     uuid;
  id_a      text := 'teste4-conta-a';
  id_b      text := 'teste4-conta-b';
  cli_a     uuid;
  cli_b     uuid;
  ass_a     uuid;
  ass_b     uuid;
  fat_a     uuid;
  fat_b     uuid;
begin
  select id into v_plano_s from planos where frequencia = 'semanal';
  select id into v_plano_q from planos where frequencia = 'quinzenal';
  select id into v_plano_m from planos where frequencia = 'mensal';

  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste');

  -- Preço do pente do teste, independente do que está no banco de verdade:
  -- R$ 41,00, e dúzia R$ 10,00 (só para conferir a soma).
  update config_negocio set preco_pente_centavos = 4100, preco_duzia_centavos = 1000;

  insert into clientes (nome, cep, endereco, origem) values ('Semanal', '30140000', 'R', 'organico') returning id into cli_s;
  insert into clientes (nome, cep, endereco, origem) values ('Quinzenal', '30140001', 'R', 'organico') returning id into cli_q;
  insert into clientes (nome, cep, endereco, origem) values ('Mensal', '30140002', 'R', 'organico') returning id into cli_m;
  insert into clientes (nome, cep, endereco, origem, desconto_primeiro_mes_aplicavel)
    values ('Sem desconto', '30140003', 'R', 'organico', false) returning id into cli_sd;
  insert into clientes (nome, cep, endereco, origem, pentes_padrao, duzias_padrao)
    values ('Dois pentes', '30140004', 'R', 'organico', 2, 1) returning id into cli_2p;

  ass_s  := criar_assinatura(cli_s,  v_plano_s);
  ass_q  := criar_assinatura(cli_q,  v_plano_q);
  ass_m  := criar_assinatura(cli_m,  v_plano_m);
  ass_sd := criar_assinatura(cli_sd, v_plano_s);
  ass_2p := criar_assinatura(cli_2p, v_plano_s);

  -- F4.1 ── entregas por mês derivadas dos preços documentados ────────────
  v_total := v_total + 1;
  if (select array_agg(entregas_por_mes order by intervalo_dias) from planos) = array[4, 2, 1]::smallint[] then
    raise notice '  OK    F4.1 planos: 4 / 2 / 1 entregas por mês (semanal / quinzenal / mensal)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.1 entregas_por_mes fora do esperado';
  end if;

  -- F4.2 ── valor calculado da 1ª fatura, com 10% ────────────────────────
  v_total := v_total + 1;
  if calcular_valor_fatura(ass_s) = 14760      -- 4 × 41,00 = 164,00 − 10%
     and calcular_valor_fatura(ass_q) = 7380   -- 2 × 41,00 =  82,00 − 10%
     and calcular_valor_fatura(ass_m) = 3690 then -- 1 × 41,00 = 41,00 − 10%
    raise notice '  OK    F4.2 1ª fatura com 10%%: semanal 147,60 · quinzenal 73,80 · mensal 36,90';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.2 valores: % / % / %',
      calcular_valor_fatura(ass_s), calcular_valor_fatura(ass_q), calcular_valor_fatura(ass_m);
  end if;

  -- F4.3 ── sem desconto para quem está marcado sem desconto ──────────────
  v_total := v_total + 1;
  if calcular_valor_fatura(ass_sd) = 16400 then
    raise notice '  OK    F4.3 cliente "sem desconto no 1º mês" paga o valor cheio (164,00)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.3 valor = %', calcular_valor_fatura(ass_sd);
  end if;

  -- F4.4 ── quantidade do cliente entra na conta (pentes e dúzias) ────────
  v_total := v_total + 1;
  -- (2 × 4100 + 1 × 1000) × 4 = 36.800; −10% = 33.120
  if calcular_valor_fatura(ass_2p) = 33120 then
    raise notice '  OK    F4.4 2 pentes + 1 dúzia por entrega: 331,20 no 1º mês';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.4 valor = %', calcular_valor_fatura(ass_2p);
  end if;

  -- F4.5 ── criar_fatura usa o valor calculado; o desconto some na 2ª ─────
  v_total := v_total + 1;
  fat_1 := criar_fatura(ass_s, hoje_sp() + 5);
  select valor_centavos into v_int from faturas where id = fat_1;
  fat_2 := criar_fatura(ass_s, hoje_sp() + 35);
  select valor_centavos into v_int2 from faturas where id = fat_2;
  if v_int = 14760 and v_int2 = 16400 then
    raise notice '  OK    F4.5 criar_fatura: 1ª = 147,60 (com desconto), 2ª = 164,00 (cheio)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.5 1ª = %, 2ª = %', v_int, v_int2;
  end if;

  -- F4.6 ── o valor pode ser ajustado à mão ───────────────────────────────
  v_total := v_total + 1;
  v_uuid := criar_fatura(ass_q, hoje_sp() + 7, 5000, 'Valor combinado');
  if (select valor_centavos from faturas where id = v_uuid) = 5000 then
    raise notice '  OK    F4.6 o dono pode informar o valor em vez do calculado';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.6 valor manual não gravado';
  end if;

  -- F4.7 ── recusas ───────────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform criar_fatura(ass_s, hoje_sp() + 5);   -- mesmo vencimento da fat_1
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.7 fatura duplicada (mesma assinatura e vencimento) foi aceita';
  exception when unique_violation then
    raise notice '  OK    F4.7 mesma assinatura + mesmo vencimento não gera duas faturas';
  end;

  v_total := v_total + 1;
  begin
    perform criar_fatura(ass_s, hoje_sp() + 90, 0);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.8 valor zero foi aceito';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F4.8 valor zero é recusado (%)', sqlerrm;
  end;

  v_total := v_total + 1;
  begin
    perform criar_fatura(gen_random_uuid(), hoje_sp());
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.9 fatura de assinatura inexistente foi aceita';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F4.9 assinatura inexistente é recusada (%)', sqlerrm;
  end;

  -- F4.10 ── vencimento no passado nasce atrasada ─────────────────────────
  v_total := v_total + 1;
  v_uuid := criar_fatura(ass_m, hoje_sp() - 10);
  select status::text into v_txt from faturas where id = v_uuid;
  if v_txt = 'atrasada' then
    raise notice '  OK    F4.10 fatura com vencimento no passado nasce "atrasada"';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.10 status = %', v_txt;
  end if;

  -- F4.11 ── marcar_faturas_atrasadas ─────────────────────────────────────
  v_total := v_total + 1;
  insert into faturas (cliente_id, assinatura_id, valor_centavos, vencimento)
  values (cli_q, ass_q, 1000, hoje_sp() - 10) returning id into v_uuid;  -- pendente vencida, inserida direto
  select marcar_faturas_atrasadas() into v_int;
  select status::text into v_txt from faturas where id = v_uuid;
  select status::text into v_txt2 from faturas where id = fat_1;         -- vence no futuro
  if v_int >= 1 and v_txt = 'atrasada' and v_txt2 = 'pendente' then
    raise notice '  OK    F4.11 marcar_faturas_atrasadas vira só as vencidas (fatura futura continua pendente)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.11 vencida=%, futura=%', v_txt, v_txt2;
  end if;

  -- ── Pagamento ─────────────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform registrar_pagamento(fat_1, hoje_sp() + 1, 'pix');
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.12 pagamento com data futura foi aceito';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F4.12 pagamento com data futura é recusado (%)', sqlerrm;
  end;

  v_total := v_total + 1;
  begin
    perform registrar_pagamento(fat_1, hoje_sp(), null);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.13 pagamento sem método foi aceito';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F4.13 pagamento sem método é recusado (%)', sqlerrm;
  end;

  v_total := v_total + 1;
  select status::text into v_txt from clientes where id = cli_s;
  perform registrar_pagamento(fat_1, hoje_sp(), 'pix', 'Comprovante no WhatsApp');
  if (select status::text from faturas where id = fat_1) = 'paga'
     and (select data_pagamento from faturas where id = fat_1) = hoje_sp()
     and (select metodo::text from faturas where id = fat_1) = 'pix'
     and v_txt = 'cadastro_andamento'
     and (select status::text from clientes where id = cli_s) = 'ativo' then
    raise notice '  OK    F4.14 pagamento: fatura "paga" com data e método; 1ª paga torna o cliente ATIVO';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.14 pagamento não registrado corretamente';
  end if;

  v_total := v_total + 1;
  begin
    perform registrar_pagamento(fat_1, hoje_sp(), 'pix');
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.15 fatura paga foi paga de novo';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F4.15 fatura já paga não é paga de novo (%)', sqlerrm;
  end;

  v_total := v_total + 1;
  begin
    perform cancelar_fatura(fat_1, 'engano');
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.16 fatura paga foi cancelada';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F4.16 fatura paga não pode ser cancelada (%)', sqlerrm;
  end;

  -- ── Cancelamento ──────────────────────────────────────────────────────
  v_total := v_total + 1;
  perform cancelar_fatura(fat_2, 'cobrança em duplicidade');
  if (select status::text from faturas where id = fat_2) = 'cancelada'
     and (select observacao from faturas where id = fat_2) like '%cobrança em duplicidade%' then
    raise notice '  OK    F4.17 fatura cancelada, com o motivo guardado';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.17 cancelamento';
  end if;

  v_total := v_total + 1;
  begin
    perform registrar_pagamento(fat_2, hoje_sp(), 'pix');
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.18 fatura cancelada foi paga';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F4.18 fatura cancelada não pode ser paga (%)', sqlerrm;
  end;

  -- ── Constraints ───────────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    update faturas set status = 'paga' where id = (select id from faturas where status = 'pendente' limit 1);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.19 "paga" sem data e método foi aceito';
  exception when check_violation then
    raise notice '  OK    F4.19 "paga" exige data e método (check)';
  end;

  v_total := v_total + 1;
  begin
    insert into faturas (cliente_id, assinatura_id, valor_centavos, vencimento)
    values (cli_s, ass_q, 1000, hoje_sp() + 200);   -- cliente ≠ cliente da assinatura
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.20 fatura com cliente diferente da assinatura foi aceita';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F4.20 a fatura precisa ser do cliente da assinatura';
  end;

  v_total := v_total + 1;
  begin
    delete from assinaturas where id = ass_s;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.21 assinatura com faturas foi apagada';
  exception when restrict_violation or foreign_key_violation then
    raise notice '  OK    F4.21 assinatura com faturas não pode ser apagada (restrict)';
  end;

  -- ── RLS ───────────────────────────────────────────────────────────────
  insert into "user" (id, name, email) values (id_a, 'A', 'a4@exemplo.test');
  insert into "user" (id, name, email) values (id_b, 'B', 'b4@exemplo.test');
  insert into clientes (usuario_id, nome, cep, endereco, origem)
    values (id_a, 'Ana Fatura', '30150000', 'R', 'organico') returning id into cli_a;
  insert into clientes (usuario_id, nome, cep, endereco, origem)
    values (id_b, 'Bruno Fatura', '30150001', 'R', 'organico') returning id into cli_b;
  ass_a := criar_assinatura(cli_a, v_plano_s);
  ass_b := criar_assinatura(cli_b, v_plano_s);
  fat_a := criar_fatura(ass_a, hoje_sp() + 5);
  fat_b := criar_fatura(ass_b, hoje_sp() + 5);

  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_a, true);
  set local role app_usuario;
  select count(*) into v_int from faturas;
  select count(*) into v_int2 from faturas where cliente_id = cli_b;
  reset role;
  if v_int = 1 and v_int2 = 0 then
    raise notice '  OK    F4.22 a conta A vê só a própria fatura e nenhuma da B';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.22 A viu % fatura(s); da B: %', v_int, v_int2;
  end if;

  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_a, true);
    set local role app_usuario;
    update faturas set status = 'cancelada' where id = fat_a;
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.23 assinante alterou a própria fatura direto na tabela';
  exception when others then
    reset role;
    raise notice '  OK    F4.23 assinante não escreve direto em faturas (recusado)';
  end;

  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_a, true);
    set local role app_usuario;
    perform registrar_pagamento(fat_a, hoje_sp(), 'pix');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.24 assinante se deu baixa em uma fatura (registrar_pagamento)';
  exception when others then
    reset role;
    raise notice '  OK    F4.24 assinante não executa registrar_pagamento() (recusado)';
  end;

  v_total := v_total + 1;
  perform set_config('app.usuario_id', '', true);
  begin
    set local role app_anon;
    select count(*) into v_int from faturas;
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.25 anon leu faturas';
  exception when others then
    reset role;
    raise notice '  OK    F4.25 anon não lê faturas (recusado)';
  end;

  v_total := v_total + 1;
  update perfis set papel = 'dono' where id = id_b;
  perform set_config('app.usuario_id', id_b, true);
  set local role app_usuario;
  select count(*) into v_int from faturas;
  reset role;
  if v_int = (select count(*) from faturas) and v_int > 1 then
    raise notice '  OK    F4.26 CONTROLE POSITIVO: o dono enxerga todas as faturas (%)', v_int;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F4.26 o dono viu % fatura(s)', v_int;
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificacoes da Fase 4 falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificacoes da Fase 4 passaram.', v_total;
end;
$$;

rollback;
