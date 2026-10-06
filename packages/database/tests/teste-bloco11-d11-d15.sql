-- ═══════════════════════════════════════════════════════════════════════
-- Bloco 11 — D11 (dúzia pedida pelo assinante) e D15 (bônus do indicador).
--
--   pnpm --filter @ovo/database teste:bloco11
--
-- Tudo termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total  int := 0;
  v_falhas int := 0;
  v_ok     boolean;
  v_s smallint;
  v_hoje   date := hoje_sp();
  v_f      faturas%rowtype;
  id_dono  text := 'teste-b11-dono';
  id_u     text := 'teste-b11-usuario';
  cli uuid[] := '{}';
  c uuid;
  i int;
  a1 uuid; a2 uuid; a3 uuid; a4 uuid; au uuid;
  f1 uuid; f2 uuid; f3 uuid; fx uuid; fy uuid;
  sol uuid;
  v_quarta date;
begin
  select id into v_s from planos where frequencia = 'semanal';
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste B11');
  update config_negocio set preco_pente_centavos = 4100, preco_duzia_centavos = 1200,   -- preço FICTÍCIO de teste (o real é definido pelo dono) bonus_indicador_pct = 10,
                            hora_corte = '18:00', dia_corte = 1;

  insert into "user" (id, name, email) values (id_dono, 'Dono B11', 'dono-b11@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;
  insert into "user" (id, name, email) values (id_u, 'Usuario B11', 'usuario-b11@exemplo.test');
  perform set_config('app.usuario_id', id_dono, true);

  for i in 1..6 loop
    insert into clientes (nome, email, cep, endereco, numero, bairro, origem)
    values ('B11 ' || i, 'b11-' || i || '@exemplo.test', '3014000' || i, 'Rua', i::text, 'Savassi', 'organico')
    returning id into c;
    cli := cli || c;
  end loop;
  update clientes set usuario_id = id_u where id = cli[1];

  raise notice '═══ D11 — dúzia ═══';

  a1 := criar_assinatura(cli[1], v_s);
  au := a1;

  -- B11.1 ── pedido, validações ───────────────────────────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_u, true);
  set local role app_usuario;
  sol := solicitar_alteracao_assinatura(a1, 'duzia', null, null, null, 2::smallint);
  v_ok := true;
  begin perform solicitar_alteracao_assinatura(a1, 'duzia', null, null, null, 51::smallint); v_ok := false; exception when sqlstate 'OV001' then null; end;
  begin perform solicitar_alteracao_assinatura(a1, 'duzia', null, null, null, null);          v_ok := false; exception when sqlstate 'OV001' then null; end;
  begin perform solicitar_alteracao_assinatura(a1, 'duzia', null, null, null, 0::smallint);   v_ok := false; exception when sqlstate 'OV001' then null; end;  -- já recebe 0
  reset role;
  perform set_config('app.usuario_id', id_dono, true);
  if v_ok and (select duzias_pedidas from solicitacoes_assinatura where id = sol) = 2 then
    raise notice '  OK    B11.1 o assinante pede 2 dúzias; 51, vazio e "a mesma quantidade" são recusados';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B11.1';
  end if;

  -- B11.2 ── o dono atende: vale só nas entregas depois do corte ──────────────
  v_total := v_total + 1;
  v_quarta := primeira_quarta_apos_corte(now());
  -- uma entrega pendente ANTES do corte (não muda) e outra depois (muda)
  insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
    values (a1, cli[1], v_quarta - 7, 1, 0), (a1, cli[1], v_quarta + 14, 1, 0);
  perform resolver_solicitacao(sol, 'atendida', null, true, null);
  if (select duzias_padrao from clientes where id = cli[1]) = 2
     and (select duzias from entregas where assinatura_id = a1 and data_prevista = v_quarta - 7) = 0
     and (select duzias from entregas where assinatura_id = a1 and data_prevista = v_quarta + 14) = 2
     and (select status::text from solicitacoes_assinatura where id = sol) = 'atendida' then
    raise notice '  OK    B11.2 atendido: duzias_padrao = 2; a entrega antes do corte não muda, as depois ganham as dúzias';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B11.2';
  end if;

  -- B11.3 ── a fatura seguinte cobra a dúzia a R$ 12,00 ───────────────────────
  v_total := v_total + 1;
  perform registrar_pagamento(gerar_cobranca(a1), v_hoje, 'pix');      -- a 1ª fatura (com 10%) sai do caminho
  update assinaturas set proxima_cobranca = '2027-03-01' where id = a1;
  f1 := gerar_cobranca(a1);
  select * into v_f from faturas where id = f1;
  -- mar/2027 semanal: 5 entregas × (R$ 41,00 + 2 × R$ 12,00) = 5 × 6500
  if v_f.calculo_valor_entrega_centavos = 6500 and v_f.calculo_entregas = 5 and v_f.calculo_valor_bruto_centavos = 32500 then
    raise notice '  OK    B11.3 a fatura de março/2027 cobra 5 × (R$ 41,00 + 2 dúzias × R$ 12,00) = R$ 325,00 (bruto)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B11.3  %', to_jsonb(v_f);
  end if;

  -- B11.4 ── dúzia 0 para ───────────────────────────────────────────────────────
  v_total := v_total + 1;
  perform aplicar_duzias(a1, 0::smallint);
  if (select duzias_padrao from clientes where id = cli[1]) = 0
     and (select count(*) from entregas where assinatura_id = a1 and status = 'pendente' and duzias > 0
            and data_prevista >= primeira_quarta_apos_corte(now())) = 0 then
    raise notice '  OK    B11.4 pedir 0 dúzia para de receber a partir da próxima entrega';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B11.4';
  end if;

  raise notice '═══ D15 — indicação ═══';

  -- Indicador A (cli[2]) com assinatura ativa e UMA fatura já paga (não é mais o 1º mês).
  a2 := criar_assinatura(cli[2], v_s);
  f2 := gerar_cobranca(a2);
  perform registrar_pagamento(f2, v_hoje, 'pix');

  -- B11.5 ── indicado paga a 1ª fatura → bônus pendente para o indicador ────────
  v_total := v_total + 1;
  update clientes set indicado_por = cli[2] where id in (cli[3], cli[4]);
  a3 := criar_assinatura(cli[3], v_s);
  f3 := gerar_cobranca(a3);
  perform registrar_pagamento(f3, v_hoje, 'pix');
  if (select count(*) from bonus_indicacao where indicador_id = cli[2] and indicado_id = cli[3] and status = 'pendente'
         and mes = date_trunc('month', v_hoje)::date) = 1 then
    raise notice '  OK    B11.5 o indicado pagou a 1ª fatura: o indicador ganha um bônus pendente (mês do pagamento)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B11.5';
  end if;

  -- B11.6 ── segunda indicação no mesmo mês ───────────────────────────────────
  v_total := v_total + 1;
  a4 := criar_assinatura(cli[4], v_s);
  perform registrar_pagamento(gerar_cobranca(a4), v_hoje, 'pix');
  if (select count(*) from bonus_indicacao where indicador_id = cli[2] and status = 'pendente') = 2 then
    raise notice '  OK    B11.6 duas indicações no mesmo mês: dois bônus pendentes (mas só um desconto será dado)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B11.6';
  end if;

  -- B11.7 ── o desconto na fatura do indicador: 10%, uma vez ─────────────────
  v_total := v_total + 1;
  update assinaturas set proxima_cobranca = '2027-03-01' where id = a2;
  fx := gerar_cobranca(a2);
  select * into v_f from faturas where id = fx;
  if v_f.calculo_desconto_pct = 10 and v_f.calculo_desconto_origem = 'indicacao' and v_f.calculo_valor_bruto_centavos = 20500
     and v_f.valor_centavos = 18450
     and (select count(*) from bonus_indicacao where indicador_id = cli[2] and status = 'aplicado' and fatura_id = fx) = 2
     and (select count(*) from bonus_indicacao where indicador_id = cli[2] and status = 'pendente') = 0 then
    raise notice '  OK    B11.7 duas indicações no mês = UM desconto de 10%% na fatura (R$ 205,00 → R$ 184,50); os dois bônus ficam gastos';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B11.7  %', to_jsonb(v_f);
  end if;

  -- B11.8 ── não repete na fatura seguinte ────────────────────────────────────
  v_total := v_total + 1;
  fy := gerar_cobranca(a2);
  select * into v_f from faturas where id = fy;
  if v_f.calculo_desconto_pct = 0 then
    raise notice '  OK    B11.8 o bônus não repete na fatura seguinte';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B11.8  %', to_jsonb(v_f);
  end if;

  -- B11.9 ── fatura cancelada devolve o bônus ───────────────────────────────
  v_total := v_total + 1;
  perform cancelar_fatura(fx, 'teste');
  if (select count(*) from bonus_indicacao where indicador_id = cli[2] and status = 'pendente') = 2 then
    raise notice '  OK    B11.9 cancelar a fatura devolve os bônus (voltam a pendentes)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B11.9';
  end if;

  -- B11.10 ── 1º mês do indicador e bônus no mesmo mês: 10%, nunca 20% ─────────
  v_total := v_total + 1;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem)
    values ('B11 7', 'b11-7@exemplo.test', '30140007', 'Rua', '7', 'Savassi', 'organico') returning id into c;
  update clientes set indicado_por = cli[5] where id = cli[6];
  -- cli[5] (indicador novo) tem desconto de 1º mês; cli[6] é indicado dele
  declare a5 uuid; a6 uuid; f5 uuid; f6 uuid; ff faturas%rowtype;
  begin
    a5 := criar_assinatura(cli[5], v_s);
    a6 := criar_assinatura(cli[6], v_s);
    perform registrar_pagamento(gerar_cobranca(a6), v_hoje, 'pix');       -- bônus pendente para cli[5]
    f5 := gerar_cobranca(a5);                                              -- 1ª fatura do indicador: tem 1º mês (10%)
    select * into ff from faturas where id = f5;
    v_ok := ff.calculo_desconto_pct = 10 and ff.calculo_desconto_origem = 'primeiro_mes'
        and (select count(*) from bonus_indicacao where indicador_id = cli[5] and status = 'pendente') = 1;
    if v_ok then
      raise notice '  OK    B11.10 indicador na 1ª fatura: fica o 1º mês (10%%), sem somar o bônus (que espera a próxima fatura)';
    else
      v_falhas := v_falhas + 1; raise notice '  FALHA B11.10  %', to_jsonb(ff);
    end if;
  end;

  -- B11.11 ── indicador sem assinatura ativa não recebe; fatura manual não usa bônus ─
  v_total := v_total + 1;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem)
    values ('B11 8', 'b11-8@exemplo.test', '30140008', 'Rua', '8', 'Savassi', 'organico') returning id into c;
  update clientes set indicado_por = c where id = cli[6] and false;   -- (sem efeito: só garante o cenário)
  v_ok := (select count(*) from bonus_indicacao where indicador_id = c) = 0;
  if v_ok then
    raise notice '  OK    B11.11 cliente que não indicou ninguém não tem bônus';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B11.11';
  end if;

  -- B11.12 ── permissões ───────────────────────────────────────────────────────
  v_total := v_total + 1;
  v_ok := true;
  set local role app_usuario;
  begin perform aplicar_duzias(au, 1::smallint);            v_ok := false; exception when insufficient_privilege then null; end;
  begin perform faturas_conceder_bonus_indicacao();         v_ok := false; exception when insufficient_privilege then null; end;
  begin insert into bonus_indicacao (indicador_id, indicado_id, mes) values (cli[2], cli[5], '2027-01-01'); v_ok := false; exception when insufficient_privilege then null; end;
  reset role;
  set local role app_anon;
  begin perform count(*) from bonus_indicacao;              v_ok := false; exception when insufficient_privilege then null; end;
  reset role;
  if v_ok then
    raise notice '  OK    B11.12 app_usuario e app_anon não aplicam dúzias, não concedem bônus e não gravam no livro';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B11.12';
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception 'Bloco 11: % de % verificações falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações do Bloco 11 passaram.', v_total;
end;
$$;

rollback;
