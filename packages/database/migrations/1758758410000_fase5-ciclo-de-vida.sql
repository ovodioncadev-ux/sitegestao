-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 5 — pausar, cancelar e reativar assinaturas.
--
-- Nada se apaga. A assinatura continua, com a nova situação; as entregas e
-- faturas de antes continuam onde estavam. O que MUDA, por decisão:
--
--   • entregas PENDENTES viram `cancelada`  (DECISOES.md #3: ao voltar, o
--     calendário recomeça de hoje; não se tenta recuperar o que foi perdido);
--   • faturas PENDENTES viram `cancelada`   (dono, 25/09/2026). Faturas
--     atrasadas continuam cobráveis: são dívida, não cobrança futura;
--   • o status do CLIENTE acompanha a assinatura (dono, 25/09/2026):
--         pausar   → suspenso
--         cancelar → cancelado
--         reativar → ativo, se já houve fatura paga; senão cadastro_andamento
--
-- Reativar vale para assinatura pausada OU cancelada. Os valores de antes
-- (data e motivo do cancelamento) são zerados na linha, porque a linha
-- descreve a situação de agora; a auditoria (Fase 6) guarda o antes.
--
-- Cada função grava o motivo em `app.motivo`, para a auditoria registrar
-- "por quê" junto com "quem" e "quando".
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

-- Cancela entregas e faturas pendentes de uma assinatura, deixando o porquê.
create or replace function cancelar_pendencias_da_assinatura(p_assinatura uuid, p_porque text)
returns void
language plpgsql
set search_path = public
as $$
begin
  update entregas
     set status = 'cancelada',
         observacao = left(concat_ws(' | ', observacao, 'Cancelada: ' || p_porque), 500)
   where assinatura_id = p_assinatura and status = 'pendente';

  update faturas
     set status = 'cancelada',
         observacao = left(concat_ws(' | ', observacao, 'Cancelada: ' || p_porque), 500)
   where assinatura_id = p_assinatura and status = 'pendente';
end;
$$;

revoke execute on function cancelar_pendencias_da_assinatura(uuid, text) from public;


create or replace function pausar_assinatura(p_assinatura uuid, p_motivo text default null)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_ass assinaturas%rowtype;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' then
    raise exception 'Só assinaturas ativas podem ser pausadas.' using errcode = 'OV001';
  end if;

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);

  update assinaturas set status = 'pausada' where id = p_assinatura;
  perform cancelar_pendencias_da_assinatura(p_assinatura, 'assinatura pausada');
  update clientes set status = 'suspenso' where id = v_ass.cliente_id;

  perform set_config('app.motivo', '', true);
end;
$$;

revoke execute on function pausar_assinatura(uuid, text) from public;


create or replace function cancelar_assinatura(p_assinatura uuid, p_motivo text default null)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_ass assinaturas%rowtype;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status not in ('ativa', 'pausada') then
    raise exception 'Só assinaturas ativas ou pausadas podem ser canceladas.' using errcode = 'OV001';
  end if;

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);

  update assinaturas
     set status = 'cancelada',
         data_cancelamento = hoje_sp(),
         motivo_cancelamento = nullif(trim(p_motivo), '')
   where id = p_assinatura;
  perform cancelar_pendencias_da_assinatura(p_assinatura, 'assinatura cancelada');
  update clientes set status = 'cancelado' where id = v_ass.cliente_id;

  perform set_config('app.motivo', '', true);
end;
$$;

revoke execute on function cancelar_assinatura(uuid, text) from public;


-- Reativa uma assinatura pausada ou cancelada. O calendário recomeça em
-- p_retorno (padrão: hoje), ancorado na próxima quarta (DECISOES.md #3).
create or replace function reativar_assinatura(
  p_assinatura uuid,
  p_retorno    date default null,
  p_motivo     text default null
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_ass     assinaturas%rowtype;
  v_cliente clientes%rowtype;
  v_retorno date := coalesce(p_retorno, hoje_sp());
  v_primeira date;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status not in ('pausada', 'cancelada') then
    raise exception 'Só assinaturas pausadas ou canceladas podem ser reativadas.' using errcode = 'OV001';
  end if;
  if v_retorno < hoje_sp() then
    raise exception 'A data de retorno não pode estar no passado.' using errcode = 'OV001';
  end if;

  select * into v_cliente from clientes where id = v_ass.cliente_id for update;
  if not v_cliente.dentro_area_entrega then
    raise exception 'CEP fora da área de entrega.' using errcode = 'OV001';
  end if;

  if exists (
    select 1 from assinaturas
     where cliente_id = v_ass.cliente_id and id <> p_assinatura and status in ('ativa', 'pausada')
  ) then
    raise exception 'Este cliente já tem outra assinatura ativa ou pausada.' using errcode = 'OV001';
  end if;

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);

  update assinaturas
     set status = 'ativa', data_cancelamento = null, motivo_cancelamento = null
   where id = p_assinatura;

  -- Se essa data já tem entrega viva (ex.: a entrega foi adiantada antes da
  -- pausa), pula para o ciclo seguinte em vez de travar a reativação.
  v_primeira := data_primeira_entrega(v_retorno, v_ass.plano_id);
  while exists (
    select 1 from entregas
     where assinatura_id = p_assinatura and data_prevista = v_primeira
       and status in ('pendente', 'entregue')
  ) loop
    v_primeira := data_proxima_entrega(v_primeira, v_ass.plano_id);
  end loop;

  insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
  values (p_assinatura, v_ass.cliente_id, v_primeira,
          coalesce(v_cliente.pentes_padrao, 1), coalesce(v_cliente.duzias_padrao, 0));

  update clientes
     set status = case
                    when exists (select 1 from faturas where cliente_id = v_ass.cliente_id and status = 'paga')
                    then 'ativo'::status_cliente
                    else 'cadastro_andamento'::status_cliente
                  end
   where id = v_ass.cliente_id;

  perform set_config('app.motivo', '', true);
end;
$$;

revoke execute on function reativar_assinatura(uuid, date, text) from public;


-- Down Migration

drop function if exists reativar_assinatura(uuid, date, text);
drop function if exists cancelar_assinatura(uuid, text);
drop function if exists pausar_assinatura(uuid, text);
drop function if exists cancelar_pendencias_da_assinatura(uuid, text);
