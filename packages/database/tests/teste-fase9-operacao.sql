-- ═══════════════════════════════════════════════════════════════════════
-- Fase 9 — operação: cobrança do período, pausa controlada, reposição de
-- defeitos, resposta aos pedidos, horário de entrega e rotina diária.
--
--   pnpm --filter @ovo/database teste:fase9
--
-- Tudo dentro de uma transação que termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total   int := 0;
  v_falhas  int := 0;
  v_int     int;
  v_txt     text;
  v_data    date;
  v_json    jsonb;
  v_hoje    date := hoje_sp();
  v_plano_s smallint;
  v_plano_q smallint;
  id_dono   text := 'teste9-dono';
  id_a      text := 'teste9-conta-a';
  cli_1     uuid;
  ass_1     uuid;
  ent_1     uuid;
  ent_2     uuid;
  ent_3     uuid;
  fat_1     uuid;
  fat_2     uuid;
  rep_1     uuid;
  sol_1     uuid;

  procedure_ok boolean;
begin
  select id into v_plano_s from planos where frequencia = 'semanal';
  select id into v_plano_q from planos where frequencia = 'quinzenal';
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste F9');
  update config_negocio set preco_pente_centavos = 4100, preco_duzia_centavos = 0;

  insert into "user" (id, name, email) values (id_dono, 'Dono F9', 'dono-f9@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;
  perform set_config('app.usuario_id', id_dono, true);

  insert into clientes (nome, email, cep, endereco, numero, bairro, origem)
    values ('Cliente F9', 'cli.f9@exemplo.test', '30140000', 'Rua 9', '9', 'Savassi', 'organico')
    returning id into cli_1;

  raise notice '═══ Cobrança do período ═══';

  -- F9.1 ── assinatura nova já nasce com próxima cobrança = início ────────
  v_total := v_total + 1;
  ass_1 := criar_assinatura(cli_1, v_plano_s);
  if (select proxima_cobranca from assinaturas where id = ass_1) = v_hoje
     and (select forma_cobranca::text from assinaturas where id = ass_1) = 'pix' then
    raise notice '  OK    F9.1  assinatura nova: próxima cobrança hoje, forma PIX por padrão';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.1  proxima_cobranca = %', (select proxima_cobranca from assinaturas where id = ass_1);
  end if;

  -- F9.2 ── 1ª cobrança: R$ 164 com 10% = R$ 147,60, período de 1 mês ──────
  v_total := v_total + 1;
  fat_1 := gerar_cobranca(ass_1);
  if (select valor_centavos from faturas where id = fat_1) = 14760
     and (select periodo_inicio from faturas where id = fat_1) = v_hoje
     and (select periodo_fim from faturas where id = fat_1) = (v_hoje + interval '1 month')::date - 1
     and (select vencimento from faturas where id = fat_1) = v_hoje
     and (select proxima_cobranca from assinaturas where id = ass_1) = (v_hoje + interval '1 month')::date then
    raise notice '  OK    F9.2  1ª cobrança semanal R$ 147,60 (10%% off), período de 1 mês, próxima avança 1 mês';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.2  valor=% proxima=%', (select valor_centavos from faturas where id = fat_1),
      (select proxima_cobranca from assinaturas where id = ass_1);
  end if;

  -- F9.3 ── pagar com cartão; a 2ª cobrança vem sem desconto ────────────────
  v_total := v_total + 1;
  perform registrar_pagamento(fat_1, v_hoje, 'cartao');
  fat_2 := gerar_cobranca(ass_1);
  if (select metodo::text from faturas where id = fat_1) = 'cartao'
     and (select valor_centavos from faturas where id = fat_2) = 16400
     and (select status::text from clientes where id = cli_1) = 'ativo' then
    raise notice '  OK    F9.3  pagamento no cartão registrado; 2ª cobrança R$ 164,00 (sem desconto); cliente ativo';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.3  metodo=% valor2=%', (select metodo from faturas where id = fat_1),
      (select valor_centavos from faturas where id = fat_2);
  end if;

  -- F9.4 ── rotina diária não duplica cobrança já gerada ────────────────────
  v_total := v_total + 1;
  select count(*) into v_int from faturas where assinatura_id = ass_1;
  v_json := processar_rotina_diaria();
  v_json := processar_rotina_diaria();
  if (select count(*) from faturas where assinatura_id = ass_1) = v_int then
    raise notice '  OK    F9.4  rotina rodando 2x não cria cobrança repetida (%)', v_json;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.4  faturas antes=% depois=%', v_int, (select count(*) from faturas where assinatura_id = ass_1);
  end if;

  -- F9.5 ── rotina gera o que venceu (cobrança atrasada no passado) ─────────
  v_total := v_total + 1;
  update assinaturas set proxima_cobranca = v_hoje - 70 where id = ass_1;
  v_json := processar_rotina_diaria();
  if (v_json ->> 'cobrancas_geradas')::int >= 2
     and (select proxima_cobranca from assinaturas where id = ass_1) > v_hoje
     and exists (select 1 from faturas where assinatura_id = ass_1 and periodo_inicio = v_hoje - 70 and status = 'atrasada') then
    raise notice '  OK    F9.5  rotina gera os períodos vencidos (marcados atrasados) e deixa a próxima no futuro';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.5  %', v_json;
  end if;

  -- F9.6 ── forma de cobrança muda e fica no histórico ──────────────────────
  v_total := v_total + 1;
  perform definir_forma_cobranca(ass_1, 'cartao');
  if (select forma_cobranca::text from assinaturas where id = ass_1) = 'cartao'
     and exists (select 1 from auditoria where acao = 'forma_cobranca_alterada' and entidade_id = ass_1::text) then
    raise notice '  OK    F9.6  forma de cobrança → cartão, registrada na auditoria';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.6';
  end if;

  raise notice ' ';
  raise notice '═══ Plano ═══';

  -- F9.7 ── trocar plano: histórico e próxima operação ──────────────────────
  v_total := v_total + 1;
  perform alterar_plano_assinatura(ass_1, v_plano_q);
  if (select plano_id from assinaturas where id = ass_1) = v_plano_q
     and exists (select 1 from auditoria where acao = 'plano_da_assinatura_alterado' and entidade_id = ass_1::text)
     and calcular_valor_fatura(ass_1) = 8200 then
    raise notice '  OK    F9.7  plano semanal → quinzenal: histórico gravado; próxima cobrança calcula R$ 82,00';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.7  valor=%', calcular_valor_fatura(ass_1);
  end if;
  perform alterar_plano_assinatura(ass_1, v_plano_s);

  raise notice ' ';
  raise notice '═══ Entregas, horário e defeitos ═══';

  -- F9.8 ── horário numa entrega pendente ───────────────────────────────────
  v_total := v_total + 1;
  select id into ent_1 from entregas where assinatura_id = ass_1 and status = 'pendente';
  perform definir_horario_entrega(ent_1, '09:30');
  if (select horario_previsto from entregas where id = ent_1) = '09:30'::time then
    raise notice '  OK    F9.8  horário previsto gravado na entrega pendente';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.8';
  end if;

  -- F9.9 ── entregar → próxima criada → defeito liga na próxima ─────────────
  v_total := v_total + 1;
  perform marcar_entrega(ent_1, 'entregue', null);
  select id into ent_2 from entregas where assinatura_id = ass_1 and status = 'pendente';
  rep_1 := registrar_defeito(ent_1, 5::smallint, '5 ovos trincados');
  if (select entrega_reposicao_id from reposicoes where id = rep_1) = ent_2
     and (select status::text from reposicoes where id = rep_1) = 'pendente'
     and exists (select 1 from auditoria where acao = 'defeito_registrado' and entidade_id = rep_1::text) then
    raise notice '  OK    F9.9  defeito registrado e ligado à próxima entrega pendente; histórico gravado';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.9';
  end if;

  -- F9.10 ── defeito só em entrega já feita ─────────────────────────────────
  v_total := v_total + 1;
  begin
    perform registrar_defeito(ent_2, 1::smallint, 'ainda não entregue');
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.10 aceitou defeito em entrega pendente';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F9.10 defeito em entrega não feita é recusado (%)', sqlerrm;
  end;

  -- F9.11 ── não entregue + reagendar: a reposição acompanha ────────────────
  v_total := v_total + 1;
  perform marcar_entrega(ent_2, 'nao_entregue', 'ausente', v_hoje + 14);
  select id into ent_3 from entregas where assinatura_id = ass_1 and status = 'pendente';
  if (select entrega_reposicao_id from reposicoes where id = rep_1) = ent_3 and ent_3 <> ent_2 then
    raise notice '  OK    F9.11 entrega não realizada: a reposição passa para a entrega reagendada';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.11 reposicao aponta para %', (select entrega_reposicao_id from reposicoes where id = rep_1);
  end if;

  -- F9.12 ── entregar a reposição conclui ───────────────────────────────────
  v_total := v_total + 1;
  perform marcar_entrega(ent_3, 'entregue', null);
  if (select status::text from reposicoes where id = rep_1) = 'reposta'
     and (select reposta_em from reposicoes where id = rep_1) is not null
     and exists (select 1 from auditoria where acao = 'reposicao_realizada' and entidade_id = rep_1::text) then
    raise notice '  OK    F9.12 entrega feita → reposição "reposta"; histórico da substituição gravado';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.12 status=%', (select status from reposicoes where id = rep_1);
  end if;

  -- F9.13 ── reposição não entra no valor da cobrança ───────────────────────
  v_total := v_total + 1;
  if calcular_valor_fatura(ass_1) = 16400 then
    raise notice '  OK    F9.13 reposição sem custo: valor da cobrança continua R$ 164,00';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.13 valor=%', calcular_valor_fatura(ass_1);
  end if;

  raise notice ' ';
  raise notice '═══ Pausa controlada ═══';

  -- F9.14 ── pausar com retorno: para cobrança e entregas ───────────────────
  v_total := v_total + 1;
  perform gerar_cobranca(ass_1);   -- uma cobrança pendente para ver o efeito da pausa
  perform pausar_assinatura(ass_1, 'viagem', v_hoje + 20);
  if (select status::text from assinaturas where id = ass_1) = 'pausada'
     and (select proxima_cobranca from assinaturas where id = ass_1) is null
     and (select data_retorno_prevista from assinaturas where id = ass_1) = v_hoje + 20
     and (select pausada_em from assinaturas where id = ass_1) = v_hoje
     and not exists (select 1 from entregas where assinatura_id = ass_1 and status = 'pendente')
     and not exists (select 1 from faturas where assinatura_id = ass_1 and status = 'pendente')
     and (select status::text from clientes where id = cli_1) = 'suspenso' then
    raise notice '  OK    F9.14 pausa: sem entrega nem cobrança pendente, próxima cobrança parada, retorno previsto gravado';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.14';
  end if;

  -- F9.15 ── retorno previsto no passado é recusado ─────────────────────────
  v_total := v_total + 1;
  begin
    perform reativar_assinatura(ass_1);
    perform pausar_assinatura(ass_1, 'x', v_hoje);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.15 aceitou retorno hoje';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F9.15 retorno previsto precisa ser depois de hoje (%)', sqlerrm;
  end;

  -- F9.16 ── rotina reativa na data de retorno ──────────────────────────────
  v_total := v_total + 1;
  if (select status::text from assinaturas where id = ass_1) <> 'pausada' then
    perform pausar_assinatura(ass_1, 'viagem', v_hoje + 20);
  end if;
  -- Simula que o retorno chegou (a data real é futura).
  update assinaturas set pausada_em = v_hoje - 20, data_retorno_prevista = v_hoje where id = ass_1;
  v_json := processar_rotina_diaria();
  select proxima_entrega into v_data from assinaturas where id = ass_1;
  if (select status::text from assinaturas where id = ass_1) = 'ativa'
     and (v_json ->> 'reativadas')::int = 1
     and (select data_retorno_prevista from assinaturas where id = ass_1) is null
     and extract(dow from v_data) = 3
     and exists (select 1 from faturas where assinatura_id = ass_1 and periodo_inicio = v_hoje and status <> 'cancelada')
     and exists (select 1 from auditoria where acao = 'assinatura_reativada' and entidade_id = ass_1::text
                   and motivo = 'Retorno programado da pausa') then
    raise notice '  OK    F9.16 retorno programado: reativa, próxima entrega numa quarta (%), cobrança do novo período gerada', v_data;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.16 %', v_json;
  end if;

  raise notice ' ';
  raise notice '═══ Pedidos do assinante ═══';

  insert into "user" (id, name, email, "emailVerified") values (id_a, 'Assinante F9', 'cli.f9@exemplo.test', true);
  update clientes set usuario_id = id_a where id = cli_1;

  -- F9.17 ── atender pedido de pausa executando a pausa ─────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_a, true);
  set local role app_usuario;
  sol_1 := solicitar_alteracao_assinatura(ass_1, 'pausa', 'férias');
  reset role;
  perform set_config('app.usuario_id', id_dono, true);
  perform resolver_solicitacao(sol_1, 'atendida', 'Boas férias!', true, v_hoje + 30);
  if (select status::text from solicitacoes_assinatura where id = sol_1) = 'atendida'
     and (select resolvida_por from solicitacoes_assinatura where id = sol_1) = id_dono
     and (select resposta from solicitacoes_assinatura where id = sol_1) = 'Boas férias!'
     and (select status::text from assinaturas where id = ass_1) = 'pausada'
     and (select data_retorno_prevista from assinaturas where id = ass_1) = v_hoje + 30
     and exists (select 1 from auditoria where acao = 'solicitacao_atendida' and entidade_id = sol_1::text) then
    raise notice '  OK    F9.17 dono atende o pedido de pausa e a pausa é executada na mesma transação';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.17';
  end if;

  -- F9.18 ── pedido já respondido não é respondido de novo ──────────────────
  v_total := v_total + 1;
  begin
    perform resolver_solicitacao(sol_1, 'recusada');
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.18 respondeu duas vezes';
  exception when sqlstate 'OV001' then
    raise notice '  OK    F9.18 pedido já respondido é recusado (%)', sqlerrm;
  end;

  -- F9.19 ── assinante não executa as funções do dono ───────────────────────
  v_total := v_total + 1;
  v_int := 0;
  perform set_config('app.usuario_id', id_a, true);
  set local role app_usuario;
  begin perform resolver_solicitacao(sol_1, 'recusada'); exception when others then v_int := v_int + 1; end;
  begin perform gerar_cobranca(ass_1); exception when others then v_int := v_int + 1; end;
  begin perform processar_rotina_diaria(); exception when others then v_int := v_int + 1; end;
  begin perform registrar_defeito(ent_1, 1::smallint, 'forjado'); exception when others then v_int := v_int + 1; end;
  begin perform definir_forma_cobranca(ass_1, 'pix'); exception when others then v_int := v_int + 1; end;
  begin insert into reposicoes (assinatura_id, cliente_id, entrega_origem_id, quantidade_ovos, descricao)
        values (ass_1, cli_1, ent_1, 1, 'forjado'); exception when others then v_int := v_int + 1; end;
  reset role;
  perform set_config('app.usuario_id', id_dono, true);
  if v_int = 6 then
    raise notice '  OK    F9.19 assinante não responde pedido, não gera cobrança, não roda rotina, não registra defeito nem grava reposição';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.19 só % de 6 recusados', v_int;
  end if;

  -- F9.20 ── assinante vê a própria reposição (RLS) ─────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_a, true);
  set local role app_usuario;
  select count(*) into v_int from reposicoes;
  reset role;
  perform set_config('app.usuario_id', 'ninguem', true);
  set local role app_usuario;
  select v_int * 10 + count(*)::int into v_int from reposicoes;
  reset role;
  perform set_config('app.usuario_id', id_dono, true);
  if v_int = 10 then
    raise notice '  OK    F9.20 o assinante vê a própria reposição; outra conta não vê nada';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.20 visibilidade = %', v_int;
  end if;

  -- F9.22 ── retorno no meio de um período já cobrado não cobra de novo ─────
  v_total := v_total + 1;
  perform reativar_assinatura(ass_1);                  -- estava pausada (F9.17)
  select id into fat_1 from faturas
   where assinatura_id = ass_1 and periodo_inicio is not null and status <> 'cancelada'
   order by periodo_fim desc limit 1;
  if (select proxima_cobranca from assinaturas where id = ass_1)
       = (select periodo_fim + 1 from faturas where id = fat_1) then
    raise notice '  OK    F9.22 retorno dentro de período já cobrado: próxima cobrança só depois do fim dele (%)',
      (select proxima_cobranca from assinaturas where id = ass_1);
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.22 proxima=% fim do período=%', (select proxima_cobranca from assinaturas where id = ass_1),
      (select periodo_fim from faturas where id = fat_1);
  end if;

  -- F9.21 ── cancelar: nada mais é cobrado ──────────────────────────────────
  v_total := v_total + 1;
  perform cancelar_assinatura(ass_1, 'sem fidelidade');
  begin
    perform gerar_cobranca(ass_1);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F9.21 gerou cobrança de assinatura cancelada';
  exception when sqlstate 'OV001' then
    if (select proxima_cobranca from assinaturas where id = ass_1) is null then
      raise notice '  OK    F9.21 cancelada a qualquer momento (sem fidelidade): próxima cobrança nula, nenhuma nova fatura';
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA F9.21 proxima_cobranca ainda preenchida';
    end if;
  end;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificações da Fase 9 falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações da Fase 9 passaram.', v_total;
end;
$$;

rollback;
