-- ═══════════════════════════════════════════════════════════════════════
-- Fase 9 (estabilidade) — achados da auditoria de 30/09/2026.
--
--   pnpm --filter @ovo/database teste:fase10
--
-- Tudo dentro de uma transação que termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- Falha "inesperada" (não OV001) só para os clientes marcados, criada dentro
-- da transação de teste e desfeita no ROLLBACK.
create function pg_temp.falha_inesperada() returns trigger language plpgsql as $$
begin
  if new.cliente_id::text = current_setting('teste.cliente_com_falha', true) then
    raise exception 'falha inesperada de teste';
  end if;
  return new;
end;
$$;

do $$
declare
  v_total   int := 0;
  v_falhas  int := 0;
  v_hoje    date := hoje_sp();
  v_plano_q smallint;
  v_json    jsonb;
  id_dono   text := 'teste10-dono';
  cli_a     uuid;
  cli_b     uuid;
  ass_a     uuid;
  ass_b     uuid;
  ent_b     uuid;
  rep_1     uuid;
begin
  select id into v_plano_q from planos where frequencia = 'quinzenal';
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste F10');

  insert into "user" (id, name, email) values (id_dono, 'Dono F10', 'dono-f10@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;
  perform set_config('app.usuario_id', id_dono, true);

  insert into clientes (nome, email, cep, endereco, numero, bairro, origem)
    values ('Cliente F10 A', 'f10a@exemplo.test', '30140000', 'Rua', '1', 'Savassi', 'organico') returning id into cli_a;
  insert into clientes (nome, email, cep, endereco, numero, bairro, origem)
    values ('Cliente F10 B', 'f10b@exemplo.test', '30140001', 'Rua', '2', 'Savassi', 'organico') returning id into cli_b;
  ass_a := criar_assinatura(cli_a, v_plano_q);
  ass_b := criar_assinatura(cli_b, v_plano_q);

  raise notice '═══ Rotina diária resistente a falha isolada ═══';

  -- F10.1 ── erro inesperado numa assinatura não derruba as outras ──────────
  v_total := v_total + 1;
  perform set_config('teste.cliente_com_falha', cli_a::text, true);
  create trigger falha_inesperada_tg before insert on faturas
    for each row execute function pg_temp.falha_inesperada();

  v_json := processar_rotina_diaria();
  if jsonb_array_length(v_json -> 'falhas') = 1
     and (v_json ->> 'cobrancas_geradas')::int = 1
     and exists (select 1 from faturas where assinatura_id = ass_b)
     and not exists (select 1 from faturas where assinatura_id = ass_a) then
    raise notice '  OK    F10.1  falha inesperada em A vira item de "falhas"; B foi cobrada normalmente';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F10.1  %', v_json;
  end if;

  drop trigger falha_inesperada_tg on faturas;

  -- F10.2 ── depois de corrigida a causa, a rotina cobra o que ficou para trás
  v_total := v_total + 1;
  v_json := processar_rotina_diaria();
  if (v_json ->> 'cobrancas_geradas')::int = 1
     and jsonb_array_length(v_json -> 'falhas') = 0
     and exists (select 1 from faturas where assinatura_id = ass_a) then
    raise notice '  OK    F10.2  na rodada seguinte A é cobrada e ninguém é cobrado duas vezes';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F10.2  %', v_json;
  end if;

  raise notice ' ';
  raise notice '═══ Defeito registrado uma vez só ═══';

  -- F10.3 ── duplo envio do mesmo defeito ───────────────────────────────────
  v_total := v_total + 1;
  select id into ent_b from entregas where assinatura_id = ass_b order by data_prevista limit 1;
  perform marcar_entrega(ent_b, 'entregue', null, null);
  rep_1 := registrar_defeito(ent_b, 4::smallint, '4 ovos trincados');
  begin
    perform registrar_defeito(ent_b, 4::smallint, '  4 OVOS trincados ');
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F10.3  aceitou o mesmo defeito duas vezes';
  exception when sqlstate 'OV001' then
    if (select count(*) from reposicoes where entrega_origem_id = ent_b) = 1 then
      raise notice '  OK    F10.3  segundo envio idêntico recusado: %', sqlerrm;
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA F10.3  há mais de uma reposição';
    end if;
  end;

  -- F10.4 ── outro defeito na mesma entrega continua permitido ──────────────
  v_total := v_total + 1;
  perform registrar_defeito(ent_b, 2::smallint, 'casca quebrada');
  if (select count(*) from reposicoes where entrega_origem_id = ent_b) = 2 then
    raise notice '  OK    F10.4  defeito diferente na mesma entrega é aceito';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F10.4';
  end if;

  -- F10.5 ── defeito cancelado pode ser registrado de novo ──────────────────
  v_total := v_total + 1;
  perform cancelar_reposicao(rep_1, 'engano');
  perform registrar_defeito(ent_b, 4::smallint, '4 ovos trincados');
  if (select count(*) from reposicoes where entrega_origem_id = ent_b and status <> 'cancelada') = 2 then
    raise notice '  OK    F10.5  depois de cancelar, o mesmo defeito pode ser registrado de novo';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F10.5';
  end if;

  raise notice ' ';
  raise notice '═══ Área de entrega recalculada pelo banco ═══';

  -- F10.6 ── faixa mexida direto no banco reavalia os clientes ──────────────
  v_total := v_total + 1;
  if (select dentro_area_entrega from clientes where id = cli_a) then
    update faixas_cep_atendidas set ativo = false where bairro = 'Teste F10';
    if not (select dentro_area_entrega from clientes where id = cli_a) then
      update faixas_cep_atendidas set ativo = true where bairro = 'Teste F10';
      if (select dentro_area_entrega from clientes where id = cli_a) then
        raise notice '  OK    F10.6  desativar/ativar a faixa por SQL muda dentro_area_entrega dos clientes sozinho';
      else
        v_falhas := v_falhas + 1;
        raise notice '  FALHA F10.6  reativar a faixa não voltou o cliente para dentro da área';
      end if;
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA F10.6  desativar a faixa não tirou o cliente da área';
    end if;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F10.6  cliente de teste já começou fora da área';
  end if;

  -- F10.7 ── remover a faixa também ────────────────────────────────────────
  v_total := v_total + 1;
  delete from faixas_cep_atendidas where bairro = 'Teste F10';
  if not (select dentro_area_entrega from clientes where id = cli_a) then
    raise notice '  OK    F10.7  remover a última faixa deixa os clientes fora da área';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F10.7';
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificações da Fase 9 (estabilidade) falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações de estabilidade da Fase 9 passaram.', v_total;
end;
$$;

rollback;
