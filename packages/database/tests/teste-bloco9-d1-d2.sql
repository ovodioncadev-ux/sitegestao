-- ═══════════════════════════════════════════════════════════════════════
-- Bloco 9 — D1 (fatura do mês do calendário, vence dia 3, atrasada dia 8)
-- e D2 (entregas param 20 dias depois da tolerância; voltam ao pagar).
--
--   pnpm --filter @ovo/database teste:bloco9
--
-- Datas fixas no futuro (2027) para a conta do calendário não depender do dia em
-- que o teste roda; o resto usa hoje_sp(). Tudo termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total  int := 0;
  v_falhas int := 0;
  v_int    int;
  v_json   jsonb;
  v_ok     boolean;
  v_s      smallint;
  v_m      smallint;
  v_hoje   date := hoje_sp();
  v_f      faturas%rowtype;
  id_dono  text := 'teste-b9-dono';
  cli1 uuid; cli2 uuid; cli3 uuid;
  ass1 uuid; ass2 uuid; ass3 uuid;
  f0 uuid; f1 uuid; f2 uuid; fa uuid; fb uuid;
begin
  select id into v_s from planos where frequencia = 'semanal';
  select id into v_m from planos where frequencia = 'mensal';
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste B9');
  update config_negocio set preco_pente_centavos = 4100, hora_corte = '18:00', dia_corte = 1;

  insert into "user" (id, name, email) values (id_dono, 'Dono B9', 'dono-b9@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;
  perform set_config('app.usuario_id', id_dono, true);

  insert into clientes (nome, email, cep, endereco, numero, bairro, origem) values ('B9 Um',   'b9-1@exemplo.test', '30140000', 'Rua', '1', 'Savassi', 'organico') returning id into cli1;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem) values ('B9 Dois', 'b9-2@exemplo.test', '30140001', 'Rua', '2', 'Savassi', 'organico') returning id into cli2;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem) values ('B9 Tres', 'b9-3@exemplo.test', '30140002', 'Rua', '3', 'Savassi', 'organico') returning id into cli3;

  raise notice '═══ D1 — o calendário e o vencimento ═══';

  -- B9.1 ── quantas entregas cada plano tem no mês ──────────────────────────
  v_total := v_total + 1;
  if entregas_do_calendario_no_periodo('2027-03-01', '2027-03-31', 'semanal') = 5    -- 5 quartas
     and entregas_do_calendario_no_periodo('2027-02-01', '2027-02-28', 'semanal') = 4
     and entregas_do_calendario_no_periodo('2027-03-01', '2027-03-31', 'quinzenal') = 2
     and entregas_do_calendario_no_periodo('2027-03-01', '2027-03-31', 'mensal') = 1
     and entregas_do_calendario_no_periodo('2027-03-12', '2027-03-31', 'semanal') = 3 then
    raise notice '  OK    B9.1  semanal 4 ou 5 por mês, quinzenal 2, mensal 1; contagem parcial a partir do dia 12';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.1';
  end if;

  -- B9.2 ── tolerância: vence dia 3, atrasada no dia 8 ───────────────────────
  v_total := v_total + 1;
  if not fatura_atrasada_em('2027-03-03', '2027-03-07') and fatura_atrasada_em('2027-03-03', '2027-03-08') then
    raise notice '  OK    B9.2  vencida no dia 3, a fatura vira atrasada no dia 8 (5 dias de tolerância)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.2';
  end if;

  ass1 := criar_assinatura(cli1, v_s);
  f0 := gerar_cobranca(ass1);   -- 1ª fatura (não é a que se testa abaixo)

  -- B9.3 ── mês cheio: período do calendário, vence dia 3, valor pelas entregas ─
  v_total := v_total + 1;
  update assinaturas set proxima_cobranca = '2027-03-01' where id = ass1;
  f1 := gerar_cobranca(ass1);
  select * into v_f from faturas where id = f1;
  if v_f.periodo_inicio = '2027-03-01' and v_f.periodo_fim = '2027-03-31' and v_f.vencimento = '2027-03-03'
     and v_f.status = 'pendente' and v_f.calculo_entregas = 5 and v_f.valor_centavos = 5 * 4100
     and v_f.calculo_desconto_centavos = 0 and v_f.calculo_regra = 'calendario-v1'
     and (select proxima_cobranca from assinaturas where id = ass1) = '2027-04-01' then
    raise notice '  OK    B9.3  mês cheio (mar/2027, semanal): 5 entregas = R$ 205,00, vence dia 3, próxima cobrança 1º de abril';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.3  %', to_jsonb(v_f);
  end if;

  -- B9.4 ── transição no meio do mês: do dia à fim do mês, vence no dia ──────
  v_total := v_total + 1;
  update assinaturas set proxima_cobranca = '2027-05-10' where id = ass1;   -- segunda: a quarta 12 ainda vale (corte 18h)
  f2 := gerar_cobranca(ass1);
  select * into v_f from faturas where id = f2;
  if v_f.periodo_inicio = '2027-05-12' and v_f.periodo_fim = '2027-05-31' and v_f.vencimento = '2027-05-10'
     and v_f.calculo_entregas = 3
     and (select proxima_cobranca from assinaturas where id = ass1) = '2027-06-01' then
    raise notice '  OK    B9.4  cobrança que começa no meio do mês cobra só as entregas restantes (12, 19 e 26) e volta ao dia 1 no mês seguinte';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.4  %', to_jsonb(v_f);
  end if;

  -- B9.5 ── plano mensal já entregue no mês: cobra o mês seguinte inteiro ────
  v_total := v_total + 1;
  ass2 := criar_assinatura(cli2, v_m);
  perform gerar_cobranca(ass2);
  update assinaturas set proxima_cobranca = '2027-03-12' where id = ass2;   -- a 1ª quarta de março (dia 3) já passou
  f2 := gerar_cobranca(ass2);
  select * into v_f from faturas where id = f2;
  if v_f.periodo_inicio = '2027-04-07' and v_f.periodo_fim = '2027-04-30' and v_f.calculo_entregas = 1
     and v_f.vencimento = '2027-03-12' then
    raise notice '  OK    B9.5  mensal sem entrega no resto do mês: a cobrança vai para a 1ª entrega seguinte (abril), em 1 entrega';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.5  %', to_jsonb(v_f);
  end if;

  -- B9.6 ── a rotina gera a fatura com antecedência (7 dias), e só até lá ────
  v_total := v_total + 1;
  update assinaturas set proxima_cobranca = v_hoje + 8 where id = ass1;
  v_json := processar_rotina_diaria();
  v_ok := (v_json ->> 'cobrancas_geradas')::int = 0;
  update assinaturas set proxima_cobranca = v_hoje + 7 where id = ass1;
  v_json := processar_rotina_diaria();
  if v_ok and (v_json ->> 'cobrancas_geradas')::int >= 1 then
    raise notice '  OK    B9.6  fatura do período sai 7 dias antes (8 dias antes ainda não)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.6  %', v_json;
  end if;
  -- limpa: o resto dos testes usa outras assinaturas
  update faturas set status = 'cancelada' where assinatura_id in (ass1, ass2) and status in ('pendente', 'atrasada');

  raise notice '═══ D2 — inadimplência ═══';

  ass3 := criar_assinatura(cli3, v_s);
  f0 := gerar_cobranca(ass3);
  update faturas set status = 'cancelada' where id = f0;
  -- Duas faturas vencidas: uma além do limite de bloqueio (vencimento + 5 + 20 dias) e outra só atrasada.
  insert into faturas (cliente_id, assinatura_id, valor_centavos, vencimento, status)
    values (cli3, ass3, 1000, v_hoje - 25, 'atrasada') returning id into fa;
  insert into faturas (cliente_id, assinatura_id, valor_centavos, vencimento, status)
    values (cli3, ass3, 1000, v_hoje - 31, 'atrasada') returning id into fb;

  -- B9.7 ── 24 dias vencida: ainda não bloqueia ─────────────────────────────
  v_total := v_total + 1;
  update faturas set vencimento = v_hoje - 24 where id = fa;
  update faturas set vencimento = v_hoje - 23 where id = fb;
  v_json := processar_rotina_diaria();
  if (select bloqueada_desde from assinaturas where id = ass3) is null
     and (v_json ->> 'assinaturas_bloqueadas')::int = 0
     and (select count(*) from entregas where assinatura_id = ass3 and status = 'pendente') = 1 then
    raise notice '  OK    B9.7  fatura vencida há 24 dias (< 5 + 20): ainda entrega';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.7  %', v_json;
  end if;

  -- B9.8 ── 25 dias: bloqueia, cancela a entrega pendente, não gera fatura ───
  v_total := v_total + 1;
  update faturas set vencimento = v_hoje - 25 where id = fa;
  update faturas set vencimento = v_hoje - 26 where id = fb;
  v_json := processar_rotina_diaria();
  v_ok := (select bloqueada_desde from assinaturas where id = ass3) = v_hoje
      and (v_json ->> 'assinaturas_bloqueadas')::int = 1
      and (select count(*) from entregas where assinatura_id = ass3 and status = 'pendente') = 0;
  begin perform gerar_cobranca(ass3); v_ok := false; exception when sqlstate 'OV001' then null; end;
  begin perform agendar_entrega(ass3, v_hoje + 14); v_ok := false; exception when sqlstate 'OV001' then null; end;
  begin
    insert into entregas (assinatura_id, cliente_id, data_prevista) values (ass3, cli3, v_hoje + 21);
    v_ok := false;
  exception when sqlstate 'OV001' then null; end;
  if v_ok then
    raise notice '  OK    B9.8  vencida há 25 dias (dia 3 → dia 28): bloqueia, cancela a entrega pendente, recusa fatura e entrega novas';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.8  %', v_json;
  end if;

  -- B9.9 ── rotina não gera fatura nova para bloqueada ───────────────────────
  v_total := v_total + 1;
  update assinaturas set proxima_cobranca = v_hoje where id = ass3;
  v_json := processar_rotina_diaria();
  if (v_json ->> 'cobrancas_geradas')::int = 0 and jsonb_array_length(v_json -> 'falhas') = 0 then
    raise notice '  OK    B9.9  a rotina pula a assinatura bloqueada (sem fatura nova, sem erro)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.9  %', v_json;
  end if;

  -- B9.10 ── pagar UMA das duas faturas não basta ────────────────────────────
  v_total := v_total + 1;
  perform registrar_pagamento(fa, v_hoje, 'pix');
  if (select bloqueada_desde from assinaturas where id = ass3) is not null then
    raise notice '  OK    B9.10 com outra fatura ainda além do limite, a assinatura continua bloqueada';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.10';
  end if;

  -- B9.11 ── pagar a última libera: entrega volta numa quarta, sem cobrar o bloqueio ──
  v_total := v_total + 1;
  perform registrar_pagamento(fb, v_hoje, 'pix');
  select count(*) into v_int from entregas where assinatura_id = ass3 and status = 'pendente';
  if (select bloqueada_desde from assinaturas where id = ass3) is null
     and v_int = 1
     and extract(dow from (select proxima_entrega from assinaturas where id = ass3)) = 3
     and (select proxima_cobranca from assinaturas where id = ass3) >= (date_trunc('month', v_hoje) + interval '1 month')::date then
    raise notice '  OK    B9.11 pagando a última fatura: desbloqueia, agenda a próxima entrega (quarta) e recomeça a cobrança no mês seguinte';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.11  entregas %', v_int;
  end if;

  -- B9.12 ── a rotina de novo não rebloqueia quem pagou ───────────────────────
  v_total := v_total + 1;
  v_json := processar_rotina_diaria();
  if (v_json ->> 'assinaturas_bloqueadas')::int = 0 and (select bloqueada_desde from assinaturas where id = ass3) is null then
    raise notice '  OK    B9.12 quem regularizou não é bloqueado de novo';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.12  %', v_json;
  end if;

  -- B9.13 ── papéis da aplicação não alcançam as funções do bloqueio ─────────
  v_total := v_total + 1;
  v_ok := true;
  set local role app_anon;
  begin perform bloquear_inadimplentes();  v_ok := false; exception when insufficient_privilege then null; end;
  begin perform reavaliar_bloqueio(ass3);  v_ok := false; exception when insufficient_privilege then null; end;
  reset role;
  set local role app_usuario;
  begin perform bloquear_inadimplentes();  v_ok := false; exception when insufficient_privilege then null; end;
  begin perform reavaliar_bloqueio(ass3);  v_ok := false; exception when insufficient_privilege then null; end;
  reset role;
  if v_ok then
    raise notice '  OK    B9.13 app_anon e app_usuario não executam bloquear_inadimplentes nem reavaliar_bloqueio';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B9.13';
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception 'Bloco 9: % de % verificações falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações do Bloco 9 passaram.', v_total;
end;
$$;

rollback;
