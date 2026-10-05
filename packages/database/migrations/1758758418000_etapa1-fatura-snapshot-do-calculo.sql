-- ═══════════════════════════════════════════════════════════════════════════
-- Etapa 1 (1/4) — a fatura guarda COMO o valor foi calculado.
--
-- Até aqui a fatura só guardava o resultado (`valor_centavos`). Plano, preço
-- do pente, quantidade de entregas e desconto eram lidos de novo, no estado
-- ATUAL do banco, por quem quisesse explicar o valor — e mudariam se o preço
-- do plano mudasse. Agora cada fatura nova nasce com um snapshot do cálculo,
-- gravado no mesmo INSERT que a cria.
--
--   valor_bruto − desconto − crédito + ajuste manual = valor_centavos
--
-- NÃO muda nenhuma regra de cobrança: `calcular_valor_fatura` devolve o mesmo
-- número de antes (a fórmula só passou a morar em `calcular_detalhe_fatura`,
-- que devolve também as parcelas). Vencimento, tolerância, período e
-- calendário ficam como estavam.
--
-- Faturas que já existiam ficam SEM snapshot (`calculo_regra` nula). O banco
-- não guardava o plano nem o preço da época: uma das faturas pagas, por
-- exemplo, tem valor de plano semanal numa assinatura hoje quinzenal, então
-- reconstruir a partir do estado atual seria inventar. Ver o relatório da
-- Etapa 1.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

alter table faturas
  add column calculo_regra                 text,
  add column calculado_em                  timestamptz,
  add column calculo_plano_id              smallint references planos (id) on delete restrict,
  add column calculo_plano_frequencia      frequencia_plano,
  add column calculo_plano_nome            text,
  add column calculo_preco_plano_centavos  integer,
  add column calculo_entregas              smallint,
  add column calculo_pentes_por_entrega    smallint,
  add column calculo_duzias_por_entrega    smallint,
  add column calculo_valor_pente_centavos  integer,
  add column calculo_valor_duzia_centavos  integer,
  add column calculo_valor_entrega_centavos integer,
  add column calculo_valor_bruto_centavos  integer,
  add column calculo_desconto_pct          numeric(5,2),
  add column calculo_desconto_centavos     integer,
  add column calculo_desconto_origem       text,
  add column calculo_credito_centavos      integer,
  add column calculo_ajuste_centavos       integer;

comment on column faturas.calculo_regra is
  'Versão da regra que produziu o valor. Nula = fatura anterior à Etapa 1, sem snapshot (não reconstruído de propósito).';
comment on column faturas.calculo_preco_plano_centavos is
  'Preço de vitrine do plano na data do cálculo: preço do pente × entregas por mês (1 pente por entrega), como em planos_publicos().';
comment on column faturas.calculo_entregas is
  'Entregas cobradas nesta fatura (planos.entregas_por_mes na data do cálculo).';
comment on column faturas.calculo_valor_entrega_centavos is
  'Valor por entrega: pentes × preço do pente + dúzias × preço da dúzia, congelado.';
comment on column faturas.calculo_valor_bruto_centavos is
  'Valor por entrega × entregas, antes de desconto, crédito e ajuste.';
comment on column faturas.calculo_desconto_origem is
  'Por que houve desconto (ex.: primeiro_mes). Nula quando não houve.';
comment on column faturas.calculo_credito_centavos is
  'Crédito em reais abatido. Zero até a etapa que implementa créditos (D3/D15c).';
comment on column faturas.calculo_ajuste_centavos is
  'Diferença entre o valor informado à mão pelo dono e o calculado. Zero quando o valor é o calculado.';

alter table faturas
  add constraint faturas_calculo_completo check (
    calculo_regra is null
    or (
      calculado_em is not null
      and calculo_plano_id is not null
      and calculo_plano_frequencia is not null
      and calculo_plano_nome is not null
      and calculo_preco_plano_centavos is not null
      and calculo_entregas is not null
      and calculo_pentes_por_entrega is not null
      and calculo_duzias_por_entrega is not null
      and calculo_valor_pente_centavos is not null
      and calculo_valor_duzia_centavos is not null
      and calculo_valor_entrega_centavos is not null
      and calculo_valor_bruto_centavos is not null
      and calculo_desconto_pct is not null
      and calculo_desconto_centavos is not null
      and calculo_credito_centavos is not null
      and calculo_ajuste_centavos is not null
    )
  ),
  add constraint faturas_calculo_nao_negativo check (
    calculo_regra is null
    or (calculo_desconto_centavos >= 0 and calculo_credito_centavos >= 0
        and calculo_valor_bruto_centavos >= 0 and calculo_entregas > 0)
  ),
  -- A conta fecha: quem lê a fatura consegue refazer o valor só com ela.
  add constraint faturas_calculo_fecha check (
    calculo_regra is null
    or (
      calculo_valor_bruto_centavos = calculo_valor_entrega_centavos * calculo_entregas
      and calculo_valor_bruto_centavos - calculo_desconto_centavos - calculo_credito_centavos
          + calculo_ajuste_centavos = valor_centavos
    )
  );

create index faturas_calculo_plano_idx on faturas (calculo_plano_id) where calculo_plano_id is not null;


-- ───────────────────────────────────────────────────────────────────────────
-- A fórmula (a mesma de antes) devolvendo TODAS as parcelas
-- ───────────────────────────────────────────────────────────────────────────
create or replace function calcular_detalhe_fatura(p_assinatura uuid)
returns table (
  regra                 text,
  plano_id              smallint,
  plano_frequencia      frequencia_plano,
  plano_nome            text,
  preco_plano_centavos  integer,
  entregas              smallint,
  pentes_por_entrega    smallint,
  duzias_por_entrega    smallint,
  valor_pente_centavos  integer,
  valor_duzia_centavos  integer,
  valor_entrega_centavos integer,
  valor_bruto_centavos  integer,
  desconto_pct          numeric,
  desconto_centavos     integer,
  desconto_origem       text,
  credito_centavos      integer,
  valor_final_centavos  integer
)
language plpgsql
stable
set search_path = public
as $$
declare
  v_ass    assinaturas%rowtype;
  v_plano  planos%rowtype;
  v_cli    clientes%rowtype;
  v_cfg    config_negocio%rowtype;
  v_pentes integer;
  v_duzias integer;
  v_entrega integer;
  v_bruto  integer;
  v_pct    numeric := 0;
  v_final  integer;
  v_origem text;
begin
  select * into v_ass from assinaturas where id = p_assinatura;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  select * into v_plano from planos where id = v_ass.plano_id;
  select * into v_cli   from clientes where id = v_ass.cliente_id;
  select * into v_cfg   from config_negocio where id = 1;

  -- Pente é o produto: sem quantidade padrão no cliente, conta 1.
  v_pentes  := coalesce(v_cli.pentes_padrao, 1);
  v_duzias  := coalesce(v_cli.duzias_padrao, 0);
  v_entrega := v_pentes * v_cfg.preco_pente_centavos + v_duzias * v_cfg.preco_duzia_centavos;
  v_bruto   := v_entrega * v_plano.entregas_por_mes;
  v_final   := v_bruto;

  -- Desconto do 1º mês: só na primeira fatura (não cancelada) do cliente.
  if v_cli.desconto_primeiro_mes_aplicavel
     and v_plano.desconto_primeiro_mes_pct > 0
     and not exists (select 1 from faturas where cliente_id = v_cli.id and status <> 'cancelada')
  then
    v_pct    := v_plano.desconto_primeiro_mes_pct;
    v_origem := 'primeiro_mes';
    v_final  := round(v_bruto::numeric * (100 - v_pct) / 100)::integer;
  end if;

  return query select
    'mensalidade-fixa-v1'::text,
    v_plano.id,
    v_plano.frequencia,
    v_plano.nome,
    (v_cfg.preco_pente_centavos * v_plano.entregas_por_mes)::integer,
    v_plano.entregas_por_mes,
    v_pentes::smallint,
    v_duzias::smallint,
    v_cfg.preco_pente_centavos,
    v_cfg.preco_duzia_centavos,
    v_entrega,
    v_bruto,
    v_pct,
    v_bruto - v_final,
    v_origem,
    0,
    v_final;
end;
$$;

comment on function calcular_detalhe_fatura(uuid) is
  'A conta da fatura com todas as parcelas (plano, preços, entregas, desconto). Fonte única da fórmula: calcular_valor_fatura devolve só o valor final desta função.';
revoke execute on function calcular_detalhe_fatura(uuid) from public;


-- Mesma assinatura, mesmo resultado de antes; agora sem fórmula própria.
create or replace function calcular_valor_fatura(p_assinatura uuid)
returns integer
language sql
stable
set search_path = public
as $$
  select valor_final_centavos from calcular_detalhe_fatura(p_assinatura);
$$;

revoke execute on function calcular_valor_fatura(uuid) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- Único ponto que grava fatura + snapshot. Chamado por criar_fatura e
-- gerar_cobranca; nunca por um papel de aplicação.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function inserir_fatura_com_snapshot(
  p_assinatura     uuid,
  p_vencimento     date,
  p_status         status_fatura,
  p_periodo_inicio date,
  p_periodo_fim    date,
  p_observacao     text,
  p_valor_informado integer default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass assinaturas%rowtype;
  v_d   record;
  v_valor integer;
  v_id  uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;

  select * into v_d from calcular_detalhe_fatura(p_assinatura);
  v_valor := coalesce(p_valor_informado, v_d.valor_final_centavos);

  if v_valor <= 0 then
    raise exception 'O valor da fatura precisa ser maior que zero.' using errcode = 'OV001';
  end if;

  insert into faturas (
    cliente_id, assinatura_id, valor_centavos, vencimento, status,
    periodo_inicio, periodo_fim, observacao,
    calculo_regra, calculado_em, calculo_plano_id, calculo_plano_frequencia, calculo_plano_nome,
    calculo_preco_plano_centavos, calculo_entregas, calculo_pentes_por_entrega, calculo_duzias_por_entrega,
    calculo_valor_pente_centavos, calculo_valor_duzia_centavos, calculo_valor_entrega_centavos,
    calculo_valor_bruto_centavos, calculo_desconto_pct, calculo_desconto_centavos, calculo_desconto_origem,
    calculo_credito_centavos, calculo_ajuste_centavos
  )
  values (
    v_ass.cliente_id, p_assinatura, v_valor, p_vencimento, p_status,
    p_periodo_inicio, p_periodo_fim, p_observacao,
    v_d.regra, now(), v_d.plano_id, v_d.plano_frequencia, v_d.plano_nome,
    v_d.preco_plano_centavos, v_d.entregas, v_d.pentes_por_entrega, v_d.duzias_por_entrega,
    v_d.valor_pente_centavos, v_d.valor_duzia_centavos, v_d.valor_entrega_centavos,
    v_d.valor_bruto_centavos, v_d.desconto_pct, v_d.desconto_centavos, v_d.desconto_origem,
    v_d.credito_centavos,
    v_valor - (v_d.valor_bruto_centavos - v_d.desconto_centavos - v_d.credito_centavos)
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer) is
  'Insere a fatura já com o snapshot do cálculo. Valor informado à mão vira "ajuste" no snapshot, para a conta continuar fechando.';
revoke execute on function inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer) from public;


-- criar_fatura: igual à Fase 4; só o INSERT passou a gravar o snapshot.
create or replace function criar_fatura(
  p_assinatura uuid,
  p_vencimento date,
  p_valor      integer default null,
  p_observacao text default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass   assinaturas%rowtype;
  v_valor integer;
  v_id    uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' then
    raise exception 'Só assinaturas ativas recebem fatura.' using errcode = 'OV001';
  end if;
  if p_vencimento is null then
    raise exception 'Informe o vencimento.' using errcode = 'OV001';
  end if;

  v_valor := coalesce(p_valor, calcular_valor_fatura(p_assinatura));
  if v_valor <= 0 then
    raise exception 'O valor da fatura precisa ser maior que zero.' using errcode = 'OV001';
  end if;

  v_id := inserir_fatura_com_snapshot(
    p_assinatura, p_vencimento,
    case when p_vencimento < hoje_sp() then 'atrasada'::status_fatura else 'pendente'::status_fatura end,
    null, null, nullif(trim(p_observacao), ''), p_valor
  );

  return v_id;
end;
$$;

revoke execute on function criar_fatura(uuid, date, integer, text) from public;


-- gerar_cobranca: igual à Fase 9; só o INSERT passou a gravar o snapshot.
create or replace function gerar_cobranca(p_assinatura uuid)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass    assinaturas%rowtype;
  v_inicio date;
  v_fim    date;
  v_id     uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' or v_ass.proxima_cobranca is null then
    raise exception 'Só assinaturas ativas têm próxima cobrança.' using errcode = 'OV001';
  end if;

  v_inicio := v_ass.proxima_cobranca;
  v_fim    := (v_inicio + interval '1 month')::date - 1;

  select id into v_id from faturas
   where assinatura_id = p_assinatura and periodo_inicio = v_inicio and status <> 'cancelada';

  if v_id is null then
    v_id := inserir_fatura_com_snapshot(
      p_assinatura, v_inicio,
      case when v_inicio < hoje_sp() then 'atrasada'::status_fatura else 'pendente'::status_fatura end,
      v_inicio, v_fim,
      case v_ass.forma_cobranca
        when 'cartao' then 'Cartão (recorrência): confirme o pagamento e registre aqui.'
        else 'PIX: cobrança mensal manual.'
      end,
      null
    );
  end if;

  update assinaturas set proxima_cobranca = v_fim + 1 where id = p_assinatura;
  return v_id;
end;
$$;

comment on function gerar_cobranca(uuid) is
  'Fatura do próximo período (1 mês) da assinatura ativa; avança proxima_cobranca. Idempotente por período.';
revoke execute on function gerar_cobranca(uuid) from public;


-- Down Migration

-- gerar_cobranca e criar_fatura voltam às versões anteriores (Fase 9 / Fase 4).
create or replace function gerar_cobranca(p_assinatura uuid)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass    assinaturas%rowtype;
  v_inicio date;
  v_fim    date;
  v_id     uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' or v_ass.proxima_cobranca is null then
    raise exception 'Só assinaturas ativas têm próxima cobrança.' using errcode = 'OV001';
  end if;

  v_inicio := v_ass.proxima_cobranca;
  v_fim    := (v_inicio + interval '1 month')::date - 1;

  select id into v_id from faturas
   where assinatura_id = p_assinatura and periodo_inicio = v_inicio and status <> 'cancelada';

  if v_id is null then
    insert into faturas (cliente_id, assinatura_id, valor_centavos, vencimento, status,
                         periodo_inicio, periodo_fim, observacao)
    values (v_ass.cliente_id, p_assinatura, calcular_valor_fatura(p_assinatura), v_inicio,
            case when v_inicio < hoje_sp() then 'atrasada'::status_fatura else 'pendente'::status_fatura end,
            v_inicio, v_fim,
            case v_ass.forma_cobranca
              when 'cartao' then 'Cartão (recorrência): confirme o pagamento e registre aqui.'
              else 'PIX: cobrança mensal manual.'
            end)
    returning id into v_id;
  end if;

  update assinaturas set proxima_cobranca = v_fim + 1 where id = p_assinatura;
  return v_id;
end;
$$;
revoke execute on function gerar_cobranca(uuid) from public;

create or replace function criar_fatura(
  p_assinatura uuid,
  p_vencimento date,
  p_valor      integer default null,
  p_observacao text default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass   assinaturas%rowtype;
  v_valor integer;
  v_id    uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' then
    raise exception 'Só assinaturas ativas recebem fatura.' using errcode = 'OV001';
  end if;
  if p_vencimento is null then
    raise exception 'Informe o vencimento.' using errcode = 'OV001';
  end if;

  v_valor := coalesce(p_valor, calcular_valor_fatura(p_assinatura));
  if v_valor <= 0 then
    raise exception 'O valor da fatura precisa ser maior que zero.' using errcode = 'OV001';
  end if;

  insert into faturas (cliente_id, assinatura_id, valor_centavos, vencimento, status, observacao)
  values (v_ass.cliente_id, p_assinatura, v_valor, p_vencimento,
          case when p_vencimento < hoje_sp() then 'atrasada'::status_fatura else 'pendente'::status_fatura end,
          nullif(trim(p_observacao), ''))
  returning id into v_id;

  return v_id;
end;
$$;
revoke execute on function criar_fatura(uuid, date, integer, text) from public;

drop function if exists inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer);

-- calcular_valor_fatura volta a ter a fórmula dentro dela (Fase 4).
create or replace function calcular_valor_fatura(p_assinatura uuid)
returns integer
language plpgsql
stable
set search_path = public
as $$
declare
  v_ass    assinaturas%rowtype;
  v_plano  planos%rowtype;
  v_cli    clientes%rowtype;
  v_cfg    config_negocio%rowtype;
  v_valor  numeric;
begin
  select * into v_ass from assinaturas where id = p_assinatura;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  select * into v_plano from planos where id = v_ass.plano_id;
  select * into v_cli   from clientes where id = v_ass.cliente_id;
  select * into v_cfg   from config_negocio where id = 1;

  v_valor := (coalesce(v_cli.pentes_padrao, 1) * v_cfg.preco_pente_centavos
              + coalesce(v_cli.duzias_padrao, 0) * v_cfg.preco_duzia_centavos)
             * v_plano.entregas_por_mes;

  if v_cli.desconto_primeiro_mes_aplicavel
     and v_plano.desconto_primeiro_mes_pct > 0
     and not exists (select 1 from faturas where cliente_id = v_cli.id and status <> 'cancelada')
  then
    v_valor := v_valor * (100 - v_plano.desconto_primeiro_mes_pct) / 100;
  end if;

  return round(v_valor)::integer;
end;
$$;
revoke execute on function calcular_valor_fatura(uuid) from public;

drop function if exists calcular_detalhe_fatura(uuid);

drop index if exists faturas_calculo_plano_idx;
alter table faturas
  drop constraint if exists faturas_calculo_fecha,
  drop constraint if exists faturas_calculo_nao_negativo,
  drop constraint if exists faturas_calculo_completo,
  drop column if exists calculo_ajuste_centavos,
  drop column if exists calculo_credito_centavos,
  drop column if exists calculo_desconto_origem,
  drop column if exists calculo_desconto_centavos,
  drop column if exists calculo_desconto_pct,
  drop column if exists calculo_valor_bruto_centavos,
  drop column if exists calculo_valor_entrega_centavos,
  drop column if exists calculo_valor_duzia_centavos,
  drop column if exists calculo_valor_pente_centavos,
  drop column if exists calculo_duzias_por_entrega,
  drop column if exists calculo_pentes_por_entrega,
  drop column if exists calculo_entregas,
  drop column if exists calculo_preco_plano_centavos,
  drop column if exists calculo_plano_nome,
  drop column if exists calculo_plano_frequencia,
  drop column if exists calculo_plano_id,
  drop column if exists calculado_em,
  drop column if exists calculo_regra;
