-- ═══════════════════════════════════════════════════════════════════════
-- Etapa 2 — calendário de entregas nas quartas (D10) e corte (D9).
--
--   pnpm --filter @ovo/database teste:etapa2
--
-- Determinístico: todas as datas e instantes são fixos (nada depende do dia em
-- que o teste roda), exceto o bloco de reativar, que usa uma segunda-feira
-- futura calculada a partir de hoje (reativar não aceita retorno no passado).
-- Tudo dentro de uma transação que termina em ROLLBACK.
--
-- Calendário de referência (conferido no bloco D10.0):
--   set/2026: quartas 2, 9, 16, 23, 30 (5)     out/2026: 7, 14, 21, 28
--   nov/2026: 4, 11, 18, 25                    dez/2026: 2, 9, 16, 23, 30 (5)
--   jan/2027: 6, 13, 20, 27                    fev/2026: 4, 11, 18, 25
--   abr/2026: 1, 8, 15, 22, 29 (5)
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total  int := 0;
  v_falhas int := 0;
  v_s smallint;
  v_q smallint;
  v_m smallint;
  v_dt date;
  v_txt text;
  v_ent date;
  id_dono text := 'teste-e2-dono';
  cli uuid; cli2 uuid; ass uuid; ass2 uuid;
  v_seg date;

  -- Confere `obtido = esperado` e conta.
  -- (função local via bloco: repetimos o padrão if/else como nos outros testes)
begin
  select id into v_s from planos where frequencia = 'semanal';
  select id into v_q from planos where frequencia = 'quinzenal';
  select id into v_m from planos where frequencia = 'mensal';

  raise notice '═══ D10 — o calendário de quartas ═══';

  -- D10.0 ── as datas de referência são mesmo quartas ─────────────────────
  v_total := v_total + 1;
  if (select bool_and(extract(dow from d) = 3) from unnest(array[
        date '2026-09-02', date '2026-09-30', date '2026-10-07', date '2026-10-28', date '2026-11-04',
        date '2026-12-02', date '2026-12-30', date '2027-01-06', date '2026-04-01', date '2026-04-29',
        date '2026-02-04', date '2026-01-07']) d) then
    raise notice '  OK    D10.0  as datas de referência dos testes são quartas-feiras';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D10.0';
  end if;

  -- D10.1 ── quem é dia de entrega de cada plano ────────────────────────────
  v_total := v_total + 1;
  if data_de_entrega_do_plano(date '2026-10-07', 'semanal') and data_de_entrega_do_plano(date '2026-10-14', 'semanal')
     and data_de_entrega_do_plano(date '2026-09-30', 'semanal')            -- 5ª quarta: semanal entrega
     and not data_de_entrega_do_plano(date '2026-10-08', 'semanal')        -- quinta
     and not data_de_entrega_do_plano(date '2026-10-06', 'semanal')        -- terça
     and data_de_entrega_do_plano(date '2026-10-07', 'quinzenal') and data_de_entrega_do_plano(date '2026-10-21', 'quinzenal')
     and not data_de_entrega_do_plano(date '2026-10-14', 'quinzenal')      -- 2ª
     and not data_de_entrega_do_plano(date '2026-10-28', 'quinzenal')      -- 4ª
     and not data_de_entrega_do_plano(date '2026-09-30', 'quinzenal')      -- 5ª
     and data_de_entrega_do_plano(date '2026-10-07', 'mensal')
     and not data_de_entrega_do_plano(date '2026-10-21', 'mensal')
     and not data_de_entrega_do_plano(date '2026-09-30', 'mensal')         -- 5ª
     and not data_de_entrega_do_plano(date '2026-10-08', 'mensal') then
    raise notice '  OK    D10.1  semanal = toda quarta; quinzenal = 1ª e 3ª; mensal = 1ª; a 5ª quarta só vale para o semanal';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D10.1';
  end if;

  -- ── Semanal ───────────────────────────────────────────────────────────
  v_total := v_total + 1;
  if proxima_entrega_do_calendario(date '2026-10-07', 'semanal') = date '2026-10-14'      -- quarta → semana seguinte
     and proxima_entrega_do_calendario(date '2026-10-14', 'semanal') = date '2026-10-21'
     and proxima_entrega_do_calendario(date '2026-10-28', 'semanal') = date '2026-11-04'  -- virada de mês
     and proxima_entrega_do_calendario(date '2026-09-16', 'semanal') = date '2026-09-23'  -- mês com 5 quartas
     and proxima_entrega_do_calendario(date '2026-09-23', 'semanal') = date '2026-09-30'
     and proxima_entrega_do_calendario(date '2026-09-30', 'semanal') = date '2026-10-07'  -- 5ª quarta → 1ª do mês seguinte
     and proxima_entrega_do_calendario(date '2026-12-30', 'semanal') = date '2027-01-06'  -- virada de ano
     and proxima_entrega_do_calendario(date '2026-10-08', 'semanal') = date '2026-10-14'  -- base fora da quarta
     and proxima_entrega_do_calendario(date '2026-10-13', 'semanal') = date '2026-10-14' then
    raise notice '  OK    D10.2  SEMANAL: quarta → semana seguinte; virada de mês; mês com 5 quartas; virada de ano; base fora da quarta';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D10.2';
  end if;

  -- ── Quinzenal ─────────────────────────────────────────────────────────
  v_total := v_total + 1;
  if proxima_entrega_do_calendario(date '2026-10-07', 'quinzenal') = date '2026-10-21'      -- 1ª → 3ª
     and proxima_entrega_do_calendario(date '2026-10-21', 'quinzenal') = date '2026-11-04'  -- 3ª → 1ª do mês seguinte
     and proxima_entrega_do_calendario(date '2026-01-21', 'quinzenal') = date '2026-02-04'  -- virada de mês
     and proxima_entrega_do_calendario(date '2026-04-01', 'quinzenal') = date '2026-04-15'  -- mês com 5 quartas: 1ª → 3ª
     and proxima_entrega_do_calendario(date '2026-04-15', 'quinzenal') = date '2026-05-06'  -- 3ª → 1ª de maio (pula 22 e 29)
     and proxima_entrega_do_calendario(date '2026-09-16', 'quinzenal') = date '2026-10-07'  -- set (5 quartas): pula 23 e 30
     and proxima_entrega_do_calendario(date '2026-12-02', 'quinzenal') = date '2026-12-16'
     and proxima_entrega_do_calendario(date '2026-12-16', 'quinzenal') = date '2027-01-06'  -- virada de ano
     and proxima_entrega_do_calendario(date '2026-10-14', 'quinzenal') = date '2026-10-21'  -- base na 2ª quarta
     and proxima_entrega_do_calendario(date '2026-09-30', 'quinzenal') = date '2026-10-07'  -- base na 5ª quarta
     and proxima_entrega_do_calendario(date '2026-10-22', 'quinzenal') = date '2026-11-04' then
    raise notice '  OK    D10.3  QUINZENAL: 1ª → 3ª; 3ª → 1ª do mês seguinte; mês com 5 quartas; virada de mês e de ano';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D10.3';
  end if;

  -- ── Mensal ────────────────────────────────────────────────────────────
  v_total := v_total + 1;
  if proxima_entrega_do_calendario(date '2026-10-07', 'mensal') = date '2026-11-04'      -- mês com 4 quartas
     and proxima_entrega_do_calendario(date '2026-02-04', 'mensal') = date '2026-03-04'  -- fev: 4 quartas
     and proxima_entrega_do_calendario(date '2026-11-04', 'mensal') = date '2026-12-02'
     and proxima_entrega_do_calendario(date '2026-09-02', 'mensal') = date '2026-10-07'  -- mês com 5 quartas
     and proxima_entrega_do_calendario(date '2026-04-01', 'mensal') = date '2026-05-06'  -- abr: 5 quartas
     and proxima_entrega_do_calendario(date '2026-12-02', 'mensal') = date '2027-01-06'  -- virada de ano
     and proxima_entrega_do_calendario(date '2026-10-21', 'mensal') = date '2026-11-04'  -- base no meio do mês
     and proxima_entrega_do_calendario(date '2026-09-30', 'mensal') = date '2026-10-07'  -- base na 5ª quarta
     and proxima_entrega_do_calendario(date '2026-10-01', 'mensal') = date '2026-10-07'  -- base antes da 1ª quarta do mês
     and proxima_entrega_do_calendario(date '2026-10-07', 'mensal') <> date '2026-10-07' then
    raise notice '  OK    D10.4  MENSAL: 1ª → 1ª do mês seguinte; meses com 4 e com 5 quartas; virada de ano';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D10.4';
  end if;

  -- ── data_proxima_entrega (a função que as operações chamam) segue o calendário ─
  v_total := v_total + 1;
  if data_proxima_entrega(date '2026-10-07', v_s) = date '2026-10-14'
     and data_proxima_entrega(date '2026-10-07', v_q) = date '2026-10-21'
     and data_proxima_entrega(date '2026-10-07', v_m) = date '2026-11-04'
     and data_proxima_entrega(date '2026-10-21', v_q) = date '2026-11-04' then
    raise notice '  OK    D10.5  data_proxima_entrega(plano) usa o calendário (não soma 7/15/30 dias)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D10.5';
  end if;

  -- Sem contagem em dias: 7/14/28 dias depois NÃO é mais o resultado do quinzenal/mensal.
  v_total := v_total + 1;
  if data_proxima_entrega(date '2026-10-14', v_q) <> date '2026-10-14' + 14   -- 28/10 seria a "contagem em dias"
     and data_proxima_entrega(date '2026-10-14', v_m) <> date '2026-10-14' + 28 then
    raise notice '  OK    D10.6  quinzenal e mensal não dependem de +14 / +28 dias';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D10.6';
  end if;

  raise notice ' ';
  raise notice '═══ D9 — o corte (segunda 18:00, horário de São Paulo) ═══';

  -- Segunda 05/10/2026 é a segunda-feira da semana da quarta 07/10.
  v_total := v_total + 1;
  if extract(dow from date '2026-10-05') = 1 and (select dia_corte = 1 and hora_corte = time '18:00' from config_negocio) then
    raise notice '  OK    D9.0  referência: 05/10/2026 é segunda e o corte configurado é segunda 18:00';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D9.0 (config do corte diferente do esperado pelo teste)';
  end if;

  -- D9.1 ── a fronteira: 17:59, 18:00 e 18:01 ──────────────────────────────
  v_total := v_total + 1;
  if primeira_quarta_apos_corte(timestamp '2026-10-05 17:59:00' at time zone 'America/Sao_Paulo') = date '2026-10-07'
     and primeira_quarta_apos_corte(timestamp '2026-10-05 18:00:00' at time zone 'America/Sao_Paulo') = date '2026-10-07'
     and primeira_quarta_apos_corte(timestamp '2026-10-05 18:00:01' at time zone 'America/Sao_Paulo') = date '2026-10-14'
     and primeira_quarta_apos_corte(timestamp '2026-10-05 18:01:00' at time zone 'America/Sao_Paulo') = date '2026-10-14' then
    raise notice '  OK    D9.1  segunda 17:59 → 07/10; segunda 18:00:00 → 07/10 (só "depois" do corte perde); 18:00:01 e 18:01 → 14/10';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA D9.1  17:59=% 18:00=% 18:00:01=% 18:01=%',
      primeira_quarta_apos_corte(timestamp '2026-10-05 17:59:00' at time zone 'America/Sao_Paulo'),
      primeira_quarta_apos_corte(timestamp '2026-10-05 18:00:00' at time zone 'America/Sao_Paulo'),
      primeira_quarta_apos_corte(timestamp '2026-10-05 18:00:01' at time zone 'America/Sao_Paulo'),
      primeira_quarta_apos_corte(timestamp '2026-10-05 18:01:00' at time zone 'America/Sao_Paulo');
  end if;

  -- D9.2 ── o dia da semana ────────────────────────────────────────────────
  v_total := v_total + 1;
  if primeira_quarta_apos_corte(timestamp '2026-10-04 23:59:00' at time zone 'America/Sao_Paulo') = date '2026-10-07'   -- domingo (antes)
     and primeira_quarta_apos_corte(timestamp '2026-10-06 09:00:00' at time zone 'America/Sao_Paulo') = date '2026-10-14' -- terça
     and primeira_quarta_apos_corte(timestamp '2026-10-07 00:00:00' at time zone 'America/Sao_Paulo') = date '2026-10-14' -- quarta 00:00
     and primeira_quarta_apos_corte(timestamp '2026-10-07 23:59:00' at time zone 'America/Sao_Paulo') = date '2026-10-14' -- quarta 23:59
     and primeira_quarta_apos_corte(timestamp '2026-10-08 10:00:00' at time zone 'America/Sao_Paulo') = date '2026-10-14' -- quinta
     and primeira_quarta_apos_corte(timestamp '2026-10-09 10:00:00' at time zone 'America/Sao_Paulo') = date '2026-10-14' -- sexta
     and primeira_quarta_apos_corte(timestamp '2026-10-10 10:00:00' at time zone 'America/Sao_Paulo') = date '2026-10-14' -- sábado
     and primeira_quarta_apos_corte(timestamp '2026-10-11 23:59:00' at time zone 'America/Sao_Paulo') = date '2026-10-14' -- domingo
     and primeira_quarta_apos_corte(timestamp '2026-10-12 17:59:00' at time zone 'America/Sao_Paulo') = date '2026-10-14' -- segunda seguinte, antes
     and primeira_quarta_apos_corte(timestamp '2026-10-12 18:01:00' at time zone 'America/Sao_Paulo') = date '2026-10-21' then
    raise notice '  OK    D9.2  domingo(antes) → 07/10; terça, quarta, quinta, sexta, sábado, domingo → 14/10; segunda 17:59 → 14/10; segunda 18:01 → 21/10';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D9.2';
  end if;

  -- D9.3 ── fuso: o instante é lido em São Paulo, não em UTC ───────────────
  -- 21:00 UTC = 18:00 em São Paulo (UTC−3).
  v_total := v_total + 1;
  if primeira_quarta_apos_corte(timestamptz '2026-10-05 20:59:59+00') = date '2026-10-07'   -- 17:59:59 SP
     and primeira_quarta_apos_corte(timestamptz '2026-10-05 21:00:00+00') = date '2026-10-07' -- 18:00:00 SP
     and primeira_quarta_apos_corte(timestamptz '2026-10-05 21:00:01+00') = date '2026-10-14' -- 18:00:01 SP
     -- domingo 04/10 23:30 em SP já é segunda 05/10 02:30 em UTC: continua antes do corte.
     and primeira_quarta_apos_corte(timestamptz '2026-10-05 02:30:00+00') = date '2026-10-07'
     -- terça 06/10 23:30 em SP é quarta 07/10 02:30 em UTC: em ambos os casos, depois do corte.
     and primeira_quarta_apos_corte(timestamptz '2026-10-07 02:30:00+00') = date '2026-10-14' then
    raise notice '  OK    D9.3  fuso America/Sao_Paulo respeitado (21:00 UTC = 18:00 SP; virada de dia em UTC não engana)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D9.3';
  end if;

  -- D9.4 ── o corte vem da configuração, não do código ──────────────────────
  v_total := v_total + 1;
  update config_negocio set dia_corte = 2, hora_corte = time '12:00';   -- terça 12:00
  if primeira_quarta_apos_corte(timestamp '2026-10-06 11:59:00' at time zone 'America/Sao_Paulo') = date '2026-10-07'
     and primeira_quarta_apos_corte(timestamp '2026-10-06 12:00:00' at time zone 'America/Sao_Paulo') = date '2026-10-07'
     and primeira_quarta_apos_corte(timestamp '2026-10-06 12:00:01' at time zone 'America/Sao_Paulo') = date '2026-10-14'
     and primeira_quarta_apos_corte(timestamp '2026-10-05 18:01:00' at time zone 'America/Sao_Paulo') = date '2026-10-07' then
    raise notice '  OK    D9.4  com o corte configurado para terça 12:00, a fronteira acompanha a configuração';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D9.4';
  end if;
  update config_negocio set dia_corte = 1, hora_corte = time '18:00';

  -- D9.5 ── corte + calendário juntos (1ª entrega por plano) ────────────────
  v_total := v_total + 1;
  if data_primeira_entrega(date '2026-10-05', v_s, timestamp '2026-10-05 17:59' at time zone 'America/Sao_Paulo') = date '2026-10-07'
     and data_primeira_entrega(date '2026-10-05', v_s, timestamp '2026-10-05 18:01' at time zone 'America/Sao_Paulo') = date '2026-10-14'
     -- quinzenal: fora do corte → quarta 14/10 não é dia do plano → 3ª quarta, 21/10
     and data_primeira_entrega(date '2026-10-05', v_q, timestamp '2026-10-05 17:59' at time zone 'America/Sao_Paulo') = date '2026-10-07'
     and data_primeira_entrega(date '2026-10-05', v_q, timestamp '2026-10-05 18:01' at time zone 'America/Sao_Paulo') = date '2026-10-21'
     -- mensal: 07/10 é a 1ª quarta; perdeu o corte → 1ª quarta de novembro
     and data_primeira_entrega(date '2026-10-05', v_m, timestamp '2026-10-05 17:59' at time zone 'America/Sao_Paulo') = date '2026-10-07'
     and data_primeira_entrega(date '2026-10-05', v_m, timestamp '2026-10-05 18:01' at time zone 'America/Sao_Paulo') = date '2026-11-04'
     -- sem instante: vale o dia informado à 00:00 de São Paulo
     and data_primeira_entrega(date '2026-10-05', v_s) = date '2026-10-07'
     and data_primeira_entrega(date '2026-10-07', v_s) = date '2026-10-14' then
    raise notice '  OK    D9.5  1ª entrega = corte (D9) + calendário do plano (D10): semanal, quinzenal e mensal, antes e depois do corte';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D9.5';
  end if;

  -- D9.6 ── nunca antes do dia de início informado ──────────────────────────
  v_total := v_total + 1;
  if data_primeira_entrega(date '2026-11-02', v_s, timestamp '2026-10-05 10:00' at time zone 'America/Sao_Paulo') = date '2026-11-04' then
    raise notice '  OK    D9.6  início no futuro (02/11) com instante antigo: a 1ª entrega não fica antes do início (04/11)';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D9.6';
  end if;

  raise notice ' ';
  raise notice '═══ Operações reais usando o corte e o calendário ═══';

  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste E2');
  insert into "user" (id, name, email) values (id_dono, 'Dono E2', 'dono-e2@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;
  perform set_config('app.usuario_id', id_dono, true);

  insert into clientes (nome, email, cep, endereco, numero, bairro, origem)
    values ('Cliente E2 A', 'e2a@exemplo.test', '30140000', 'Rua', '1', 'Savassi', 'organico') returning id into cli;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem)
    values ('Cliente E2 B', 'e2b@exemplo.test', '30140001', 'Rua', '2', 'Savassi', 'organico') returning id into cli2;

  -- D9.7 ── criar_assinatura com o instante injetado ────────────────────────
  v_total := v_total + 1;
  ass := criar_assinatura(cli, v_s, null, timestamp '2026-10-05 17:59' at time zone 'America/Sao_Paulo');
  ass2 := criar_assinatura(cli2, v_s, null, timestamp '2026-10-05 18:01' at time zone 'America/Sao_Paulo');
  if (select proxima_entrega from assinaturas where id = ass) = date '2026-10-07'
     and (select data_prevista from entregas where assinatura_id = ass and status = 'pendente') = date '2026-10-07'
     and (select proxima_entrega from assinaturas where id = ass2) = date '2026-10-14'
     and (select data_prevista from entregas where assinatura_id = ass2 and status = 'pendente') = date '2026-10-14'
     and (select data_inicio from assinaturas where id = ass) = date '2026-10-05' then
    raise notice '  OK    D9.7  criar_assinatura(instante 17:59) → 1ª entrega 07/10; (instante 18:01) → 14/10';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D9.7';
  end if;

  -- D10.7 ── marcar_entrega gera a seguinte pelo calendário ─────────────────
  v_total := v_total + 1;
  perform marcar_entrega((select id from entregas where assinatura_id = ass and status = 'pendente'), 'entregue', 'ok');
  -- entregue "hoje" (real): a base é greatest(data_prevista, hoje). Confere só que é
  -- a próxima quarta do calendário semanal depois dessa base, e que é quarta.
  select data_prevista into v_dt from entregas where assinatura_id = ass and status = 'pendente';
  if v_dt = proxima_entrega_do_calendario(greatest(date '2026-10-07', hoje_sp()), 'semanal') and extract(dow from v_dt) = 3 then
    raise notice '  OK    D10.7  marcar_entrega(entregue) cria a próxima quarta do calendário semanal';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D10.7 %', v_dt;
  end if;

  -- D9.8 ── reativar_assinatura respeita o corte no retorno ─────────────────
  -- Uma segunda-feira futura (≥ 7 dias): retorno hoje, instante = segunda 17:59 / 18:01.
  v_seg := hoje_sp() + (((1 - extract(dow from hoje_sp())::int) + 7) % 7) + 7;
  v_total := v_total + 1;
  perform pausar_assinatura(ass2, 'teste');
  perform reativar_assinatura(ass2, null, 'teste', ((v_seg::timestamp + time '17:59')) at time zone 'America/Sao_Paulo');
  select min(data_prevista) into v_dt from entregas where assinatura_id = ass2 and status = 'pendente';
  -- (17:59 da segunda futura → a quarta dessa semana, v_seg + 2)
  if v_dt = v_seg + 2 then
    raise notice '  OK    D9.8a reativar com instante segunda 17:59 → quarta da mesma semana';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D9.8a % (esperado %)', v_dt, v_seg + 2;
  end if;

  v_total := v_total + 1;
  perform pausar_assinatura(ass2, 'teste');
  perform reativar_assinatura(ass2, null, 'teste', ((v_seg::timestamp + time '18:01')) at time zone 'America/Sao_Paulo');
  select min(data_prevista) into v_dt from entregas where assinatura_id = ass2 and status = 'pendente';
  if v_dt = v_seg + 9 then
    raise notice '  OK    D9.8b reativar com instante segunda 18:01 → quarta da semana seguinte';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D9.8b % (esperado %)', v_dt, v_seg + 9;
  end if;

  -- D10.8 ── as funções antigas continuam existindo (compatibilidade) ───────
  v_total := v_total + 1;
  if proxima_quarta(date '2026-10-06') = date '2026-10-07'
     and quarta_mais_proxima(date '2026-10-08') = date '2026-10-07'
     and proxima_entrega_pendente(ass, null) is not null then
    raise notice '  OK    D10.8  proxima_quarta, quarta_mais_proxima e proxima_entrega_pendente seguem disponíveis';
  else
    v_falhas := v_falhas + 1; raise notice '  FALHA D10.8';
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificações da Etapa 2 falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações da Etapa 2 passaram.', v_total;
end;
$$;

rollback;
