-- ═══════════════════════════════════════════════════════════════════════
-- Fase 1 — clientes completos: e-mail único, endereço e área de entrega.
--
--   pnpm --filter @ovo/database teste:fase1
--
-- Tudo dentro de uma transação que termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total  int := 0;
  v_falhas int := 0;
  v_bool   boolean;
  v_txt    text;
begin
  -- Cria uma faixa só para os testes de área (o banco real pode estar vazio).
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro)
  values ('30110000', '30190999', 'Centro-Sul (teste)');

  -- F1.1 ── e-mail duplicado (mesmo texto) é recusado ─────────────────────
  v_total := v_total + 1;
  insert into clientes (nome, email, origem) values ('Cliente Um', 'duplicado@exemplo.test', 'organico');
  begin
    insert into clientes (nome, email, origem) values ('Cliente Dois', 'duplicado@exemplo.test', 'organico');
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F1.1 e-mail repetido foi aceito';
  exception when unique_violation then
    raise notice '  OK    F1.1 e-mail repetido é recusado (%)', 'unique_violation';
  end;

  -- F1.2 ── ... e maiúscula/minúscula não escapa ─────────────────────────
  v_total := v_total + 1;
  begin
    insert into clientes (nome, email, origem) values ('Cliente Tres', 'DUPLICADO@Exemplo.TEST', 'organico');
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F1.2 e-mail com outra caixa foi aceito';
  exception when unique_violation then
    raise notice '  OK    F1.2 e-mail com outra caixa também é recusado';
  end;

  -- F1.3 ── vários clientes SEM e-mail continuam permitidos ──────────────
  v_total := v_total + 1;
  begin
    insert into clientes (nome, origem) values ('Sem e-mail A', 'organico');
    insert into clientes (nome, origem) values ('Sem e-mail B', 'organico');
    raise notice '  OK    F1.3 clientes sem e-mail podem existir em quantidade';
  exception when others then
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F1.3 cliente sem e-mail foi recusado: %', sqlerrm;
  end;

  -- F1.4 ── estado precisa ser sigla em maiúsculas ───────────────────────
  v_total := v_total + 1;
  begin
    insert into clientes (nome, estado, origem) values ('UF ruim', 'mg', 'organico');
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F1.4 estado em minúsculas foi aceito';
  exception when check_violation then
    raise notice '  OK    F1.4 estado fora do formato é recusado';
  end;

  -- F1.5 ── endereço completo é gravado ──────────────────────────────────
  v_total := v_total + 1;
  begin
    insert into clientes (nome, cep, endereco, numero, complemento, bairro, cidade, estado, origem)
    values ('Endereço completo', '30140000', 'Rua A', '10-B', 'ap 2', 'Centro-Sul', 'Belo Horizonte', 'MG', 'organico');
    raise notice '  OK    F1.5 endereço completo (número, bairro, cidade, estado) é gravado';
  exception when others then
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F1.5 %', sqlerrm;
  end;

  -- F1.6 ── CEP dentro da faixa marca a área; fora não marca ─────────────
  v_total := v_total + 1;
  select dentro_area_entrega into v_bool from clientes where nome = 'Endereço completo';
  if v_bool then
    raise notice '  OK    F1.6 CEP dentro da faixa marca dentro_area_entrega';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F1.6 CEP dentro da faixa NÃO foi marcado';
  end if;

  v_total := v_total + 1;
  update clientes set cep = '31000000' where nome = 'Endereço completo';
  select dentro_area_entrega into v_bool from clientes where nome = 'Endereço completo';
  if not v_bool then
    raise notice '  OK    F1.7 mudar o CEP para fora da faixa recalcula para "fora"';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F1.7 o CEP mudou e a área continuou "dentro"';
  end if;

  -- F1.8 ── cliente sem CEP nunca fica "dentro" ──────────────────────────
  v_total := v_total + 1;
  select dentro_area_entrega into v_bool from clientes where nome = 'Sem e-mail A';
  if not v_bool then
    raise notice '  OK    F1.8 cliente sem CEP fica fora da área (não se presume "dentro")';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F1.8 cliente sem CEP ficou dentro da área';
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificacoes da Fase 1 falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificacoes da Fase 1 passaram.', v_total;
end;
$$;

rollback;
