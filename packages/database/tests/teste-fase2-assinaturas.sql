-- ═══════════════════════════════════════════════════════════════════════
-- Fase 2 — assinaturas: datas, regras de criação, constraints e RLS.
--
--   pnpm --filter @ovo/database teste:fase2
--
-- Tudo dentro de uma transação que termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total    int := 0;
  v_falhas   int := 0;
  v_data     date;
  v_bool     boolean;
  v_int      int;
  v_id       uuid;
  v_plano_s  smallint;   -- semanal
  v_plano_q  smallint;   -- quinzenal
  v_plano_m  smallint;   -- mensal
  cli_a      uuid;
  cli_b      uuid;
  cli_sem    uuid;
  cli_fora   uuid;
  ass_a      uuid;
  id_a       text := 'teste2-conta-a';
  id_b       text := 'teste2-conta-b';
  -- 07/01/2026 é uma quarta-feira.
  qua        date := date '2026-01-07';
begin
  select id into v_plano_s from planos where frequencia = 'semanal';
  select id into v_plano_q from planos where frequencia = 'quinzenal';
  select id into v_plano_m from planos where frequencia = 'mensal';

  -- ── Datas ─────────────────────────────────────────────────────────────
  v_total := v_total + 1;
  if extract(dow from qua) = 3 then
    raise notice '  OK    F2.0 a data de referência (07/01/2026) é mesmo uma quarta-feira';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.0 data de referência não é quarta';
  end if;

  v_total := v_total + 1;
  if proxima_quarta(qua) = qua
     and proxima_quarta(qua + 1) = qua + 7      -- quinta → próxima quarta
     and proxima_quarta(qua - 1) = qua then     -- terça → a quarta seguinte
    raise notice '  OK    F2.1 proxima_quarta: quarta fica, quinta pula para a seguinte, terça avança 1 dia';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.1 proxima_quarta';
  end if;

  v_total := v_total + 1;
  if quarta_mais_proxima(qua + 1) = qua          -- quinta  → quarta anterior
     and quarta_mais_proxima(qua + 2) = qua      -- sexta   → quarta anterior
     and quarta_mais_proxima(qua + 3) = qua      -- sábado  → quarta anterior
     and quarta_mais_proxima(qua + 4) = qua + 7  -- domingo → próxima quarta
     and quarta_mais_proxima(qua + 5) = qua + 7  -- segunda → próxima quarta
     and quarta_mais_proxima(qua + 6) = qua + 7  -- terça   → próxima quarta
     and quarta_mais_proxima(qua) = qua then
    raise notice '  OK    F2.2 quarta_mais_proxima acerta os 7 dias da semana';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.2 quarta_mais_proxima';
  end if;

  -- D10 (Etapa 2): calendário de quartas. 07/01/2026 é a 1ª quarta de janeiro.
  -- semanal → 14/01; quinzenal → 21/01 (3ª quarta); mensal → 04/02 (1ª quarta de fevereiro).
  -- A matriz completa está em teste-etapa2-calendario.sql.
  v_total := v_total + 1;
  if data_proxima_entrega(qua, v_plano_s) = date '2026-01-14'
     and data_proxima_entrega(qua, v_plano_q) = date '2026-01-21'
     and data_proxima_entrega(qua, v_plano_m) = date '2026-02-04' then
    raise notice '  OK    F2.3 D10: da 1ª quarta de janeiro, semanal → 14/01, quinzenal → 21/01 (3ª quarta), mensal → 04/02';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.3 calendário: % / % / %',
      data_proxima_entrega(qua, v_plano_s), data_proxima_entrega(qua, v_plano_q), data_proxima_entrega(qua, v_plano_m);
  end if;

  -- planos.ancorar_em_quarta deixou de comandar as datas (D10 substitui a contagem em dias).
  v_total := v_total + 1;
  update planos set ancorar_em_quarta = false;
  if data_proxima_entrega(qua, v_plano_q) = date '2026-01-21'
     and data_proxima_entrega(qua, v_plano_m) = date '2026-02-04' then
    raise notice '  OK    F2.4 D10: ancorar_em_quarta = false não volta à contagem em dias (15/30)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.4 ainda depende de ancorar_em_quarta';
  end if;
  update planos set ancorar_em_quarta = true;

  -- ── Área de entrega e clientes de teste ───────────────────────────────
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste');

  insert into "user" (id, name, email) values (id_a, 'Assinante A', 'a2@exemplo.test');
  insert into "user" (id, name, email) values (id_b, 'Assinante B', 'b2@exemplo.test');

  insert into clientes (usuario_id, nome, cep, endereco, origem)
  values (id_a, 'Ana Assina', '30140000', 'Rua A', 'organico') returning id into cli_a;
  insert into clientes (usuario_id, nome, cep, endereco, origem)
  values (id_b, 'Bruno Assina', '30150000', 'Rua B', 'organico') returning id into cli_b;
  insert into clientes (nome, origem) values ('Sem endereço', 'organico') returning id into cli_sem;
  insert into clientes (nome, cep, endereco, origem)
  values ('Fora da área', '31000000', 'Rua Z', 'organico') returning id into cli_fora;

  -- ── criar_assinatura ──────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform criar_assinatura(gen_random_uuid(), v_plano_s);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.5 cliente inexistente foi aceito';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F2.5 cliente inexistente é recusado (%)', sqlerrm;
  end;

  v_total := v_total + 1;
  begin
    perform criar_assinatura(cli_a, 9999::smallint);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.6 plano inexistente foi aceito';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F2.6 plano inexistente é recusado (%)', sqlerrm;
  end;

  v_total := v_total + 1;
  begin
    perform criar_assinatura(cli_sem, v_plano_s);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.7 cliente sem endereço foi aceito';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F2.7 cliente sem endereço é recusado (%)', sqlerrm;
  end;

  v_total := v_total + 1;
  begin
    perform criar_assinatura(cli_fora, v_plano_s);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.8 CEP fora da área foi aceito';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F2.8 CEP fora da área é recusado (%)', sqlerrm;
  end;

  v_total := v_total + 1;
  ass_a := criar_assinatura(cli_a, v_plano_q, date '2026-01-08');  -- quinta
  select proxima_entrega into v_data from assinaturas where id = ass_a;
  if v_data = date '2026-01-21' then
    raise notice '  OK    F2.9 assinatura quinzenal criada; início na quinta (08/01) → quarta 14/01 pelo corte → 1ª data do calendário quinzenal: 21/01 (3ª quarta)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.9 proxima_entrega = %', v_data;
  end if;

  v_total := v_total + 1;
  select (plano_id = v_plano_q) into v_bool from clientes where id = cli_a;
  if v_bool then
    raise notice '  OK    F2.10 o plano do cliente acompanha o da assinatura';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.10 plano do cliente não acompanhou';
  end if;

  v_total := v_total + 1;
  begin
    perform criar_assinatura(cli_a, v_plano_s);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.11 segunda assinatura vigente foi aceita';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F2.11 segunda assinatura vigente é recusada (%)', sqlerrm;
  end;

  -- O índice único também segura quem tentar por fora da função.
  v_total := v_total + 1;
  begin
    insert into assinaturas (cliente_id, plano_id, data_inicio) values (cli_a, v_plano_s, date '2026-01-01');
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.12 insert direto duplicou a assinatura vigente';
  exception when unique_violation then
    raise notice '  OK    F2.12 índice único barra a duplicata mesmo com insert direto';
  end;

  -- ── Constraints ───────────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    update assinaturas set status = 'cancelada' where id = ass_a;   -- sem data_cancelamento
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.13 cancelada sem data de cancelamento foi aceita';
  exception when check_violation then
    raise notice '  OK    F2.13 cancelada exige data de cancelamento';
  end;

  v_total := v_total + 1;
  begin
    delete from clientes where id = cli_a;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.14 cliente com assinatura foi apagado';
  exception when restrict_violation or foreign_key_violation then
    raise notice '  OK    F2.14 cliente com assinatura não pode ser apagado (restrict)';
  end;

  v_total := v_total + 1;
  begin
    delete from planos where id = v_plano_q;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.15 plano com assinatura foi apagado';
  exception when restrict_violation or foreign_key_violation then
    raise notice '  OK    F2.15 plano com assinatura não pode ser apagado (restrict)';
  end;

  v_total := v_total + 1;
  begin
    update assinaturas set cliente_id = cli_b where id = ass_a;
    select cliente_id into v_id from assinaturas where id = ass_a;
    if v_id = cli_a then
      raise notice '  OK    F2.16 a assinatura não muda de cliente (cliente_id é imutável)';
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA F2.16 a assinatura trocou de cliente';
    end if;
  exception when others then
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.16 %', sqlerrm;
  end;

  -- ── RLS ───────────────────────────────────────────────────────────────
  perform criar_assinatura(cli_b, v_plano_s);

  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_a, true);
  set local role app_usuario;
  select count(*) into v_int from assinaturas;
  reset role;
  if v_int = 1 then
    raise notice '  OK    F2.17 a conta A enxerga só a própria assinatura (1 de 2)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.17 a conta A enxergou % assinatura(s)', v_int;
  end if;

  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_a, true);
    set local role app_usuario;
    update assinaturas set status = 'cancelada' where cliente_id = cli_a;
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.18 assinante alterou a própria assinatura direto na tabela';
  exception when others then
    reset role;
    raise notice '  OK    F2.18 assinante não escreve direto em assinaturas (recusado)';
  end;

  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_a, true);
    set local role app_usuario;
    perform criar_assinatura(cli_a, v_plano_s);
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.19 assinante executou criar_assinatura()';
  exception when others then
    reset role;
    raise notice '  OK    F2.19 assinante não executa criar_assinatura() (recusado)';
  end;

  v_total := v_total + 1;
  perform set_config('app.usuario_id', '', true);
  begin
    set local role app_anon;
    select count(*) into v_int from assinaturas;
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.20 anon leu assinaturas';
  exception when others then
    reset role;
    raise notice '  OK    F2.20 anon não lê assinaturas (recusado)';
  end;

  v_total := v_total + 1;
  update perfis set papel = 'dono' where id = id_a;
  perform set_config('app.usuario_id', id_a, true);
  set local role app_usuario;
  select count(*) into v_int from assinaturas;
  reset role;
  -- Compara com o total real: o banco pode ter outras assinaturas além das do teste.
  if v_int = (select count(*) from assinaturas) and v_int >= 2 then
    raise notice '  OK    F2.21 CONTROLE POSITIVO: o dono enxerga todas as assinaturas (%)', v_int;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F2.21 o dono enxergou % assinatura(s)', v_int;
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificacoes da Fase 2 falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificacoes da Fase 2 passaram.', v_total;
end;
$$;

rollback;
