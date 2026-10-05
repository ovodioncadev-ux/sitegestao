-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 9 (correção) — reativar não cobra de novo dias já cobrados.
--
-- Achado no teste manual: pausa no meio de um período já pago + retorno
-- antes do fim desse período → a próxima cobrança começava no retorno e
-- cobrava de novo os dias restantes. Agora a cobrança recomeça no dia
-- seguinte ao fim do último período cobrado (não cancelado), ou no retorno,
-- o que vier depois.
--
-- Fica em aberto (decisão de negócio): crédito pelos dias de pausa dentro de
-- um período já pago. Hoje não há crédito automático.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

create or replace function inicio_proxima_cobranca(p_assinatura uuid, p_desde date)
returns date
language sql
stable
set search_path = public
as $$
  select greatest(
    p_desde,
    coalesce((select max(periodo_fim) + 1 from faturas
               where assinatura_id = p_assinatura and status <> 'cancelada' and periodo_fim is not null),
             p_desde)
  );
$$;

comment on function inicio_proxima_cobranca(uuid, date) is
  'Data em que a cobrança recomeça: p_desde, mas nunca antes do fim do último período já cobrado.';
revoke execute on function inicio_proxima_cobranca(uuid, date) from public;


create or replace function assinaturas_ciclo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'ativa' and new.proxima_cobranca is null then
      new.proxima_cobranca := new.data_inicio;
    end if;
    return new;
  end if;

  if new.status is distinct from old.status then
    if new.status in ('pausada', 'cancelada', 'encerrada') then
      new.proxima_cobranca := null;
    end if;
    if new.status <> 'pausada' then
      new.pausada_em := null;
      new.data_retorno_prevista := null;
    end if;
    if new.status = 'ativa' then
      new.proxima_cobranca := inicio_proxima_cobranca(new.id, coalesce(new.proxima_cobranca, hoje_sp()));
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function assinaturas_ciclo() from public;


-- Down Migration

create or replace function assinaturas_ciclo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'ativa' and new.proxima_cobranca is null then
      new.proxima_cobranca := new.data_inicio;
    end if;
    return new;
  end if;
  if new.status is distinct from old.status then
    if new.status in ('pausada', 'cancelada', 'encerrada') then new.proxima_cobranca := null; end if;
    if new.status <> 'pausada' then new.pausada_em := null; new.data_retorno_prevista := null; end if;
    if new.status = 'ativa' and new.proxima_cobranca is null then new.proxima_cobranca := hoje_sp(); end if;
  end if;
  return new;
end;
$$;
revoke execute on function assinaturas_ciclo() from public;
drop function if exists inicio_proxima_cobranca(uuid, date);
