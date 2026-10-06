-- ═══════════════════════════════════════════════════════════════════════
-- Bloco 10 — D3 a D7: pausa com crédito, troca de plano, cancelamento no fim do mês.
--
--   pnpm --filter @ovo/database teste:bloco10
--
-- Períodos pagos são colocados em 2027 (por UPDATE) para a conta do calendário não depender do
-- dia em que o teste roda. Tudo termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total  int := 0;
  v_falhas int := 0;
  v_int    int;
  v_ok     boolean;
  v_json   jsonb;
  v_s smallint; v_q smallint; v_m smallint;
  v_hoje   date := hoje_sp();
  v_f      faturas%rowtype;
  id_dono  text := 'teste-b10-dono';
  id_u     text := 'teste-b10-usuario';
  cli uuid[] := '{}';
  c uuid;
  i int;
  ass_a uuid; ass_b uuid; ass_c uuid; ass_d uuid; ass_e uuid; ass_f uuid; ass_g uuid; ass_u uuid;
  fa uuid; fb uuid; fc uuid; fd uuid; fe uuid; ff uuid; fx uuid;
  sol uuid;
begin
  select id into v_s from planos where frequencia = 'semanal';
  select id into v_q from planos where frequencia = 'quinzenal';
  select id into v_m from planos where frequencia = 'mensal';
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste B10');
  update config_negocio set preco_pente_centavos = 4100, hora_corte = '18:00', dia_corte = 1;

  insert into "user" (id, name, email) values (id_dono, 'Dono B10', 'dono-b10@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;
  insert into "user" (id, name, email) values (id_u, 'Usuario B10', 'usuario-b10@exemplo.test');
  perform set_config('app.usuario_id', id_dono, true);

  for i in 1..9 loop
    insert into clientes (nome, email, cep, endereco, numero, bairro, origem)
    values ('B10 ' || i, 'b10-' || i || '@exemplo.test', '3014000' || i, 'Rua', i::text, 'Savassi', 'organico')
    returning id into c;
    cli := cli || c;
  end loop;
  update clientes set usuario_id = id_u where id = cli[9];

  -- Assinatura A, B, C...: primeira fatura gerada e paga, com o período trazido para março de 2027.
  ass_a := criar_assinatura(cli[1], v_s);  fa := gerar_cobranca(ass_a);
  perform registrar_pagamento(fa, v_hoje, 'pix');
  update faturas set periodo_inicio = '2027-03-01', periodo_fim = '2027-03-31' where id = fa;

  raise notice '═══ D7 — cancelamento no fim do mês pago ═══';

  -- B10.1 ── agenda para o último dia pago; entregas e cobrança ───────────────
  v_total := v_total + 1;
  perform cancelar_assinatura(ass_a, 'vou me mudar');
  v_ok := (select status::text from assinaturas where id = ass_a) = 'ativa'
      and (select cancelamento_agendado_para from assinaturas where id = ass_a) = '2027-03-31'
      and (select count(*) from entregas where assinatura_id = ass_a and status = 'pendente') = 1
      and (select data_cancelamento from assinaturas where id = ass_a) is null;
  begin perform gerar_cobranca(ass_a); v_ok := false; exception when sqlstate 'OV001' then null; end;
  begin perform cancelar_assinatura(ass_a, 'de novo'); v_ok := false; exception when sqlstate 'OV001' then null; end;
  begin perform pausar_assinatura(ass_a); v_ok := false; exception when sqlstate 'OV001' then null; end;
  if v_ok then
    raise notice '  OK    B10.1 cancelar agenda para o fim do mês pago: segue ativa, entrega mantida, sem cobrança nova, não pausa nem cancela de novo';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.1';
  end if;

  -- B10.2 ── a rotina só executa depois do último dia pago ────────────────────
  v_total := v_total + 1;
  v_json := processar_rotina_diaria();
  v_ok := (select status::text from assinaturas where id = ass_a) = 'ativa' and (v_json ->> 'cancelamentos_executados')::int = 0;
  update assinaturas set cancelamento_agendado_para = v_hoje - 1 where id = ass_a;   -- simula o fim do mês pago
  v_json := processar_rotina_diaria();
  if v_ok and (select status::text from assinaturas where id = ass_a) = 'cancelada'
     and (v_json ->> 'cancelamentos_executados')::int = 1
     and (select data_cancelamento from assinaturas where id = ass_a) = v_hoje
     and (select cancelamento_agendado_para from assinaturas where id = ass_a) is null
     and (select motivo_cancelamento from assinaturas where id = ass_a) = 'vou me mudar'
     and (select status::text from clientes where id = cli[1]) = 'cancelado'
     and (select count(*) from entregas where assinatura_id = ass_a and status = 'pendente') = 0 then
    raise notice '  OK    B10.2 a rotina cancela depois do mês pago, com o motivo, e encerra entregas pendentes';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.2  %', v_json;
  end if;

  -- B10.3 ── desfazer o agendamento; cancelar sem mês pago é imediato ──────────
  v_total := v_total + 1;
  ass_b := criar_assinatura(cli[2], v_s);  fb := gerar_cobranca(ass_b);
  perform registrar_pagamento(fb, v_hoje, 'pix');
  update faturas set periodo_inicio = '2027-03-01', periodo_fim = '2027-03-31' where id = fb;
  perform cancelar_assinatura(ass_b);
  perform desfazer_cancelamento_agendado(ass_b);
  v_ok := (select cancelamento_agendado_para from assinaturas where id = ass_b) is null
      and (select status::text from assinaturas where id = ass_b) = 'ativa';
  ass_c := criar_assinatura(cli[3], v_s);                       -- nada pago
  perform cancelar_assinatura(ass_c, 'não paguei nada');
  if v_ok and (select status::text from assinaturas where id = ass_c) = 'cancelada' then
    raise notice '  OK    B10.3 agendamento desfeito pelo dono; sem mês pago o cancelamento é imediato';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.3';
  end if;

  raise notice '═══ D5, D3 e D4 — pausa ═══';

  -- B10.4 ── duração máxima de 60 dias ───────────────────────────────────────
  v_total := v_total + 1;
  v_ok := true;
  begin perform pausar_assinatura(ass_b, 'x', v_hoje + 61); v_ok := false; exception when sqlstate 'OV001' then null; end;
  if v_ok and (select status::text from assinaturas where id = ass_b) = 'ativa' then
    raise notice '  OK    B10.4 retorno além de 60 dias é recusado';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.4';
  end if;

  -- B10.5 ── D3: entregas pagas e não feitas viram crédito ────────────────────
  v_total := v_total + 1;
  perform pausar_assinatura(ass_b, 'viagem');                    -- sem retorno: todo o mês pago de março/2027
  if (select credito_centavos from pausas_assinatura where assinatura_id = ass_b and status = 'ativa') = 5 * 4100
     and (select entregas_pagas_nao_feitas from pausas_assinatura where assinatura_id = ass_b and status = 'ativa') = 5
     and saldo_credito(ass_b) = 20500
     and (select destino_credito from pausas_assinatura where assinatura_id = ass_b and status = 'ativa') = 'credito' then
    raise notice '  OK    B10.5 pausa em mês pago (mar/2027, semanal): 5 entregas × R$ 41,00 = R$ 205,00 de crédito';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B10.5  saldo=% pausa=%', saldo_credito(ass_b), (select to_jsonb(p) from pausas_assinatura p where assinatura_id = ass_b and status = 'ativa');
  end if;

  -- B10.6 ── o crédito abate a fatura seguinte (sem desconto %) ────────────────
  v_total := v_total + 1;
  perform reativar_assinatura(ass_b);
  update assinaturas set proxima_cobranca = '2027-04-01' where id = ass_b;
  fx := gerar_cobranca(ass_b);
  select * into v_f from faturas where id = fx;
  -- abril/2027: 4 quartas (7, 14, 21, 28) = R$ 164,00; crédito de R$ 205,00 cobre quase tudo
  if v_f.calculo_valor_bruto_centavos = 16400 and v_f.calculo_credito_centavos = 16300 and v_f.valor_centavos = 100
     and saldo_credito(ass_b) = 20500 - 16300 then
    raise notice '  OK    B10.6 crédito de R$ 205,00 abate a fatura de abril (R$ 164,00) até sobrar R$ 1,00; saldo restante R$ 42,00';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.6  % saldo=%', to_jsonb(v_f), saldo_credito(ass_b);
  end if;

  -- B10.7 ── fatura cancelada devolve o crédito ────────────────────────────────
  v_total := v_total + 1;
  perform cancelar_fatura(fx, 'teste');
  if saldo_credito(ass_b) = 20500 then
    raise notice '  OK    B10.7 cancelar a fatura devolve o crédito consumido';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.7  saldo=%', saldo_credito(ass_b);
  end if;

  -- B10.8 ── D15c: desconto percentual vence; o crédito espera ─────────────────
  v_total := v_total + 1;
  ass_d := criar_assinatura(cli[4], v_s);
  insert into creditos_assinatura (assinatura_id, cliente_id, valor_centavos, origem) values (ass_d, cli[4], 3000, 'pausa');
  fd := gerar_cobranca(ass_d);                                  -- 1ª fatura do cliente: tem os 10%
  select * into v_f from faturas where id = fd;
  if v_f.calculo_desconto_pct = 10 and v_f.calculo_credito_centavos = 0 and saldo_credito(ass_d) = 3000 then
    raise notice '  OK    B10.8 na fatura com 10%% do 1º mês o crédito não é usado e continua no saldo (R$ 30,00)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.8  %', to_jsonb(v_f);
  end if;

  -- B10.9 ── "pentes depois": vão junto da 1ª entrega depois do retorno ───────
  v_total := v_total + 1;
  ass_e := criar_assinatura(cli[5], v_s);  fe := gerar_cobranca(ass_e);
  perform registrar_pagamento(fe, v_hoje, 'pix');
  update faturas set periodo_inicio = '2027-03-01', periodo_fim = '2027-03-31' where id = fe;
  perform pausar_assinatura(ass_e, 'pentes', null, 'pentes');
  v_ok := saldo_credito(ass_e) = 0
      and (select pentes_a_repor from pausas_assinatura where assinatura_id = ass_e and status = 'ativa') = 5;
  perform reativar_assinatura(ass_e);
  if v_ok and (select pentes from entregas where assinatura_id = ass_e and status = 'pendente') = 6 then
    raise notice '  OK    B10.9 pausa com "pentes depois": sem crédito; 5 pentes devidos vão na 1ª entrega do retorno (1 + 5)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.9  pentes=%', (select pentes from entregas where assinatura_id = ass_e and status = 'pendente');
  end if;

  -- B10.10 ── D4: fatura atrasada do período fica só com as entregas feitas ───
  v_total := v_total + 1;
  ass_c := criar_assinatura(cli[3], v_s);                        -- (a anterior foi cancelada)
  fc := gerar_cobranca(ass_c);
  update faturas set periodo_inicio = v_hoje - 14, periodo_fim = v_hoje + 14, status = 'atrasada',
                     vencimento = v_hoje - 14 where id = fc;
  insert into entregas (assinatura_id, cliente_id, data_prevista, status, data_realizada)
    values (ass_c, cli[3], v_hoje - 10, 'entregue', now()), (ass_c, cli[3], v_hoje - 3, 'entregue', now());
  select * into v_f from faturas where id = fc;
  perform pausar_assinatura(ass_c, 'pausa com fatura atrasada');
  select * into v_f from faturas where id = fc;
  if v_f.status = 'atrasada' and v_f.calculo_entregas = 2 and v_f.calculo_valor_bruto_centavos = 8200
     and v_f.valor_centavos = 7380 and v_f.calculo_desconto_centavos = 820 then
    raise notice '  OK    B10.10 pausa com fatura atrasada: 2 entregas feitas × R$ 41,00 com 10%% = R$ 73,80';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.10  %', to_jsonb(v_f);
  end if;

  -- B10.11 ── D4: sem nenhuma entrega feita, a fatura do período some ─────────
  v_total := v_total + 1;
  ass_f := criar_assinatura(cli[6], v_s);  ff := gerar_cobranca(ass_f);
  update faturas set periodo_inicio = v_hoje - 3, periodo_fim = v_hoje + 20, status = 'atrasada', vencimento = v_hoje - 3 where id = ff;
  perform pausar_assinatura(ass_f);
  if (select status::text from faturas where id = ff) = 'cancelada' then
    raise notice '  OK    B10.11 pausa sem entrega feita no período: a fatura em aberto é cancelada';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.11';
  end if;

  raise notice '═══ D6 — troca de plano ═══';

  -- B10.12 ── redução vale no mês seguinte e a fatura do mês já sai pelo plano novo ─
  v_total := v_total + 1;
  ass_g := criar_assinatura(cli[7], v_s);  fa := gerar_cobranca(ass_g);
  perform registrar_pagamento(fa, v_hoje, 'pix');
  perform alterar_plano_assinatura(ass_g, v_m);
  v_ok := (select plano_id from assinaturas where id = ass_g) = v_s
      and (select plano_proximo_id from assinaturas where id = ass_g) = v_m
      and (select plano_proximo_a_partir_de from assinaturas where id = ass_g) = (date_trunc('month', v_hoje) + interval '1 month')::date;
  update assinaturas set proxima_cobranca = '2027-05-01', plano_proximo_a_partir_de = '2027-05-01' where id = ass_g;
  fx := gerar_cobranca(ass_g);
  select * into v_f from faturas where id = fx;
  if v_ok and v_f.calculo_plano_frequencia = 'mensal' and v_f.calculo_entregas = 1 and v_f.valor_centavos = 4100 then
    raise notice '  OK    B10.12 redução semanal → mensal fica agendada; a fatura do mês da troca sai pelo plano mensal (1 entrega, R$ 41,00)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.12  ok=% %', v_ok, to_jsonb(v_f);
  end if;

  -- B10.13 ── a rotina aplica a redução na data ─────────────────────────────────
  v_total := v_total + 1;
  update assinaturas set plano_proximo_a_partir_de = v_hoje where id = ass_g;
  v_json := processar_rotina_diaria();
  if (select plano_id from assinaturas where id = ass_g) = v_m
     and (select plano_proximo_id from assinaturas where id = ass_g) is null
     and (select plano_id from clientes where id = cli[7]) = v_m
     and (v_json ->> 'trocas_aplicadas')::int = 1
     and not exists (select 1 from entregas e join assinaturas a on a.id = e.assinatura_id
                      where e.assinatura_id = ass_g and e.status = 'pendente'
                        and not data_de_entrega_do_plano(e.data_prevista, 'mensal')) then
    raise notice '  OK    B10.13 na data, a rotina aplica o plano novo e ajusta a entrega pendente ao calendário dele';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.13  %', v_json;
  end if;

  -- B10.14 ── aumento vale na hora, com fatura de diferença ─────────────────────
  v_total := v_total + 1;
  declare
    v_quarta date := primeira_quarta_apos_corte(now());
    v_fim    date := (date_trunc('month', v_hoje) + interval '1 month')::date - 1;
    v_dif    int;
  begin
    perform alterar_plano_assinatura(ass_g, v_s);              -- mensal → semanal
    v_dif := case when v_quarta <= v_fim
                  then entregas_do_calendario_no_periodo(v_quarta, v_fim, 'semanal')
                     - entregas_do_calendario_no_periodo(v_quarta, v_fim, 'mensal')
                  else 0 end;
    select count(*) into v_int from faturas
     where assinatura_id = ass_g and observacao like 'Diferença de plano%' and status = 'pendente'
       and calculo_entregas = v_dif and valor_centavos = v_dif * 4100;
    if (select plano_id from assinaturas where id = ass_g) = v_s
       and (select plano_proximo_id from assinaturas where id = ass_g) is null
       and ((v_dif > 0 and v_int = 1) or (v_dif = 0 and v_int = 0))
       and (select count(*) from entregas where assinatura_id = ass_g and status = 'pendente') = 1 then
      raise notice '  OK    B10.14 aumento mensal → semanal vale já: fatura avulsa de % entrega(s) de diferença, 1 entrega pendente', v_dif;
    else
      v_falhas := v_falhas + 1; raise notice '  FALHA B10.14  dif=% faturas=%', v_dif, v_int;
    end if;
  end;

  -- B10.15 ── voltar ao plano atual cancela redução agendada; mesmo plano é recusado ─
  v_total := v_total + 1;
  perform alterar_plano_assinatura(ass_d, v_m);                 -- redução agendada
  perform alterar_plano_assinatura(ass_d, v_s);                 -- volta ao atual: cancela o agendamento
  v_ok := (select plano_proximo_id from assinaturas where id = ass_d) is null;
  begin perform alterar_plano_assinatura(ass_d, v_s); v_ok := false; exception when sqlstate 'OV001' then null; end;
  if v_ok then
    raise notice '  OK    B10.15 voltar ao plano atual desfaz a redução agendada; trocar para o mesmo plano é recusado';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.15';
  end if;

  raise notice '═══ Pedidos do assinante e permissões ═══';

  -- B10.16 ── pedido de pausa com "pentes depois" e troca; o dono atende ───────
  v_total := v_total + 1;
  ass_u := criar_assinatura(cli[9], v_s);
  perform set_config('app.usuario_id', id_u, true);
  set local role app_usuario;
  sol := solicitar_alteracao_assinatura(ass_u, 'pausa', 'viagem', 'pentes');
  begin perform solicitar_alteracao_assinatura(ass_u, 'troca_plano', null, null, v_s); v_ok := false; exception when sqlstate 'OV001' then v_ok := true; end;
  perform solicitar_alteracao_assinatura(ass_u, 'troca_plano', 'quero menos', null, v_m);
  reset role;
  perform set_config('app.usuario_id', id_dono, true);
  perform resolver_solicitacao(sol, 'atendida', 'ok', true, null);
  if v_ok and (select status::text from assinaturas where id = ass_u) = 'pausada'
     and (select destino_credito from pausas_assinatura where assinatura_id = ass_u and status = 'ativa') = 'pentes'
     and (select preferencia from solicitacoes_assinatura where id = sol) = 'pentes' then
    raise notice '  OK    B10.16 o assinante pede pausa com "pentes depois" e troca de plano (plano igual é recusado); o dono atende e a preferência vale';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.16';
  end if;

  -- B10.17 ── papéis da aplicação não alcançam as funções internas ────────────
  v_total := v_total + 1;
  v_ok := true;
  set local role app_usuario;
  begin perform cancelar_assinatura_agora(ass_u, 'x');       v_ok := false; exception when insufficient_privilege then null; end;
  begin perform executar_cancelamentos_agendados();           v_ok := false; exception when insufficient_privilege then null; end;
  begin perform aplicar_trocas_agendadas();                   v_ok := false; exception when insufficient_privilege then null; end;
  begin perform reagendar_entregas_pelo_plano(ass_u, v_hoje); v_ok := false; exception when insufficient_privilege then null; end;
  begin perform pausar_assinatura(ass_u);                     v_ok := false; exception when insufficient_privilege then null; end;
  begin perform cancelar_assinatura(ass_u);                   v_ok := false; exception when insufficient_privilege then null; end;
  reset role;
  set local role app_anon;
  begin perform solicitar_alteracao_assinatura(ass_u, 'pausa'); v_ok := false; exception when insufficient_privilege then null; end;
  begin perform count(*) from creditos_assinatura;            v_ok := false; exception when insufficient_privilege then null; end;
  reset role;
  if v_ok then
    raise notice '  OK    B10.17 as funções internas e o livro de créditos não são alcançáveis por app_usuario/app_anon';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA B10.17';
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception 'Bloco 10: % de % verificações falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações do Bloco 10 passaram.', v_total;
end;
$$;

rollback;
