-- ═══════════════════════════════════════════════════════════════════════
-- Etapa 1 — snapshot do cálculo da fatura, histórico de pausas, selo do plano.
--
--   pnpm --filter @ovo/database teste:etapa1
--
-- Tudo dentro de uma transação que termina em ROLLBACK.
-- (O teste do WhatsApp — número em um lugar só — é de código, não de banco:
--  apps/assinante/tests/whatsapp.test.ts.)
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total   int := 0;
  v_falhas  int := 0;
  v_hoje    date := hoje_sp();
  v_plano_q smallint;
  v_plano_s smallint;
  v_f       faturas%rowtype;
  v_antes   faturas%rowtype;
  v_depois  faturas%rowtype;
  v_id      uuid;
  v_txt     text;
  id_dono   text := 'teste-e1-dono';
  cli       uuid;
  cli_b     uuid;
  ass_b     uuid;
  v_int     int;
  ass       uuid;
  fat_1     uuid;
  fat_2     uuid;
  fat_3     uuid;
begin
  select id into v_plano_q from planos where frequencia = 'quinzenal';
  select id into v_plano_s from planos where frequencia = 'semanal';
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste E1');

  insert into "user" (id, name, email) values (id_dono, 'Dono E1', 'dono-e1@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;
  perform set_config('app.usuario_id', id_dono, true);

  insert into clientes (nome, email, cep, endereco, numero, bairro, origem)
    values ('Cliente E1', 'e1@exemplo.test', '30140000', 'Rua', '1', 'Savassi', 'organico') returning id into cli;
  ass := criar_assinatura(cli, v_plano_q);

  raise notice '═══ Fatura: snapshot do cálculo ═══';

  -- E1.1 ── fatura gerada nasce com o snapshot completo ───────────────────
  v_total := v_total + 1;
  fat_1 := gerar_cobranca(ass);
  select * into v_f from faturas where id = fat_1;
  if v_f.calculo_regra is not null
     and v_f.calculo_plano_id = v_plano_q
     and v_f.calculo_plano_frequencia = 'quinzenal'
     and v_f.calculo_plano_nome = 'Quinzenal'
     and v_f.calculo_entregas = entregas_do_calendario_no_periodo(v_f.periodo_inicio, v_f.periodo_fim, 'quinzenal')
     and v_f.calculo_regra = 'calendario-v1'
     and v_f.calculo_pentes_por_entrega = 1
     and v_f.calculo_duzias_por_entrega = 0
     and v_f.calculo_valor_pente_centavos = (select preco_pente_centavos from config_negocio)
     and v_f.calculo_valor_entrega_centavos = v_f.calculo_valor_pente_centavos
     and v_f.calculo_preco_plano_centavos = v_f.calculo_valor_pente_centavos * 2
     and v_f.calculo_valor_bruto_centavos = v_f.calculo_valor_pente_centavos * v_f.calculo_entregas
     and v_f.calculo_desconto_pct = 10
     and v_f.calculo_desconto_origem = 'primeiro_mes'
     and v_f.calculo_credito_centavos = 0
     and v_f.calculo_ajuste_centavos = 0
     and v_f.periodo_inicio is not null and v_f.periodo_fim is not null
     and v_f.calculo_valor_bruto_centavos - v_f.calculo_desconto_centavos = v_f.valor_centavos then
    raise notice '  OK    E1.1  fatura gerada guarda plano, preços, entregas, desconto, bruto e final (bruto %, desconto %, final %)',
      v_f.calculo_valor_bruto_centavos, v_f.calculo_desconto_centavos, v_f.valor_centavos;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E1.1  %', to_jsonb(v_f);
  end if;

  -- E1.2 ── o valor continua o mesmo de antes (mesma regra) ───────────────
  v_total := v_total + 1;
  if v_f.valor_centavos = round((v_f.calculo_valor_bruto_centavos)::numeric * 90 / 100)::integer
     and calcular_valor_fatura(ass) = (select valor_final_centavos from calcular_detalhe_fatura(ass)) then
    raise notice '  OK    E1.2  valor final = bruto − 10%% do 1º mês, igual à fórmula antiga; calcular_valor_fatura = detalhe';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E1.2';
  end if;

  -- E1.3 ── mudar preço do pente e o plano NÃO mexe na fatura antiga ───────
  v_total := v_total + 1;
  v_antes := v_f;
  update config_negocio set preco_pente_centavos = preco_pente_centavos + 500 where id = 1;
  update planos set nome = 'Quinzenal (renomeado)', entregas_por_mes = 3 where id = v_plano_q;
  select * into v_depois from faturas where id = fat_1;
  if to_jsonb(v_depois) - 'atualizado_em' = to_jsonb(v_antes) - 'atualizado_em' then
    raise notice '  OK    E1.3  preço do pente e o plano mudaram; a fatura antiga continua idêntica (valor %, plano %)',
      v_depois.valor_centavos, v_depois.calculo_plano_nome;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E1.3  antes=% depois=%', to_jsonb(v_antes), to_jsonb(v_depois);
  end if;

  -- E1.4 ── a fatura nova já usa os valores novos e registra isso ─────────
  v_total := v_total + 1;
  update assinaturas set proxima_cobranca = (select periodo_fim + 1 from faturas where id = fat_1) where id = ass;
  fat_2 := gerar_cobranca(ass);
  select * into v_f from faturas where id = fat_2;
  if v_f.calculo_plano_nome = 'Quinzenal (renomeado)'
     and v_f.calculo_entregas = 2   -- D10: quinzenal = sempre 2 no mês; entregas_por_mes não manda mais na fatura
     and v_f.calculo_valor_pente_centavos = v_antes.calculo_valor_pente_centavos + 500
     and v_f.calculo_desconto_centavos = 0
     and v_f.valor_centavos = v_f.calculo_valor_pente_centavos * 2 then
    raise notice '  OK    E1.4  a fatura seguinte registra o plano e o preço novos, sem desconto (não é a 1ª)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E1.4  %', to_jsonb(v_f);
  end if;

  -- E1.5 ── fatura avulsa com valor do dono: o ajuste fecha a conta ───────
  v_total := v_total + 1;
  fat_3 := criar_fatura(ass, v_hoje + 200, 5000, 'combinado');
  select * into v_f from faturas where id = fat_3;
  if v_f.valor_centavos = 5000
     and v_f.calculo_ajuste_centavos <> 0
     and v_f.periodo_inicio is null
     and v_f.calculo_valor_bruto_centavos - v_f.calculo_desconto_centavos - v_f.calculo_credito_centavos
         + v_f.calculo_ajuste_centavos = 5000 then
    raise notice '  OK    E1.5  valor informado à mão vira ajuste de % no snapshot; a conta fecha em 5000', v_f.calculo_ajuste_centavos;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E1.5  %', to_jsonb(v_f);
  end if;

  -- E1.6 ── o banco recusa snapshot incompleto ou que não fecha ───────────
  v_total := v_total + 1;
  begin
    update faturas set calculo_entregas = null where id = fat_1;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E1.6  aceitou snapshot incompleto';
  exception when check_violation then
    begin
      update faturas set calculo_desconto_centavos = calculo_desconto_centavos + 1 where id = fat_1;
      v_falhas := v_falhas + 1;
      raise notice '  FALHA E1.6  aceitou snapshot que não fecha a conta';
    exception when check_violation then
      raise notice '  OK    E1.6  snapshot incompleto ou que não fecha a conta é recusado pelo banco';
    end;
  end;

  -- E1.7 ── fatura antiga (sem snapshot) continua válida ─────────────────
  v_total := v_total + 1;
  insert into faturas (cliente_id, assinatura_id, valor_centavos, vencimento, status)
  values (cli, ass, 1234, v_hoje + 400, 'pendente') returning id into v_id;
  if (select calculo_regra from faturas where id = v_id) is null then
    raise notice '  OK    E1.7  fatura sem snapshot (como as anteriores à Etapa 1) continua aceita, com calculo_regra nula';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E1.7';
  end if;

  raise notice ' ';
  raise notice '═══ Pausas: histórico permanente ═══';

  -- E2.1 ── pausar abre uma linha ativa no histórico ─────────────────────
  v_total := v_total + 1;
  perform pausar_assinatura(ass, 'viagem', v_hoje + 20);
  if (select count(*) from pausas_assinatura where assinatura_id = ass) = 1
     and exists (select 1 from pausas_assinatura
                  where assinatura_id = ass and status = 'ativa' and inicio = v_hoje
                    and retorno_previsto = v_hoje + 20 and retorno_efetivo is null
                    and motivo = 'viagem' and criada_por = id_dono and cliente_id = cli) then
    raise notice '  OK    E2.1  pausar grava início, retorno previsto, motivo, quem pausou e status ativa';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E2.1  %', (select jsonb_agg(to_jsonb(p)) from pausas_assinatura p where assinatura_id = ass);
  end if;

  -- E2.2 ── os campos antigos da assinatura continuam funcionando ────────
  v_total := v_total + 1;
  if (select pausada_em from assinaturas where id = ass) = v_hoje
     and (select data_retorno_prevista from assinaturas where id = ass) = v_hoje + 20 then
    raise notice '  OK    E2.2  assinaturas.pausada_em / data_retorno_prevista seguem sendo preenchidos (compatibilidade)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E2.2';
  end if;

  -- E2.3 ── reativar encerra a pausa e o histórico permanece ─────────────
  v_total := v_total + 1;
  perform reativar_assinatura(ass);
  if (select pausada_em from assinaturas where id = ass) is null    -- o campo antigo é apagado…
     and exists (select 1 from pausas_assinatura                     -- …o histórico não
                  where assinatura_id = ass and status = 'encerrada'
                    and inicio = v_hoje and retorno_efetivo = v_hoje
                    and retorno_previsto = v_hoje + 20) then
    raise notice '  OK    E2.3  ao reativar, a pausa vira "encerrada" com retorno efetivo; os campos antigos são limpos e o histórico fica';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E2.3  %', (select jsonb_agg(to_jsonb(p)) from pausas_assinatura p where assinatura_id = ass);
  end if;

  -- E2.4 ── segunda pausa da mesma assinatura: as duas existem ───────────
  v_total := v_total + 1;
  perform pausar_assinatura(ass, 'reforma', null);
  if (select count(*) from pausas_assinatura where assinatura_id = ass) = 2
     and (select count(*) from pausas_assinatura where assinatura_id = ass and status = 'ativa') = 1
     and (select motivo from pausas_assinatura where assinatura_id = ass and status = 'encerrada') = 'viagem'
     and (select motivo from pausas_assinatura where assinatura_id = ass and status = 'ativa') = 'reforma' then
    raise notice '  OK    E2.4  a mesma assinatura tem 2 pausas ao longo do tempo; a nova não apagou nem alterou a antiga';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E2.4  %', (select jsonb_agg(to_jsonb(p)) from pausas_assinatura p where assinatura_id = ass);
  end if;

  -- E2.5 ── só uma pausa ativa por assinatura ────────────────────────────
  v_total := v_total + 1;
  begin
    insert into pausas_assinatura (assinatura_id, cliente_id, inicio) values (ass, cli, v_hoje + 1);
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E2.5  aceitou duas pausas ativas';
  exception when unique_violation or sqlstate 'OV001' then
    raise notice '  OK    E2.5  duas pausas ativas na mesma assinatura são recusadas';
  end;

  -- E2.6 ── pausas que se sobrepõem no tempo são recusadas ───────────────
  v_total := v_total + 1;
  begin
    insert into pausas_assinatura (assinatura_id, cliente_id, inicio, retorno_efetivo, status)
    values (ass, cli, v_hoje - 1, v_hoje + 2, 'encerrada');   -- atravessa a pausa ativa
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E2.6  aceitou pausa sobreposta';
  exception when sqlstate 'OV001' then
    raise notice '  OK    E2.6  pausa sobreposta a outra da mesma assinatura é recusada (%)', sqlerrm;
  end;

  -- E2.7 ── pausa ativa tem de estar sem retorno efetivo; datas coerentes ─
  v_total := v_total + 1;
  begin
    insert into pausas_assinatura (assinatura_id, cliente_id, inicio, retorno_previsto, retorno_efetivo, status)
    values (ass, cli, v_hoje - 400, v_hoje - 401, v_hoje - 399, 'encerrada');   -- previsto antes do início
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E2.7  aceitou retorno previsto antes do início';
  exception when check_violation then
    begin
      insert into pausas_assinatura (assinatura_id, cliente_id, inicio, retorno_efetivo, status)
      values (ass, cli, v_hoje - 400, v_hoje - 399, 'ativa');                   -- ativa com retorno efetivo
      v_falhas := v_falhas + 1;
      raise notice '  FALHA E2.7  aceitou pausa ativa com retorno efetivo';
    exception when check_violation then
      raise notice '  OK    E2.7  constraints recusam retorno previsto antes do início e "ativa" com retorno efetivo';
    end;
  end;

  -- E2.9 ── ajuste manual das datas na assinatura acompanha o histórico e nunca bloqueia
  v_total := v_total + 1;
  update assinaturas set pausada_em = v_hoje - 10, data_retorno_prevista = v_hoje where id = ass;
  if exists (select 1 from pausas_assinatura
              where assinatura_id = ass and status = 'ativa'
                and inicio = v_hoje - 10 and retorno_previsto = v_hoje) then
    raise notice '  OK    E2.9  corrigir pausada_em/retorno na assinatura atualiza a pausa ativa, sem erro';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E2.9  %', (select jsonb_agg(to_jsonb(p)) from pausas_assinatura p where assinatura_id = ass);
  end if;

  -- E2.10 ── RLS: cada assinante lê só as próprias pausas; ninguém escreve direto
  v_total := v_total + 1;
  insert into "user" (id, name, email, "emailVerified") values ('teste-e1-a', 'Ana E1', 'e1@exemplo.test', true);
  insert into "user" (id, name, email, "emailVerified") values ('teste-e1-b', 'Bruno E1', 'e1b@exemplo.test', true);
  update clientes set usuario_id = 'teste-e1-a' where id = cli;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem, usuario_id)
    values ('Cliente E1 B', 'e1b@exemplo.test', '30150000', 'Rua', '2', 'Savassi', 'organico', 'teste-e1-b')
    returning id into cli_b;
  ass_b := criar_assinatura(cli_b, v_plano_q);
  perform pausar_assinatura(ass_b, 'teste', null);

  perform set_config('app.usuario_id', 'teste-e1-a', true);
  set local role app_usuario;
  select (select count(*) from pausas_assinatura)::int * 100
       + (select count(*) from pausas_assinatura where cliente_id = cli_b)::int
    into v_int;
  begin
    insert into pausas_assinatura (assinatura_id, cliente_id, inicio) values (ass, cli, v_hoje + 900);
    v_int := -1;   -- escreveu: não devia
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  perform set_config('app.usuario_id', id_dono, true);
  if v_int = 200 then
    raise notice '  OK    E2.10 assinante A vê só as 2 pausas dele, nenhuma do B, e não consegue inserir pausa';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E2.10 resultado=%', v_int;
  end if;

  -- E2.8 ── a pausa não some com a assinatura apagada ─────────────────────
  v_total := v_total + 1;
  begin
    delete from assinaturas where id = ass;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E2.8  apagou assinatura com histórico';
  exception when restrict_violation or foreign_key_violation then
    raise notice '  OK    E2.8  assinatura com pausas não pode ser apagada (restrict, sem cascade)';
  end;

  raise notice ' ';
  raise notice '═══ Selo do plano ═══';

  -- E3.1 ── D13: só o semanal nasce com "Recomendado" ─────────────────────
  v_total := v_total + 1;
  select string_agg(frequencia || '=' || coalesce(selo, '-'), ',' order by intervalo_dias) into v_txt from planos_publicos();
  if (select selo from planos_publicos() where frequencia = 'semanal') = 'Recomendado'
     and (select count(*) from planos_publicos() where selo is not null) = 1 then
    raise notice '  OK    E3.1  planos_publicos(): só o semanal traz o selo "Recomendado" (%)', v_txt;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E3.1  %', v_txt;
  end if;

  -- E3.2 ── o selo é dado: trocar/retirar no banco muda o que a vitrine devolve
  v_total := v_total + 1;
  update planos set selo = null where frequencia = 'semanal';
  update planos set selo = 'Recomendado' where frequencia = 'mensal';
  select string_agg(frequencia || '=' || coalesce(selo, '-'), ',' order by intervalo_dias) into v_txt from planos_publicos();
  if (select selo from planos_publicos() where frequencia = 'semanal') is null
     and (select selo from planos_publicos() where frequencia = 'mensal') = 'Recomendado' then
    raise notice '  OK    E3.2  mudar planos.selo muda a vitrine, sem tocar em código (%)', v_txt;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E3.2  %', v_txt;
  end if;

  -- E3.3 ── selo vazio ou longo demais é recusado ─────────────────────────
  v_total := v_total + 1;
  begin
    update planos set selo = '' where frequencia = 'mensal';
    v_falhas := v_falhas + 1;
    raise notice '  FALHA E3.3  aceitou selo vazio';
  exception when check_violation then
    begin
      update planos set selo = repeat('x', 31) where frequencia = 'mensal';
      v_falhas := v_falhas + 1;
      raise notice '  FALHA E3.3  aceitou selo com 31 caracteres';
    exception when check_violation then
      raise notice '  OK    E3.3  selo vazio (use nulo) ou acima de 30 caracteres é recusado';
    end;
  end;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificações da Etapa 1 falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações da Etapa 1 passaram.', v_total;
end;
$$;

rollback;
