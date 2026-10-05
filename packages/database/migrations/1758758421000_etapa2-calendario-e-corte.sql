-- ═══════════════════════════════════════════════════════════════════════════
-- Etapa 2 — calendário de entregas nas quartas (D10) e corte (D9).
--
-- D10 (DECISOES.md): as entregas ficam presas às quartas-feiras DO CALENDÁRIO,
-- e deixam de ser "última entrega + 7/15/30 dias":
--     semanal   = toda quarta-feira
--     quinzenal = 1ª e 3ª quarta-feira do mês
--     mensal    = 1ª quarta-feira do mês
-- (mês com 5 quartas: semanal entrega nas 5; quinzenal e mensal ignoram a 5ª.)
--
-- D9: vale o corte de `config_negocio` (dia_corte = segunda, hora_corte = 18:00,
-- horário de São Paulo). Uma entrega em uma quarta só é possível se o instante
-- de referência é ANTERIOR OU IGUAL ao corte daquela quarta; "depois dele"
-- (DECISOES.md) significa estritamente depois: segunda 18:00:00 ainda vale,
-- 18:00:01 já vai para a quarta seguinte.
--
-- O instante de referência é injetável (`p_agora timestamptz`), para ser
-- testável e para que a D8 (etapa posterior) passe o instante do PAGAMENTO.
-- Hoje, sem pagamento ligado à 1ª entrega, quem cria a assinatura usa `now()`.
--
-- NÃO reescreve nada existente: só as funções que calculam datas NOVAS mudam.
-- Entregas, assinaturas e faturas atuais ficam como estão. `quarta_mais_proxima`
-- e `proxima_quarta` continuam existindo (ainda cobertas por testes).
-- `planos.intervalo_dias` e `ancorar_em_quarta` deixam de comandar as datas;
-- as colunas permanecem (a vitrine ainda as lê).
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

-- ───────────────────────────────────────────────────────────────────────────
-- D10 — o calendário
-- ───────────────────────────────────────────────────────────────────────────

-- "É dia de entrega deste plano?" — a definição da regra, em um lugar só.
create or replace function data_de_entrega_do_plano(p_data date, p_frequencia frequencia_plano)
returns boolean
language sql
immutable
set search_path = public
as $$
  select extract(dow from p_data) = 3
     and case p_frequencia
           when 'semanal'   then true
           when 'quinzenal' then ((extract(day from p_data)::int - 1) / 7 + 1) in (1, 3)
           when 'mensal'    then ((extract(day from p_data)::int - 1) / 7 + 1) = 1
         end;
$$;

comment on function data_de_entrega_do_plano(date, frequencia_plano) is
  'D10: semanal = toda quarta; quinzenal = 1ª e 3ª quarta do mês; mensal = 1ª quarta do mês. A n-ésima quarta do mês é (dia − 1) / 7 + 1.';
revoke execute on function data_de_entrega_do_plano(date, frequencia_plano) from public;


-- Primeira data do calendário do plano a partir de p_desde, INCLUINDO p_desde.
create or replace function entrega_do_calendario_a_partir_de(p_desde date, p_frequencia frequencia_plano)
returns date
language sql
immutable
set search_path = public
as $$
  -- O maior intervalo do calendário é o do mensal (até 5 semanas); 45 dias cobre com folga.
  select d::date
    from generate_series(p_desde::timestamp, (p_desde + 45)::timestamp, interval '1 day') as d
   where data_de_entrega_do_plano(d::date, p_frequencia)
   order by d
   limit 1;
$$;

revoke execute on function entrega_do_calendario_a_partir_de(date, frequencia_plano) from public;


-- Próxima entrega do calendário, ESTRITAMENTE depois de p_base.
create or replace function proxima_entrega_do_calendario(p_base date, p_frequencia frequencia_plano)
returns date
language sql
immutable
set search_path = public
as $$
  select entrega_do_calendario_a_partir_de(p_base + 1, p_frequencia);
$$;

revoke execute on function proxima_entrega_do_calendario(date, frequencia_plano) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- D9 — o corte
-- ───────────────────────────────────────────────────────────────────────────

-- Menor quarta-feira entregável para quem fecha no instante p_agora: a primeira
-- quarta (a partir do dia de p_agora, em São Paulo) cujo corte ainda não passou.
-- Corte de uma quarta W = (dia_corte antes de W) às hora_corte, horário de SP.
create or replace function primeira_quarta_apos_corte(p_agora timestamptz)
returns date
language plpgsql
stable
set search_path = public
as $$
declare
  v_cfg    config_negocio%rowtype;
  v_local  timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_quarta date;
  v_atras  int;
  v_corte  timestamp;
begin
  if p_agora is null then
    raise exception 'Informe o instante de referência.' using errcode = 'OV001';
  end if;
  select * into v_cfg from config_negocio where id = 1;
  if not found then
    raise exception 'Configuração de negócio não encontrada.' using errcode = 'OV001';
  end if;

  v_quarta := proxima_quarta(v_local::date);
  -- Dias entre o dia do corte e a quarta (segunda → 2). Dia 3 (quarta): 0.
  v_atras := (3 - v_cfg.dia_corte + 7) % 7;

  for i in 0..2 loop
    v_corte := (v_quarta - v_atras) + v_cfg.hora_corte;
    -- "Depois do corte" é estritamente depois: exatamente no corte ainda vale.
    if v_local <= v_corte then
      return v_quarta;
    end if;
    v_quarta := v_quarta + 7;
  end loop;
  return v_quarta;
end;
$$;

comment on function primeira_quarta_apos_corte(timestamptz) is
  'D9: primeira quarta cujo corte (config_negocio: dia_corte/hora_corte, horário de São Paulo) não passou no instante dado. No corte exato ainda vale.';
revoke execute on function primeira_quarta_apos_corte(timestamptz) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- Datas de entrega usadas pelas operações (mesmos nomes de antes)
-- ───────────────────────────────────────────────────────────────────────────

-- 1ª entrega: aplica o corte ao instante de referência e cai no calendário do plano.
--   p_agora informado → é o instante (a D8 passará o do pagamento).
--   p_agora nulo      → p_inicio à 00:00 de São Paulo (data "como se fosse então").
--   Nunca antes do dia p_inicio.
drop function if exists data_primeira_entrega(date, smallint);

create or replace function data_primeira_entrega(
  p_inicio date,
  p_plano  smallint,
  p_agora  timestamptz default null
)
returns date
language plpgsql
stable
set search_path = public
as $$
declare
  v_freq   frequencia_plano;
  v_ref    timestamptz;
  v_quarta date;
begin
  select frequencia into v_freq from planos where id = p_plano;
  if not found then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;

  v_ref := greatest(
    coalesce(p_agora, '-infinity'::timestamptz),
    (p_inicio::timestamp at time zone 'America/Sao_Paulo')
  );
  v_quarta := primeira_quarta_apos_corte(v_ref);
  return entrega_do_calendario_a_partir_de(v_quarta, v_freq);
end;
$$;

comment on function data_primeira_entrega(date, smallint, timestamptz) is
  'D9 + D10: 1ª entrega = 1ª data do calendário do plano na 1ª quarta que o corte permite.';
revoke execute on function data_primeira_entrega(date, smallint, timestamptz) from public;


-- Entrega seguinte à de p_base: próxima data do calendário do plano (D10).
create or replace function data_proxima_entrega(p_base date, p_plano smallint)
returns date
language plpgsql
stable
set search_path = public
as $$
declare
  v_freq frequencia_plano;
begin
  select frequencia into v_freq from planos where id = p_plano;
  if not found then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;
  return proxima_entrega_do_calendario(p_base, v_freq);
end;
$$;

comment on function data_proxima_entrega(date, smallint) is
  'D10: próxima data do calendário do plano, estritamente depois de p_base. Não soma mais 7/15/30 dias.';
revoke execute on function data_proxima_entrega(date, smallint) from public;


-- criar_assinatura: igual à Fase 3, mais o instante de referência.
drop function if exists criar_assinatura(uuid, smallint, date);

create or replace function criar_assinatura(
  p_cliente uuid,
  p_plano   smallint,
  p_inicio  date default null,
  p_agora   timestamptz default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_cliente clientes%rowtype;
  -- Início: o informado; senão o dia (em São Paulo) do instante injetado; senão hoje.
  v_inicio  date := coalesce(
              p_inicio,
              case when p_agora is not null then (p_agora at time zone 'America/Sao_Paulo')::date end,
              hoje_sp());
  -- Sem instante informado: agora, salvo se o início foi dado no passado
  -- (então vale aquele dia, como antes).
  v_agora   timestamptz := coalesce(
              p_agora,
              case when p_inicio is null or p_inicio >= hoje_sp() then now() end);
  v_id      uuid;
  v_primeira date;
begin
  select * into v_cliente from clientes where id = p_cliente for update;
  if not found then
    raise exception 'Cliente não encontrado.' using errcode = 'OV001';
  end if;

  if not exists (select 1 from planos where id = p_plano and ativo) then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;

  if v_cliente.cep is null or v_cliente.endereco is null then
    raise exception 'Cliente sem endereço: preencha o CEP e o endereço antes de criar a assinatura.'
      using errcode = 'OV001';
  end if;

  if not v_cliente.dentro_area_entrega then
    raise exception 'CEP fora da área de entrega.' using errcode = 'OV001';
  end if;

  if exists (
    select 1 from assinaturas where cliente_id = p_cliente and status in ('ativa', 'pausada')
  ) then
    raise exception 'Este cliente já tem uma assinatura ativa ou pausada.' using errcode = 'OV001';
  end if;

  v_primeira := data_primeira_entrega(v_inicio, p_plano, v_agora);

  insert into assinaturas (cliente_id, plano_id, status, data_inicio, proxima_entrega)
  values (p_cliente, p_plano, 'ativa', v_inicio, v_primeira)
  returning id into v_id;

  insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
  values (v_id, p_cliente, v_primeira,
          coalesce(v_cliente.pentes_padrao, 1), coalesce(v_cliente.duzias_padrao, 0));

  update clientes set plano_id = p_plano where id = p_cliente and plano_id is distinct from p_plano;

  return v_id;
end;
$$;

revoke execute on function criar_assinatura(uuid, smallint, date, timestamptz) from public;


-- reativar_assinatura: igual à Fase 9, mais o instante de referência (D9 vale no retorno).
drop function if exists reativar_assinatura(uuid, date, text);

create or replace function reativar_assinatura(
  p_assinatura uuid,
  p_retorno    date default null,
  p_motivo     text default null,
  p_agora      timestamptz default null
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
     set status = 'ativa', data_cancelamento = null, motivo_cancelamento = null,
         proxima_cobranca = v_retorno
   where id = p_assinatura;

  v_primeira := data_primeira_entrega(v_retorno, v_ass.plano_id, coalesce(p_agora, now()));
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

revoke execute on function reativar_assinatura(uuid, date, text, timestamptz) from public;


-- Down Migration

drop function if exists reativar_assinatura(uuid, date, text, timestamptz);
drop function if exists criar_assinatura(uuid, smallint, date, timestamptz);
drop function if exists data_primeira_entrega(date, smallint, timestamptz);

-- Volta o cálculo por dias (Fase 2).
create or replace function data_primeira_entrega(p_inicio date, p_plano smallint)
returns date
language plpgsql
stable
set search_path = public
as $$
declare
  v_ancorar boolean;
begin
  select ancorar_em_quarta into v_ancorar from planos where id = p_plano;
  if not found then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;
  return case when v_ancorar then proxima_quarta(p_inicio) else p_inicio end;
end;
$$;
revoke execute on function data_primeira_entrega(date, smallint) from public;

create or replace function data_proxima_entrega(p_base date, p_plano smallint)
returns date
language plpgsql
stable
set search_path = public
as $$
declare
  v_plano planos%rowtype;
  v_data  date;
begin
  select * into v_plano from planos where id = p_plano;
  if not found then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;

  v_data := p_base + v_plano.intervalo_dias;
  if v_plano.ancorar_em_quarta then
    v_data := quarta_mais_proxima(v_data);
  end if;
  if v_data <= p_base then
    v_data := p_base + v_plano.intervalo_dias;
  end if;
  return v_data;
end;
$$;
revoke execute on function data_proxima_entrega(date, smallint) from public;

create or replace function criar_assinatura(
  p_cliente uuid,
  p_plano   smallint,
  p_inicio  date default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_cliente clientes%rowtype;
  v_inicio  date := coalesce(p_inicio, hoje_sp());
  v_id      uuid;
  v_primeira date;
begin
  select * into v_cliente from clientes where id = p_cliente for update;
  if not found then
    raise exception 'Cliente não encontrado.' using errcode = 'OV001';
  end if;
  if not exists (select 1 from planos where id = p_plano and ativo) then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;
  if v_cliente.cep is null or v_cliente.endereco is null then
    raise exception 'Cliente sem endereço: preencha o CEP e o endereço antes de criar a assinatura.'
      using errcode = 'OV001';
  end if;
  if not v_cliente.dentro_area_entrega then
    raise exception 'CEP fora da área de entrega.' using errcode = 'OV001';
  end if;
  if exists (
    select 1 from assinaturas where cliente_id = p_cliente and status in ('ativa', 'pausada')
  ) then
    raise exception 'Este cliente já tem uma assinatura ativa ou pausada.' using errcode = 'OV001';
  end if;

  v_primeira := data_primeira_entrega(v_inicio, p_plano);

  insert into assinaturas (cliente_id, plano_id, status, data_inicio, proxima_entrega)
  values (p_cliente, p_plano, 'ativa', v_inicio, v_primeira)
  returning id into v_id;

  insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
  values (v_id, p_cliente, v_primeira,
          coalesce(v_cliente.pentes_padrao, 1), coalesce(v_cliente.duzias_padrao, 0));

  update clientes set plano_id = p_plano where id = p_cliente and plano_id is distinct from p_plano;

  return v_id;
end;
$$;
revoke execute on function criar_assinatura(uuid, smallint, date) from public;

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
     set status = 'ativa', data_cancelamento = null, motivo_cancelamento = null,
         proxima_cobranca = v_retorno
   where id = p_assinatura;

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

drop function if exists primeira_quarta_apos_corte(timestamptz);
drop function if exists proxima_entrega_do_calendario(date, frequencia_plano);
drop function if exists entrega_do_calendario_a_partir_de(date, frequencia_plano);
drop function if exists data_de_entrega_do_plano(date, frequencia_plano);
