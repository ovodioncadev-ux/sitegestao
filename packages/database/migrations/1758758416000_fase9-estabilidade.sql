-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 9 (auditoria de estabilidade, 30/09/2026)
--
-- Achados rodando cenários adversariais contra as funções da Fase 9:
--
--   1. Duas rotinas ao mesmo tempo (agendador externo + botão do painel)
--      podiam cobrar um período a mais: as duas passavam pela conferência
--      "próxima cobrança <= hoje" e a segunda, depois de esperar o bloqueio
--      da linha, gerava a fatura do mês seguinte. Agora a rotina toma um
--      bloqueio de sessão (advisory lock) e a segunda espera a primeira
--      terminar — e então não tem mais nada a fazer.
--   2. Um erro inesperado (fora OV001/unicidade) numa única assinatura
--      derrubava a rotina inteira: as demais assinaturas ficavam sem cobrança
--      e sem reativação. Agora o erro daquela assinatura vira item de
--      "falhas" e a rotina segue.
--   3. registrar_defeito aceitava o mesmo defeito duas vezes (duplo envio do
--      formulário): duas reposições iguais para a mesma entrega.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

create or replace function processar_rotina_diaria()
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_hoje       date := hoje_sp();
  v_r          record;
  v_reativadas int := 0;
  v_cobrancas  int := 0;
  v_falhas     text[] := '{}';
  v_voltas     int;
  v_atrasadas  int;
begin
  -- Uma rotina por vez. O bloqueio morre com a transação.
  perform pg_advisory_xact_lock(hashtext('ovo.processar_rotina_diaria'));

  -- Retorno programado da pausa.
  for v_r in
    select id from assinaturas where status = 'pausada' and data_retorno_prevista <= v_hoje
  loop
    begin
      perform reativar_assinatura(v_r.id, v_hoje, 'Retorno programado da pausa');
      v_reativadas := v_reativadas + 1;
    exception when others then
      v_falhas := array_append(v_falhas, 'reativar ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  -- Cobranças vencidas até hoje (até 12 períodos atrasados por assinatura).
  for v_r in
    select id from assinaturas where status = 'ativa' and proxima_cobranca <= v_hoje
  loop
    v_voltas := 0;
    begin
      while v_voltas < 12
            and (select proxima_cobranca from assinaturas where id = v_r.id) <= v_hoje loop
        perform gerar_cobranca(v_r.id);
        v_cobrancas := v_cobrancas + 1;
        v_voltas := v_voltas + 1;
      end loop;
    exception when others then
      v_falhas := array_append(v_falhas, 'cobrar ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  v_atrasadas := marcar_faturas_atrasadas();

  return jsonb_build_object(
    'data', v_hoje,
    'reativadas', v_reativadas,
    'cobrancas_geradas', v_cobrancas,
    'faturas_atrasadas', v_atrasadas,
    'falhas', to_jsonb(v_falhas)
  );
end;
$$;

revoke execute on function processar_rotina_diaria() from public;


create or replace function registrar_defeito(
  p_entrega    uuid,
  p_quantidade smallint,
  p_descricao  text
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_e  entregas%rowtype;
  v_id uuid;
begin
  select * into v_e from entregas where id = p_entrega for update;
  if not found then
    raise exception 'Entrega não encontrada.' using errcode = 'OV001';
  end if;
  if v_e.status <> 'entregue' then
    raise exception 'Só dá para registrar defeito de uma entrega já feita.' using errcode = 'OV001';
  end if;
  if p_quantidade is null or p_quantidade < 1 then
    raise exception 'Informe quantos ovos vieram com defeito.' using errcode = 'OV001';
  end if;
  if char_length(trim(coalesce(p_descricao, ''))) < 3 then
    raise exception 'Descreva o defeito (pelo menos 3 letras).' using errcode = 'OV001';
  end if;

  -- O bloqueio da entrega (for update, acima) serializa dois envios ao mesmo tempo.
  if exists (
    select 1 from reposicoes
     where entrega_origem_id = p_entrega
       and status <> 'cancelada'
       and quantidade_ovos = p_quantidade
       and lower(descricao) = lower(trim(p_descricao))
  ) then
    raise exception 'Este defeito já foi registrado nesta entrega.' using errcode = 'OV001';
  end if;

  insert into reposicoes (assinatura_id, cliente_id, entrega_origem_id, entrega_reposicao_id,
                          quantidade_ovos, descricao)
  values (v_e.assinatura_id, v_e.cliente_id, p_entrega,
          proxima_entrega_pendente(v_e.assinatura_id, p_entrega),
          p_quantidade, trim(p_descricao))
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function registrar_defeito(uuid, smallint, text) from public;


-- Down Migration

create or replace function processar_rotina_diaria()
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_hoje       date := hoje_sp();
  v_r          record;
  v_reativadas int := 0;
  v_cobrancas  int := 0;
  v_falhas     text[] := '{}';
  v_voltas     int;
  v_atrasadas  int;
begin
  for v_r in
    select id from assinaturas where status = 'pausada' and data_retorno_prevista <= v_hoje
  loop
    begin
      perform reativar_assinatura(v_r.id, v_hoje, 'Retorno programado da pausa');
      v_reativadas := v_reativadas + 1;
    exception when sqlstate 'OV001' then
      v_falhas := array_append(v_falhas, 'reativar ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  for v_r in
    select id from assinaturas where status = 'ativa' and proxima_cobranca <= v_hoje
  loop
    v_voltas := 0;
    begin
      while v_voltas < 12
            and (select proxima_cobranca from assinaturas where id = v_r.id) <= v_hoje loop
        perform gerar_cobranca(v_r.id);
        v_cobrancas := v_cobrancas + 1;
        v_voltas := v_voltas + 1;
      end loop;
    exception when sqlstate 'OV001' or unique_violation then
      v_falhas := array_append(v_falhas, 'cobrar ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  v_atrasadas := marcar_faturas_atrasadas();

  return jsonb_build_object(
    'data', v_hoje,
    'reativadas', v_reativadas,
    'cobrancas_geradas', v_cobrancas,
    'faturas_atrasadas', v_atrasadas,
    'falhas', to_jsonb(v_falhas)
  );
end;
$$;
revoke execute on function processar_rotina_diaria() from public;

create or replace function registrar_defeito(
  p_entrega    uuid,
  p_quantidade smallint,
  p_descricao  text
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_e  entregas%rowtype;
  v_id uuid;
begin
  select * into v_e from entregas where id = p_entrega for update;
  if not found then
    raise exception 'Entrega não encontrada.' using errcode = 'OV001';
  end if;
  if v_e.status <> 'entregue' then
    raise exception 'Só dá para registrar defeito de uma entrega já feita.' using errcode = 'OV001';
  end if;
  if p_quantidade is null or p_quantidade < 1 then
    raise exception 'Informe quantos ovos vieram com defeito.' using errcode = 'OV001';
  end if;
  if char_length(trim(coalesce(p_descricao, ''))) < 3 then
    raise exception 'Descreva o defeito (pelo menos 3 letras).' using errcode = 'OV001';
  end if;

  insert into reposicoes (assinatura_id, cliente_id, entrega_origem_id, entrega_reposicao_id,
                          quantidade_ovos, descricao)
  values (v_e.assinatura_id, v_e.cliente_id, p_entrega,
          proxima_entrega_pendente(v_e.assinatura_id, p_entrega),
          p_quantidade, trim(p_descricao))
  returning id into v_id;

  return v_id;
end;
$$;
revoke execute on function registrar_defeito(uuid, smallint, text) from public;
