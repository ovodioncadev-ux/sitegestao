-- ═══════════════════════════════════════════════════════════════════════
-- Fase 5 — pausar, cancelar e reativar.
--
--   pnpm --filter @ovo/database teste:fase5
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
  v_data    date;
  v_uuid    uuid;
  v_plano_s smallint;
  cli_1     uuid;
  cli_2     uuid;
  ass_1     uuid;
  ass_2     uuid;
  ent_1     uuid;
  fat_pend  uuid;
  fat_atr   uuid;
  fat_paga  uuid;
  id_a      text := 'teste5-conta-a';
begin
  select id into v_plano_s from planos where frequencia = 'semanal';
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste');
  update config_negocio set preco_pente_centavos = 4100;

  insert into clientes (nome, cep, endereco, origem) values ('Cliente Um', '30140000', 'Rua 1', 'organico') returning id into cli_1;
  insert into clientes (nome, cep, endereco, origem) values ('Cliente Dois', '30140001', 'Rua 2', 'organico') returning id into cli_2;

  ass_1 := criar_assinatura(cli_1, v_plano_s);
  select id into ent_1 from entregas where assinatura_id = ass_1 and status = 'pendente';

  -- Uma entrega já FEITA e uma fatura já PAGA: precisam sobreviver a tudo.
  perform marcar_entrega(ent_1, 'entregue', 'feita antes');
  fat_paga := criar_fatura(ass_1, hoje_sp() + 1, 1000);
  perform registrar_pagamento(fat_paga, hoje_sp(), 'pix');

  fat_pend := criar_fatura(ass_1, hoje_sp() + 20, 2000);            -- pendente
  fat_atr  := criar_fatura(ass_1, hoje_sp() - 15, 3000);            -- atrasada

  -- F5.1 ── pausar ─────────────────────────────────────────────────────────
  v_total := v_total + 1;
  perform pausar_assinatura(ass_1, 'viagem');
  select count(*) into v_int from entregas where assinatura_id = ass_1 and status = 'pendente';
  if (select status::text from assinaturas where id = ass_1) = 'pausada' and v_int = 0 then
    raise notice '  OK    F5.1 pausar: assinatura "pausada" e nenhuma entrega pendente sobra';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.1 pausar (pendentes=%)', v_int;
  end if;

  v_total := v_total + 1;
  if (select status::text from entregas where assinatura_id = ass_1 and observacao = 'feita antes') = 'entregue'
     and (select status::text from entregas where assinatura_id = ass_1 and status = 'cancelada' limit 1) = 'cancelada' then
    raise notice '  OK    F5.2 pausar não mexe na entrega já feita; a pendente virou "cancelada"';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.2 histórico de entregas';
  end if;

  v_total := v_total + 1;
  if (select status::text from faturas where id = fat_pend) = 'cancelada'
     and (select status::text from faturas where id = fat_atr) = 'atrasada'
     and (select status::text from faturas where id = fat_paga) = 'paga' then
    raise notice '  OK    F5.3 pausar cancela a fatura PENDENTE; a atrasada continua cobrável; a paga não muda';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.3 faturas: % / % / %',
      (select status from faturas where id = fat_pend), (select status from faturas where id = fat_atr),
      (select status from faturas where id = fat_paga);
  end if;

  v_total := v_total + 1;
  if (select status::text from clientes where id = cli_1) = 'suspenso'
     and (select proxima_entrega from assinaturas where id = ass_1) is null then
    raise notice '  OK    F5.4 pausar: cliente "suspenso" e assinatura sem próxima entrega';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.4 cliente=%', (select status from clientes where id = cli_1);
  end if;

  v_total := v_total + 1;
  begin
    perform pausar_assinatura(ass_1);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.5 assinatura já pausada foi pausada de novo';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F5.5 pausar uma assinatura já pausada é recusado (%)', sqlerrm;
  end;

  -- F5.6 ── reativar (da pausa) ────────────────────────────────────────────
  v_total := v_total + 1;
  perform reativar_assinatura(ass_1);
  select proxima_entrega into v_data from assinaturas where id = ass_1;
  if (select status::text from assinaturas where id = ass_1) = 'ativa'
     and v_data >= hoje_sp() and extract(dow from v_data) = 3
     and (select count(*) from entregas where assinatura_id = ass_1 and status = 'pendente') = 1 then
    raise notice '  OK    F5.6 reativar: "ativa", calendário novo a partir de hoje, na próxima quarta (%)', v_data;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.6 próxima entrega = %', v_data;
  end if;

  v_total := v_total + 1;
  if (select status::text from clientes where id = cli_1) = 'ativo' then
    raise notice '  OK    F5.7 reativar: cliente volta a "ativo" (já tinha fatura paga)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.7 cliente=%', (select status from clientes where id = cli_1);
  end if;

  v_total := v_total + 1;
  begin
    perform reativar_assinatura(ass_1);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.8 assinatura ativa foi reativada';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F5.8 reativar uma assinatura ativa é recusado (%)', sqlerrm;
  end;

  -- F5.9 ── cancelar ───────────────────────────────────────────────────────
  v_total := v_total + 1;
  perform cancelar_assinatura(ass_1, 'mudou de cidade');
  if (select status::text from assinaturas where id = ass_1) = 'cancelada'
     and (select data_cancelamento from assinaturas where id = ass_1) = hoje_sp()
     and (select motivo_cancelamento from assinaturas where id = ass_1) = 'mudou de cidade'
     and (select status::text from clientes where id = cli_1) = 'cancelado'
     and (select count(*) from entregas where assinatura_id = ass_1 and status = 'pendente') = 0 then
    raise notice '  OK    F5.9 cancelar: data e motivo gravados, cliente "cancelado", sem entrega pendente';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.9 cancelamento';
  end if;

  v_total := v_total + 1;
  select count(*) into v_int from assinaturas where id = ass_1;
  select count(*) into v_int2 from entregas where assinatura_id = ass_1;
  if v_int = 1 and v_int2 >= 3
     and (select status::text from faturas where id = fat_paga) = 'paga' then
    raise notice '  OK    F5.10 cancelada NÃO desaparece: a linha, as entregas (%) e a fatura paga continuam', v_int2;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.10 sumiu algo (assinatura=%, entregas=%)', v_int, v_int2;
  end if;

  v_total := v_total + 1;
  begin
    perform cancelar_assinatura(ass_1);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.11 assinatura cancelada foi cancelada de novo';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F5.11 cancelar uma assinatura já cancelada é recusado (%)', sqlerrm;
  end;

  -- F5.12 ── reativar uma CANCELADA ─────────────────────────────────────────
  v_total := v_total + 1;
  select count(*) into v_int from entregas where assinatura_id = ass_1;
  perform reativar_assinatura(ass_1);
  if (select status::text from assinaturas where id = ass_1) = 'ativa'
     and (select data_cancelamento from assinaturas where id = ass_1) is null
     and (select motivo_cancelamento from assinaturas where id = ass_1) is null
     and (select count(*) from entregas where assinatura_id = ass_1) = v_int + 1 then
    raise notice '  OK    F5.12 reativar cancelada: ativa, cancelamento zerado, entregas de antes mantidas (+1 nova)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.12 reativar cancelada';
  end if;

  -- F5.13 ── retorno no passado ─────────────────────────────────────────────
  v_total := v_total + 1;
  perform pausar_assinatura(ass_1);
  begin
    perform reativar_assinatura(ass_1, hoje_sp() - 1);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.13 retorno no passado foi aceito';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F5.13 data de retorno no passado é recusada (%)', sqlerrm;
  end;

  -- F5.14 ── outro cliente com vigente ─────────────────────────────────────
  v_total := v_total + 1;
  perform cancelar_assinatura(ass_1);
  ass_2 := criar_assinatura(cli_1, v_plano_s);      -- nova assinatura do mesmo cliente
  begin
    perform reativar_assinatura(ass_1);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.14 reativou com outra assinatura vigente do mesmo cliente';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F5.14 reativar é recusado se o cliente já tem outra vigente (%)', sqlerrm;
  end;

  -- F5.15 ── fora da área ─────────────────────────────────────────────────
  v_total := v_total + 1;
  ass_2 := criar_assinatura(cli_2, v_plano_s);
  perform pausar_assinatura(ass_2);
  update clientes set cep = '31000000' where id = cli_2;
  begin
    perform reativar_assinatura(ass_2);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.15 reativou com o CEP fora da área';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F5.15 reativar é recusado se o CEP saiu da área (%)', sqlerrm;
  end;

  -- F5.16 ── reativar sem histórico de pagamento → cadastro_andamento ──────
  v_total := v_total + 1;
  update clientes set cep = '30140001' where id = cli_2;
  perform reativar_assinatura(ass_2);
  if (select status::text from clientes where id = cli_2) = 'cadastro_andamento' then
    raise notice '  OK    F5.16 reativar sem nenhuma fatura paga volta o cliente a "cadastro_andamento"';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.16 cliente=%', (select status from clientes where id = cli_2);
  end if;

  -- F5.17 ── só a conexão administrativa executa ───────────────────────────
  v_total := v_total + 1;
  insert into "user" (id, name, email) values (id_a, 'A', 'a5@exemplo.test');
  begin
    perform set_config('app.usuario_id', id_a, true);
    set local role app_usuario;
    perform pausar_assinatura(ass_2);
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F5.17 assinante executou pausar_assinatura()';
  exception when others then
    reset role;
    raise notice '  OK    F5.17 assinante não executa pausar/cancelar/reativar (recusado)';
  end;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificacoes da Fase 5 falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificacoes da Fase 5 passaram.', v_total;
end;
$$;

rollback;
