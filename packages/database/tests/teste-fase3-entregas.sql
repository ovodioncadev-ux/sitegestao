-- ═══════════════════════════════════════════════════════════════════════
-- Fase 3 — entregas: ciclo, reagendamento, restrições e RLS.
--
--   pnpm --filter @ovo/database teste:fase3
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
  v_data    date;
  v_data2   date;
  v_txt     text;
  v_uuid    uuid;
  v_plano_q smallint;
  v_plano_s smallint;
  cli_a     uuid;
  cli_b     uuid;
  cli_c     uuid;
  ass_a     uuid;
  ass_b     uuid;
  ass_c     uuid;
  ent_1     uuid;
  ent_2     uuid;
  ent_3     uuid;
  id_a      text := 'teste3-conta-a';
  id_b      text := 'teste3-conta-b';
  futuro    date := (select hoje_sp() + 30);
  primeira  date;
begin
  select id into v_plano_q from planos where frequencia = 'quinzenal';
  select id into v_plano_s from planos where frequencia = 'semanal';

  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste');
  insert into "user" (id, name, email) values (id_a, 'A', 'a3@exemplo.test');
  insert into "user" (id, name, email) values (id_b, 'B', 'b3@exemplo.test');

  insert into clientes (usuario_id, nome, cep, endereco, pentes_padrao, duzias_padrao, origem)
  values (id_a, 'Ana Entrega', '30140000', 'Rua A', 2, 1, 'organico') returning id into cli_a;
  insert into clientes (usuario_id, nome, cep, endereco, origem)
  values (id_b, 'Bruno Entrega', '30150000', 'Rua B', 'organico') returning id into cli_b;
  insert into clientes (nome, cep, endereco, origem)
  values ('Carla Passada', '30160000', 'Rua C', 'organico') returning id into cli_c;

  ass_a := criar_assinatura(cli_a, v_plano_q, futuro);
  ass_b := criar_assinatura(cli_b, v_plano_s, futuro);
  primeira := data_primeira_entrega(futuro, v_plano_q);

  -- F3.1 ── a primeira entrega nasce com a assinatura ────────────────────
  v_total := v_total + 1;
  select count(*), min(data_prevista) into v_int, v_data
    from entregas where assinatura_id = ass_a and status = 'pendente';
  select pentes || '/' || duzias into v_txt from entregas where assinatura_id = ass_a;
  if v_int = 1 and v_data = primeira and v_txt = '2/1' then
    raise notice '  OK    F3.1 criar_assinatura cria 1 entrega pendente na 1ª quarta, com 2 pentes + 1 dúzia do cliente';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.1 entregas=%, data=%, esperado=%, qtd=%', v_int, v_data, primeira, v_txt;
  end if;

  -- F3.2 ── proxima_entrega da assinatura acompanha a pendente ───────────
  v_total := v_total + 1;
  select proxima_entrega into v_data from assinaturas where id = ass_a;
  if v_data = primeira then
    raise notice '  OK    F3.2 assinaturas.proxima_entrega = data da entrega pendente (mantida pelo banco)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.2 proxima_entrega = %', v_data;
  end if;

  select id into ent_1 from entregas where assinatura_id = ass_a and status = 'pendente';

  -- F3.3 ── marcar entregue gera a seguinte (próxima do calendário quinzenal, D10) ─────────────
  v_total := v_total + 1;
  perform marcar_entrega(ent_1, 'entregue', 'Deixado na portaria');
  select count(*), min(data_prevista) into v_int, v_data
    from entregas where assinatura_id = ass_a and status = 'pendente';
  if v_int = 1 and v_data = proxima_entrega_do_calendario(primeira, 'quinzenal')
     and (select data_realizada is not null and status = 'entregue' and observacao = 'Deixado na portaria'
            from entregas where id = ent_1) then
    raise notice '  OK    F3.3 entregue: grava data/observação e cria a próxima do calendário quinzenal (1ª/3ª quarta)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.3 pendentes=%, próxima=%, esperado=%', v_int, v_data, proxima_entrega_do_calendario(primeira, 'quinzenal');
  end if;

  v_total := v_total + 1;
  select proxima_entrega into v_data from assinaturas where id = ass_a;
  if v_data = proxima_entrega_do_calendario(primeira, 'quinzenal') then
    raise notice '  OK    F3.4 proxima_entrega avançou junto com o ciclo';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.4 proxima_entrega = %', v_data;
  end if;

  -- F3.5 ── uma entrega resolvida não é reaberta nem remarcada ───────────
  v_total := v_total + 1;
  begin
    perform marcar_entrega(ent_1, 'nao_entregue');
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.5 entrega já entregue foi remarcada';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F3.5 entrega já resolvida não é remarcada (%)', sqlerrm;
  end;

  -- F3.6 ── não entregue + nova data reagenda ────────────────────────────
  select id into ent_2 from entregas where assinatura_id = ass_a and status = 'pendente';
  v_total := v_total + 1;
  v_data2 := hoje_sp() + 45;
  perform marcar_entrega(ent_2, 'nao_entregue', 'Cliente ausente', v_data2);
  select id into ent_3 from entregas where assinatura_id = ass_a and status = 'pendente';
  if (select status from entregas where id = ent_2) = 'nao_entregue'
     and (select data_prevista from entregas where id = ent_3) = v_data2
     and (select reagendada_de from entregas where id = ent_3) = ent_2 then
    raise notice '  OK    F3.6 não entregue reagenda: nasce nova pendente na data informada, ligada à original';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.6 reagendamento';
  end if;

  -- F3.7 ── reagendar para o passado é recusado ──────────────────────────
  v_total := v_total + 1;
  begin
    perform marcar_entrega(ent_3, 'nao_entregue', null, hoje_sp() - 1);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.7 reagendamento no passado foi aceito';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F3.7 reagendar para o passado é recusado (%)', sqlerrm;
  end;

  -- F3.8 ── só "não entregue" reagenda ───────────────────────────────────
  v_total := v_total + 1;
  begin
    perform marcar_entrega(ent_3, 'entregue', null, hoje_sp() + 5);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.8 reagendamento junto com "entregue" foi aceito';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F3.8 só uma entrega "não entregue" pode ser reagendada (%)', sqlerrm;
  end;

  -- F3.9 ── duas entregas vivas no mesmo dia não existem ─────────────────
  v_total := v_total + 1;
  begin
    perform agendar_entrega(ass_a, v_data2);   -- mesma data da pendente atual
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.9 duas entregas pendentes no mesmo dia';
  exception when unique_violation then
    raise notice '  OK    F3.9 duas entregas vivas no mesmo dia são recusadas (índice único)';
  end;

  -- F3.10 ── agendar à mão ────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform agendar_entrega(ass_a, hoje_sp() - 1);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.10 agendar no passado foi aceito';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F3.10 agendar entrega no passado é recusado (%)', sqlerrm;
  end;

  v_total := v_total + 1;
  v_uuid := agendar_entrega(ass_a, hoje_sp() + 60);
  if exists (select 1 from entregas where id = v_uuid and status = 'pendente') then
    raise notice '  OK    F3.11 agendar_entrega cria uma pendente extra';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.11 agendar_entrega';
  end if;

  -- F3.12 ── consistência de cliente/assinatura ────────────────────────────
  v_total := v_total + 1;
  begin
    insert into entregas (assinatura_id, cliente_id, data_prevista) values (ass_a, cli_b, hoje_sp() + 90);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.12 entrega com cliente diferente da assinatura foi aceita';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F3.12 a entrega precisa ser do cliente da assinatura';
  end;

  v_total := v_total + 1;
  begin
    update entregas set status = 'entregue' where id = ent_3;   -- sem data_realizada
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.13 "entregue" sem data de realização foi aceito';
  exception when check_violation then
    raise notice '  OK    F3.13 "entregue" exige data de realização (check)';
  end;

  v_total := v_total + 1;
  begin
    delete from assinaturas where id = ass_a;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.14 assinatura com entregas foi apagada';
  exception when restrict_violation or foreign_key_violation then
    raise notice '  OK    F3.14 assinatura com entregas não pode ser apagada (restrict)';
  end;

  v_total := v_total + 1;
  update entregas set assinatura_id = ass_b, cliente_id = cli_b where id = ent_3;
  if (select assinatura_id from entregas where id = ent_3) = ass_a then
    raise notice '  OK    F3.15 a entrega não muda de assinatura nem de cliente';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.15 a entrega trocou de assinatura';
  end if;

  v_total := v_total + 1;
  perform observacao_entrega(ent_1, 'Cliente elogiou');
  if (select observacao from entregas where id = ent_1) = 'Cliente elogiou' then
    raise notice '  OK    F3.16 a observação pode ser escrita até em entrega já resolvida';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.16 observação';
  end if;

  -- F3.17 ── entrega ATRASADA não gera a próxima no passado ────────────────
  v_total := v_total + 1;
  ass_c := criar_assinatura(cli_c, v_plano_s, date '2026-01-08');   -- 1ª entrega em 14/01/2026 (passado)
  select id into v_uuid from entregas where assinatura_id = ass_c and status = 'pendente';
  perform marcar_entrega(v_uuid, 'entregue');
  select min(data_prevista) into v_data from entregas where assinatura_id = ass_c and status = 'pendente';
  if v_data > hoje_sp() then
    raise notice '  OK    F3.17 entrega feita com atraso: a próxima é calculada a partir de HOJE, não do passado (%)', v_data;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.17 a próxima entrega ficou no passado: %', v_data;
  end if;

  -- F3.18 ── assinatura pausada não gera a próxima ─────────────────────────
  v_total := v_total + 1;
  select id into v_uuid from entregas where assinatura_id = ass_b and status = 'pendente';
  update assinaturas set status = 'pausada' where id = ass_b;
  perform marcar_entrega(v_uuid, 'entregue');
  select count(*) into v_int from entregas where assinatura_id = ass_b and status = 'pendente';
  if v_int = 0 then
    raise notice '  OK    F3.18 assinatura pausada: marcar entregue não cria a próxima';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.18 criou % entrega(s) pendente(s) para assinatura pausada', v_int;
  end if;

  -- ── RLS ───────────────────────────────────────────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_a, true);
  set local role app_usuario;
  select count(*) into v_int from entregas;
  select count(*) into v_int2 from entregas where cliente_id = cli_b;
  reset role;
  if v_int > 0 and v_int2 = 0 and v_int = (select count(*) from entregas where cliente_id = cli_a) then
    raise notice '  OK    F3.19 a conta A vê só as próprias entregas (% linhas) e nenhuma da B', v_int;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.19 A viu % entrega(s); da B: %', v_int, v_int2;
  end if;

  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_a, true);
    set local role app_usuario;
    update entregas set status = 'entregue', data_realizada = now() where cliente_id = cli_a;
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.20 assinante alterou a própria entrega direto na tabela';
  exception when others then
    reset role;
    raise notice '  OK    F3.20 assinante não escreve direto em entregas (recusado)';
  end;

  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_a, true);
    set local role app_usuario;
    perform marcar_entrega(ent_3, 'entregue');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.21 assinante executou marcar_entrega()';
  exception when others then
    reset role;
    raise notice '  OK    F3.21 assinante não executa marcar_entrega() (recusado)';
  end;

  v_total := v_total + 1;
  perform set_config('app.usuario_id', '', true);
  begin
    set local role app_anon;
    select count(*) into v_int from entregas;
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.22 anon leu entregas';
  exception when others then
    reset role;
    raise notice '  OK    F3.22 anon não lê entregas (recusado)';
  end;

  v_total := v_total + 1;
  update perfis set papel = 'dono' where id = id_b;
  perform set_config('app.usuario_id', id_b, true);
  set local role app_usuario;
  select count(*) into v_int from entregas;
  reset role;
  if v_int = (select count(*) from entregas) and v_int > 0 then
    raise notice '  OK    F3.23 CONTROLE POSITIVO: o dono enxerga todas as entregas (%)', v_int;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F3.23 o dono viu % entrega(s)', v_int;
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificacoes da Fase 3 falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificacoes da Fase 3 passaram.', v_total;
end;
$$;

rollback;
