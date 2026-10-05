-- ═══════════════════════════════════════════════════════════════════════
-- Fase 6 — auditoria: quem, quando, antes, depois — e imutável.
--
--   pnpm --filter @ovo/database teste:fase6
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
  v_uuid    uuid;
  v_plano_s smallint;
  cli_1     uuid;
  ass_1     uuid;
  ent_1     uuid;
  fat_1     uuid;
  fat_2     uuid;
  id_dono   text := 'teste6-dono';
  id_ass    text := 'teste6-assinante';
  quem      text := 'teste6-dono';
begin
  select id into v_plano_s from planos where frequencia = 'semanal';

  insert into "user" (id, name, email) values (id_dono, 'Dono', 'd6@exemplo.test');
  insert into "user" (id, name, email) values (id_ass, 'Assinante', 'a6@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;

  -- Tudo daqui em diante "é feito por" id_dono, como o painel faz.
  perform set_config('app.usuario_id', id_dono, true);

  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste');
  update config_negocio set preco_pente_centavos = 4100;

  -- F6.1 ── cliente criado ────────────────────────────────────────────────
  v_total := v_total + 1;
  insert into clientes (nome, cep, endereco, origem) values ('Cliente Audit', '30140000', 'Rua A', 'organico')
    returning id into cli_1;
  select count(*) into v_int from auditoria
   where acao = 'cliente_criado' and entidade = 'clientes' and entidade_id = cli_1::text
     and usuario_id = id_dono and dados_anteriores is null and dados_novos ->> 'nome' = 'Cliente Audit';
  if v_int = 1 then
    raise notice '  OK    F6.1 cliente criado: 1 linha, com o usuário e os dados novos (sem dados anteriores)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.1 linhas = %', v_int;
  end if;

  -- F6.2 ── cliente alterado: antes e depois ─────────────────────────────
  v_total := v_total + 1;
  update clientes set nome = 'Cliente Audit Editado', telefone = '+5531999990000' where id = cli_1;
  select count(*) into v_int from auditoria
   where acao = 'cliente_alterado' and entidade_id = cli_1::text
     and dados_anteriores ->> 'nome' = 'Cliente Audit'
     and dados_novos ->> 'nome' = 'Cliente Audit Editado'
     and usuario_id = id_dono;
  if v_int = 1 then
    raise notice '  OK    F6.2 cliente alterado: guarda o nome de antes ("Cliente Audit") e o de depois';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.2 linhas = %', v_int;
  end if;

  -- F6.3 ── atualização que não muda nada não gera linha ─────────────────
  v_total := v_total + 1;
  select count(*) into v_int from auditoria where entidade_id = cli_1::text;
  update clientes set nome = nome, cep = cep where id = cli_1;
  select count(*) into v_int2 from auditoria where entidade_id = cli_1::text;
  if v_int = v_int2 then
    raise notice '  OK    F6.3 "salvar sem mudar nada" não polui o histórico';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.3 gerou % linha(s) sem mudança real', v_int2 - v_int;
  end if;

  -- F6.4 ── assinatura e entrega criadas ─────────────────────────────────
  v_total := v_total + 1;
  ass_1 := criar_assinatura(cli_1, v_plano_s);
  select id into ent_1 from entregas where assinatura_id = ass_1 and status = 'pendente';
  if exists (select 1 from auditoria where acao = 'assinatura_criada' and entidade_id = ass_1::text and usuario_id = id_dono)
     and exists (select 1 from auditoria where acao = 'entrega_criada' and entidade_id = ent_1::text) then
    raise notice '  OK    F6.4 assinatura criada e 1ª entrega registradas';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.4 assinatura/entrega criada sem registro';
  end if;

  -- F6.5 ── campo automático não vira "assinatura alterada" ───────────────
  v_total := v_total + 1;
  perform marcar_entrega(ent_1, 'entregue');
  select count(*) into v_int from auditoria where acao = 'assinatura_alterada' and entidade_id = ass_1::text;
  if v_int = 0 and exists (select 1 from auditoria where acao = 'entrega_marcada_entregue' and entidade_id = ent_1::text) then
    raise notice '  OK    F6.5 entrega marcada registrada; a proxima_entrega automática NÃO gera ruído';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.5 assinatura_alterada = %', v_int;
  end if;

  -- F6.6 ── fatura: criada, paga, cancelada (com motivo) ──────────────────
  v_total := v_total + 1;
  fat_1 := criar_fatura(ass_1, hoje_sp() + 5);
  perform registrar_pagamento(fat_1, hoje_sp(), 'pix');
  fat_2 := criar_fatura(ass_1, hoje_sp() + 35);
  perform cancelar_fatura(fat_2, 'cobrança duplicada');
  if exists (select 1 from auditoria where acao = 'fatura_criada' and entidade_id = fat_1::text)
     and exists (select 1 from auditoria where acao = 'pagamento_registrado' and entidade_id = fat_1::text
                    and dados_anteriores ->> 'status' = 'pendente' and dados_novos ->> 'status' = 'paga')
     and exists (select 1 from auditoria where acao = 'fatura_cancelada' and entidade_id = fat_2::text
                    and motivo = 'cobrança duplicada') then
    raise notice '  OK    F6.6 fatura criada, pagamento registrado (pendente → paga) e cancelamento com motivo';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.6 faturas sem o registro esperado';
  end if;

  -- F6.7 ── pausar / reativar / cancelar / reativar ───────────────────────
  v_total := v_total + 1;
  perform pausar_assinatura(ass_1, 'viagem');
  perform reativar_assinatura(ass_1);
  perform cancelar_assinatura(ass_1, 'mudou de cidade');
  perform reativar_assinatura(ass_1, null, 'voltou');
  if exists (select 1 from auditoria where acao = 'assinatura_pausada' and entidade_id = ass_1::text
                and motivo = 'viagem' and dados_anteriores ->> 'status' = 'ativa' and dados_novos ->> 'status' = 'pausada')
     and exists (select 1 from auditoria where acao = 'assinatura_cancelada' and entidade_id = ass_1::text
                and motivo = 'mudou de cidade' and dados_novos ->> 'motivo_cancelamento' = 'mudou de cidade')
     and (select count(*) from auditoria where acao = 'assinatura_reativada' and entidade_id = ass_1::text) = 2 then
    raise notice '  OK    F6.7 pausada, cancelada e reativada (2×): situação anterior, nova, usuário e motivo registrados';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.7 ciclo de vida sem o registro esperado';
  end if;

  -- F6.8 ── reativar preserva, na auditoria, o cancelamento de antes ─────
  v_total := v_total + 1;
  if exists (select 1 from auditoria
              where acao = 'assinatura_reativada' and entidade_id = ass_1::text
                and dados_anteriores ->> 'data_cancelamento' is not null
                and dados_anteriores ->> 'motivo_cancelamento' = 'mudou de cidade'
                and dados_novos ->> 'data_cancelamento' is null) then
    raise notice '  OK    F6.8 a linha zera o cancelamento ao reativar, mas a auditoria guarda o de antes';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.8 histórico do cancelamento perdido';
  end if;

  -- F6.9 ── o motivo vale para as entregas canceladas em cascata ─────────
  v_total := v_total + 1;
  select count(*) into v_int from auditoria
   where entidade = 'entregas' and acao = 'entrega_marcada_cancelada' and motivo in ('viagem', 'mudou de cidade');
  if v_int >= 1 then
    raise notice '  OK    F6.9 entregas canceladas pela pausa/cancelamento carregam o motivo (% linha(s))', v_int;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.9 entregas canceladas em cascata sem motivo';
  end if;

  -- F6.10 ── vínculo de conta ──────────────────────────────────────────────
  v_total := v_total + 1;
  update clientes set usuario_id = id_ass where id = cli_1;
  update clientes set usuario_id = null   where id = cli_1;
  if exists (select 1 from auditoria where acao = 'conta_vinculada' and entidade_id = cli_1::text)
     and exists (select 1 from auditoria where acao = 'conta_desvinculada' and entidade_id = cli_1::text) then
    raise notice '  OK    F6.10 conta vinculada e desvinculada ficam registradas';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.10 vínculo sem registro';
  end if;

  -- F6.11 ── configuração e área de entrega ────────────────────────────────
  v_total := v_total + 1;
  update config_negocio set preco_duzia_centavos = 1234;
  insert into faixas_cep_atendidas (cep_inicio, cep_fim) values ('31000000', '31000999');
  if exists (select 1 from auditoria where acao = 'configuracao_alterada'
              and dados_anteriores ->> 'preco_duzia_centavos' is distinct from dados_novos ->> 'preco_duzia_centavos')
     and exists (select 1 from auditoria where acao = 'faixa_criada') then
    raise notice '  OK    F6.11 alteração de configuração e criação de faixa de CEP registradas';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.11 configuração/faixa sem registro';
  end if;

  -- F6.12 ── ação sem usuário na transação = "sistema" ─────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', '', true);
  update clientes set apelido = 'Sem usuário' where id = cli_1;
  if exists (select 1 from auditoria where entidade_id = cli_1::text and acao = 'cliente_alterado'
              and dados_novos ->> 'apelido' = 'Sem usuário' and usuario_id is null) then
    raise notice '  OK    F6.12 sem usuário na transação, a linha fica como "sistema" (usuario_id nulo)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.12 ação sem usuário';
  end if;

  -- ── Imutabilidade — até para a conexão administrativa ───────────────────
  v_total := v_total + 1;
  begin
    update auditoria set acao = 'reescrita' where id = (select min(id) from auditoria);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.13 UPDATE em auditoria foi aceito';
  exception when others then
    raise notice '  OK    F6.13 UPDATE em auditoria é recusado até para a conexão administrativa';
  end;

  v_total := v_total + 1;
  begin
    delete from auditoria where id = (select min(id) from auditoria);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.14 DELETE em auditoria foi aceito';
  exception when others then
    raise notice '  OK    F6.14 DELETE em auditoria é recusado';
  end;

  v_total := v_total + 1;
  begin
    truncate auditoria;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.15 TRUNCATE em auditoria foi aceito';
  exception when others then
    raise notice '  OK    F6.15 TRUNCATE em auditoria é recusado';
  end;

  -- ── RLS ───────────────────────────────────────────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_ass, true);
  set local role app_usuario;
  select count(*) into v_int from auditoria;
  reset role;
  if v_int = 0 then
    raise notice '  OK    F6.16 o assinante não enxerga nenhuma linha da auditoria';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.16 o assinante leu % linha(s) da auditoria', v_int;
  end if;

  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_ass, true);
    set local role app_usuario;
    insert into auditoria (acao, entidade, entidade_id) values ('forjada', 'clientes', 'x');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.17 assinante gravou linha na auditoria';
  exception when others then
    reset role;
    raise notice '  OK    F6.17 assinante não escreve na auditoria (recusado)';
  end;

  v_total := v_total + 1;
  perform set_config('app.usuario_id', '', true);
  begin
    set local role app_anon;
    select count(*) into v_int from auditoria;
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.18 anon leu a auditoria';
  exception when others then
    reset role;
    raise notice '  OK    F6.18 anon não lê a auditoria (recusado)';
  end;

  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_dono, true);
  set local role app_usuario;
  select count(*) into v_int from auditoria;
  reset role;
  if v_int = (select count(*) from auditoria) and v_int > 10 then
    raise notice '  OK    F6.19 CONTROLE POSITIVO: o dono lê a auditoria inteira (% linhas)', v_int;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F6.19 o dono leu % linha(s)', v_int;
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificacoes da Fase 6 falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificacoes da Fase 6 passaram.', v_total;
end;
$$;

rollback;
