-- ═══════════════════════════════════════════════════════════════════════════
-- Bloco 9 — D1 (fatura do mês do calendário, vence dia 3) e D2 (inadimplência).
--
-- D1 (DECISOES.md): a fatura cobre o MÊS DO CALENDÁRIO, paga adiantada, e vence
-- no dia 3. Vira atrasada 5 dias depois (dia 8). A 1ª fatura vence no dia da
-- assinatura e cobre as entregas da 1ª entrega até o fim do mês dela.
-- Junto com a D1 vai a parte da D10 que faltava: o VALOR da fatura passa a ser
-- "entregas do calendário dentro do período × valor da entrega" (antes: valor
-- fixo do mês = entregas_por_mes × valor da entrega).
--
-- D2: as entregas param 20 dias depois do fim da tolerância (dia 28 para a
-- fatura do dia 3), voltam quando o pagamento é registrado, e assinatura
-- bloqueada não gera fatura nova.
--
-- Interpretações (a confirmar com o Fred/a Bruna; ver DECISOES.md):
--   • a fatura do mês seguinte é gerada `dias_antecedencia_fatura` (7) dias antes
--     do início do mês, para o cliente poder pagar até o dia 3;
--   • ao desbloquear, o período em que esteve bloqueado NÃO é cobrado, e a
--     cobrança recomeça no 1º dia do mês seguinte (as entregas retomadas no
--     resto do mês corrente não são cobradas);
--   • se a 1ª entrega atrasar por causa do pagamento (D8), a 1ª fatura continua
--     com as entregas projetadas no momento da assinatura.
--
-- Não reescreve fatura nem entrega existentes. Assinaturas que já têm
-- proxima_cobranca no meio do mês recebem UMA fatura de transição até o fim
-- daquele mês e, depois, entram no ciclo do calendário.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

alter table config_negocio
  add column dias_tolerancia_atraso          integer not null default 5   check (dias_tolerancia_atraso between 0 and 60),
  add column dias_bloqueio_apos_tolerancia   integer not null default 20  check (dias_bloqueio_apos_tolerancia between 0 and 365),
  add column dias_antecedencia_fatura        integer not null default 7   check (dias_antecedencia_fatura between 0 and 31);

comment on column config_negocio.dias_tolerancia_atraso is
  'D1: dias depois do vencimento em que a fatura ainda não é "atrasada" (vence dia 3 → atrasada no dia 8).';
comment on column config_negocio.dias_bloqueio_apos_tolerancia is
  'D2: dias depois do fim da tolerância em que as entregas param (dia 8 + 20 = dia 28).';
comment on column config_negocio.dias_antecedencia_fatura is
  'D1 (interpretação): quantos dias antes do início do mês a fatura do mês é gerada.';

alter table assinaturas add column bloqueada_desde date;
comment on column assinaturas.bloqueada_desde is
  'D2: entregas paradas por inadimplência desde esta data. Nula = não bloqueada. Só as funções bloquear_inadimplentes/reavaliar_bloqueio mexem.';
create index assinaturas_bloqueada_idx on assinaturas (bloqueada_desde) where bloqueada_desde is not null;


-- ───────────────────────────────────────────────────────────────────────────
-- Regras de data
-- ───────────────────────────────────────────────────────────────────────────

-- Fatura em aberto com este vencimento já é "atrasada" em p_hoje?
create or replace function fatura_atrasada_em(p_vencimento date, p_hoje date default null)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_vencimento + (select dias_tolerancia_atraso from config_negocio where id = 1)
         <= coalesce(p_hoje, hoje_sp());
$$;
comment on function fatura_atrasada_em(date, date) is
  'D1: atrasada = vencimento + tolerância (5 dias) já chegou. Vencimento dia 3 → atrasada no dia 8.';
revoke execute on function fatura_atrasada_em(date, date) from public;

-- Quantas entregas o calendário do plano tem em [p_ini, p_fim] (datas inclusas).
create or replace function entregas_do_calendario_no_periodo(p_ini date, p_fim date, p_frequencia frequencia_plano)
returns integer
language sql
immutable
set search_path = public
as $$
  select count(*)::integer
    from generate_series(p_ini::timestamp, p_fim::timestamp, interval '1 day') d
   where data_de_entrega_do_plano(d::date, p_frequencia);
$$;
comment on function entregas_do_calendario_no_periodo(date, date, frequencia_plano) is
  'D10: entregas previstas do plano entre duas datas (semanal 4 ou 5 por mês, quinzenal 2, mensal 1).';
revoke execute on function entregas_do_calendario_no_periodo(date, date, frequencia_plano) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- O cálculo da fatura aceita o número de entregas do período
-- ───────────────────────────────────────────────────────────────────────────
drop function if exists calcular_detalhe_fatura(uuid);

create function calcular_detalhe_fatura(p_assinatura uuid, p_entregas integer default null)
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
  v_ass     assinaturas%rowtype;
  v_plano   planos%rowtype;
  v_cli     clientes%rowtype;
  v_cfg     config_negocio%rowtype;
  v_pentes  integer;
  v_duzias  integer;
  v_entrega integer;
  v_n       integer;
  v_bruto   integer;
  v_pct     numeric := 0;
  v_final   integer;
  v_origem  text;
begin
  select * into v_ass from assinaturas where id = p_assinatura;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  select * into v_plano from planos where id = v_ass.plano_id;
  select * into v_cli   from clientes where id = v_ass.cliente_id;
  select * into v_cfg   from config_negocio where id = 1;

  -- Sem p_entregas: a conta antiga (mês fixo). Com: as entregas do período (D10).
  v_n       := coalesce(p_entregas, v_plano.entregas_por_mes);
  v_pentes  := coalesce(v_cli.pentes_padrao, 1);
  v_duzias  := coalesce(v_cli.duzias_padrao, 0);
  v_entrega := v_pentes * v_cfg.preco_pente_centavos + v_duzias * v_cfg.preco_duzia_centavos;
  v_bruto   := v_entrega * v_n;
  v_final   := v_bruto;

  if v_cli.desconto_primeiro_mes_aplicavel
     and v_plano.desconto_primeiro_mes_pct > 0
     and not exists (select 1 from faturas where cliente_id = v_cli.id and status <> 'cancelada')
  then
    v_pct    := v_plano.desconto_primeiro_mes_pct;
    v_origem := 'primeiro_mes';
    v_final  := round(v_bruto::numeric * (100 - v_pct) / 100)::integer;
  end if;

  return query select
    case when p_entregas is null then 'mensalidade-fixa-v1' else 'calendario-v1' end,
    v_plano.id,
    v_plano.frequencia,
    v_plano.nome,
    (v_cfg.preco_pente_centavos * v_plano.entregas_por_mes)::integer,
    v_n::smallint,
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
revoke execute on function calcular_detalhe_fatura(uuid, integer) from public;

drop function if exists inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer);

create function inserir_fatura_com_snapshot(
  p_assinatura      uuid,
  p_vencimento      date,
  p_status          status_fatura,
  p_periodo_inicio  date,
  p_periodo_fim     date,
  p_observacao      text,
  p_valor_informado integer default null,
  p_entregas        integer default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass   assinaturas%rowtype;
  v_d     record;
  v_valor integer;
  v_id    uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;

  select * into v_d from calcular_detalhe_fatura(p_assinatura, p_entregas);
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
revoke execute on function inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer, integer) from public;


-- ───────────────────────────────────────────────────────────────────────────
-- D1 — a cobrança do período
-- ───────────────────────────────────────────────────────────────────────────
create or replace function gerar_cobranca(p_assinatura uuid)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass      assinaturas%rowtype;
  v_hoje     date := hoje_sp();
  v_inicio   date;   -- onde a cobrança está (proxima_cobranca)
  v_ini      date;   -- 1º dia contado na fatura
  v_fim      date;
  v_n        integer;
  v_freq     frequencia_plano;
  v_primeira boolean;
  v_venc     date;
  v_id       uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' or v_ass.proxima_cobranca is null then
    raise exception 'Só assinaturas ativas têm próxima cobrança.' using errcode = 'OV001';
  end if;
  if v_ass.bloqueada_desde is not null then
    raise exception 'Assinatura bloqueada por inadimplência: não gera fatura nova até o pagamento.'
      using errcode = 'OV001';
  end if;

  -- D8: quem aguarda o 1º pagamento já tem a fatura certa em aberto (ver migration 427).
  if v_ass.aguardando_pagamento_desde is not null and exists (
       select 1 from faturas
        where assinatura_id = p_assinatura and status in ('pendente', 'atrasada')
     ) then
    raise exception 'Esta assinatura aguarda o pagamento da 1ª fatura, que já está em aberto: não há outra cobrança a gerar.'
      using errcode = 'OV001';
  end if;

  select frequencia into v_freq from planos where id = v_ass.plano_id;
  v_inicio   := v_ass.proxima_cobranca;
  v_primeira := not exists (select 1 from faturas where assinatura_id = p_assinatura and status <> 'cancelada');

  if v_primeira then
    -- 1ª fatura: da 1ª entrega (a real, se já existe; senão a projetada com o corte de agora) até o fim do mês dela.
    v_ini := coalesce(
      (select min(data_prevista) from entregas where assinatura_id = p_assinatura and status <> 'cancelada'),
      data_primeira_entrega(v_inicio, v_ass.plano_id, case when v_inicio >= v_hoje then now() end)
    );
  elsif extract(day from v_inicio) = 1 then
    v_ini := v_inicio;                            -- mês cheio do calendário
  else
    -- Transição (assinatura que já cobrava no meio do mês, ou volta de pausa): do 1º dia
    -- do calendário possível até o fim do mês.
    -- (período passado: sem o corte de agora; só o futuro depende dele)
    v_ini := greatest(v_inicio, data_primeira_entrega(v_inicio, v_ass.plano_id, case when v_inicio >= v_hoje then now() end));
  end if;

  v_fim := (date_trunc('month', v_ini) + interval '1 month')::date - 1;
  v_n   := entregas_do_calendario_no_periodo(v_ini, v_fim, v_freq);
  if v_n = 0 then
    -- Nenhuma entrega no que sobra do mês (ex.: mensal já entregue): cobra o mês seguinte inteiro.
    v_ini := v_fim + 1;
    v_fim := (date_trunc('month', v_ini) + interval '1 month')::date - 1;
    v_n   := entregas_do_calendario_no_periodo(v_ini, v_fim, v_freq);
  end if;

  -- Mês cheio: dia 3. 1ª fatura e transição: no dia em que a cobrança começa (proxima_cobranca);
  -- se esse dia já passou, a fatura nasce vencida (e atrasada, passada a tolerância).
  v_venc := case when not v_primeira and extract(day from v_ini) = 1
                 then v_ini + 2
                 else v_inicio end;

  select id into v_id from faturas
   where assinatura_id = p_assinatura and periodo_inicio = v_ini and status <> 'cancelada';

  if v_id is null then
    v_id := inserir_fatura_com_snapshot(
      p_assinatura, v_venc,
      case when fatura_atrasada_em(v_venc, v_hoje) then 'atrasada'::status_fatura else 'pendente'::status_fatura end,
      v_ini, v_fim,
      case v_ass.forma_cobranca
        when 'cartao' then 'Cartão (recorrência): confirme o pagamento e registre aqui.'
        else 'PIX: cobrança mensal manual.'
      end,
      null,
      v_n
    );
  end if;

  update assinaturas set proxima_cobranca = v_fim + 1 where id = p_assinatura;
  return v_id;
end;
$$;
revoke execute on function gerar_cobranca(uuid) from public;


-- Fatura manual do painel: mesma regra de "atrasada".
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
    case when fatura_atrasada_em(p_vencimento) then 'atrasada'::status_fatura else 'pendente'::status_fatura end,
    null, null, nullif(trim(p_observacao), ''), p_valor
  );

  return v_id;
end;
$$;
revoke execute on function criar_fatura(uuid, date, integer, text) from public;


create or replace function marcar_faturas_atrasadas()
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_n integer;
begin
  update faturas set status = 'atrasada'
   where status = 'pendente' and fatura_atrasada_em(vencimento);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke execute on function marcar_faturas_atrasadas() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- D2 — bloqueio por inadimplência
-- ───────────────────────────────────────────────────────────────────────────

-- Ninguém cria entrega para assinatura bloqueada (cobre agendar_entrega, a entrega seguinte
-- depois de "entregue", reagendamento...). A mensagem aparece como erro ao operador.
create or replace function entregas_nao_para_bloqueada()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (select 1 from assinaturas where id = new.assinatura_id and bloqueada_desde is not null) then
    raise exception 'Assinatura bloqueada por inadimplência: as entregas voltam quando o pagamento for registrado.'
      using errcode = 'OV001';
  end if;
  return new;
end;
$$;

create trigger entregas_nao_para_bloqueada_tg
  before insert on entregas
  for each row execute function entregas_nao_para_bloqueada();

-- Bloqueia quem tem fatura em aberto passada da tolerância + dias de bloqueio.
create or replace function bloquear_inadimplentes()
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_hoje date := hoje_sp();
  v_cfg  config_negocio%rowtype;
  v_a    record;
  v_n    integer := 0;
begin
  select * into v_cfg from config_negocio where id = 1;

  for v_a in
    select a.id
      from assinaturas a
     where a.status = 'ativa' and a.bloqueada_desde is null and a.aguardando_pagamento_desde is null
       and exists (
         select 1 from faturas f
          where f.assinatura_id = a.id and f.status in ('pendente', 'atrasada')
            and f.vencimento + v_cfg.dias_tolerancia_atraso + v_cfg.dias_bloqueio_apos_tolerancia <= v_hoje
       )
     for update of a
  loop
    perform set_config('app.motivo', 'Inadimplência: entregas paradas', true);
    update assinaturas set bloqueada_desde = v_hoje where id = v_a.id;
    update entregas set status = 'cancelada', observacao = 'Entrega cancelada: assinatura bloqueada por inadimplência'
     where assinatura_id = v_a.id and status = 'pendente';
    perform set_config('app.motivo', '', true);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
comment on function bloquear_inadimplentes() is
  'D2: para as entregas (cancela as pendentes) de quem tem fatura em aberto além de vencimento + tolerância + dias de bloqueio.';
revoke execute on function bloquear_inadimplentes() from public;

-- Depois de um pagamento (ou cancelamento de fatura): se nada mais justifica o bloqueio,
-- libera e agenda a próxima entrega do calendário (com o corte, D9).
create or replace function reavaliar_bloqueio(p_assinatura uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ass     assinaturas%rowtype;
  v_cfg     config_negocio%rowtype;
  v_cli     clientes%rowtype;
  v_primeira date;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found or v_ass.bloqueada_desde is null then
    return false;
  end if;

  select * into v_cfg from config_negocio where id = 1;
  if exists (
    select 1 from faturas f
     where f.assinatura_id = p_assinatura and f.status in ('pendente', 'atrasada')
       and f.vencimento + v_cfg.dias_tolerancia_atraso + v_cfg.dias_bloqueio_apos_tolerancia <= hoje_sp()
  ) then
    return false;   -- ainda há fatura que justifica o bloqueio
  end if;

  perform set_config('app.motivo', 'Pagamento registrado: entregas liberadas', true);
  update assinaturas
     set bloqueada_desde = null,
         -- o período bloqueado não é cobrado: recomeça no 1º dia do mês seguinte
         proxima_cobranca = greatest(
           coalesce(proxima_cobranca, hoje_sp()),
           (date_trunc('month', hoje_sp()) + interval '1 month')::date)
   where id = p_assinatura;

  if v_ass.status = 'ativa' and not exists (
       select 1 from entregas where assinatura_id = p_assinatura and status = 'pendente') then
    select * into v_cli from clientes where id = v_ass.cliente_id;
    v_primeira := data_primeira_entrega(hoje_sp(), v_ass.plano_id, now());
    while exists (
      select 1 from entregas
       where assinatura_id = p_assinatura and data_prevista = v_primeira and status in ('pendente', 'entregue')
    ) loop
      v_primeira := data_proxima_entrega(v_primeira, v_ass.plano_id);
    end loop;
    insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
    values (p_assinatura, v_ass.cliente_id, v_primeira,
            coalesce(v_cli.pentes_padrao, 1), coalesce(v_cli.duzias_padrao, 0));
  end if;
  perform set_config('app.motivo', '', true);
  return true;
end;
$$;
comment on function reavaliar_bloqueio(uuid) is
  'D2: libera a assinatura bloqueada quando nenhuma fatura em aberto justifica mais o bloqueio e agenda a próxima entrega.';
revoke execute on function reavaliar_bloqueio(uuid) from public;

create or replace function faturas_reavaliar_bloqueio()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assinatura_id is not null then
    perform reavaliar_bloqueio(new.assinatura_id);
  end if;
  return null;
end;
$$;
revoke execute on function faturas_reavaliar_bloqueio() from public;

create trigger faturas_reavaliar_bloqueio_tg
  after update of status on faturas
  for each row
  when (old.status in ('pendente', 'atrasada') and new.status in ('paga', 'cancelada'))
  execute function faturas_reavaliar_bloqueio();


-- ───────────────────────────────────────────────────────────────────────────
-- A rotina diária: antecedência da fatura e bloqueio
-- ───────────────────────────────────────────────────────────────────────────
create or replace function processar_rotina_diaria()
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_hoje       date := hoje_sp();
  v_cfg        config_negocio%rowtype;
  v_r          record;
  v_reativadas int := 0;
  v_cobrancas  int := 0;
  v_canceladas int := 0;
  v_bloqueadas int := 0;
  v_falhas     text[] := '{}';
  v_voltas     int;
  v_atrasadas  int;
begin
  perform pg_advisory_xact_lock(hashtext('ovo.processar_rotina_diaria'));
  select * into v_cfg from config_negocio where id = 1;

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

  for v_r in
    select a.id, a.cliente_id
      from assinaturas a
     where a.status = 'ativa' and a.aguardando_pagamento_desde is not null
       and a.aguardando_pagamento_desde + v_cfg.dias_para_pagar_1a_fatura <= v_hoje
  loop
    begin
      perform cancelar_assinatura(v_r.id, 'Primeira fatura não paga no prazo');
      update clientes set status = 'cadastro_andamento' where id = v_r.cliente_id and status = 'cancelado';
      v_canceladas := v_canceladas + 1;
    exception when others then
      v_falhas := array_append(v_falhas, 'cancelar sem pagamento ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  -- Faturas do período: geradas com antecedência (a do mês seguinte sai dias_antecedencia_fatura dias
  -- antes), até 12 períodos por assinatura. Bloqueada não gera fatura nova (D2).
  for v_r in
    select id from assinaturas
     where status = 'ativa' and aguardando_pagamento_desde is null and bloqueada_desde is null
       and proxima_cobranca <= v_hoje + v_cfg.dias_antecedencia_fatura
  loop
    v_voltas := 0;
    begin
      while v_voltas < 12
            and (select proxima_cobranca <= v_hoje + v_cfg.dias_antecedencia_fatura
                   from assinaturas where id = v_r.id) loop
        perform gerar_cobranca(v_r.id);
        v_cobrancas := v_cobrancas + 1;
        v_voltas := v_voltas + 1;
      end loop;
    exception when others then
      v_falhas := array_append(v_falhas, 'cobrar ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  v_atrasadas := marcar_faturas_atrasadas();

  begin
    v_bloqueadas := bloquear_inadimplentes();
  exception when others then
    v_falhas := array_append(v_falhas, 'bloquear: ' || sqlerrm);
  end;

  return jsonb_build_object(
    'data', v_hoje,
    'reativadas', v_reativadas,
    'cobrancas_geradas', v_cobrancas,
    'canceladas_sem_pagamento', v_canceladas,
    'faturas_atrasadas', v_atrasadas,
    'assinaturas_bloqueadas', v_bloqueadas,
    'falhas', to_jsonb(v_falhas)
  );
end;
$$;
revoke execute on function processar_rotina_diaria() from public;

-- D8 continua liberando a 1ª entrega ao pagar a 1ª fatura (que agora começa na 1ª entrega).
create or replace function registrar_pagamento(
  p_fatura     uuid,
  p_data       date,
  p_metodo     metodo_pagamento,
  p_observacao text default null
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_f faturas%rowtype;
begin
  select * into v_f from faturas where id = p_fatura for update;
  if not found then
    raise exception 'Fatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_f.status = 'paga' then
    raise exception 'Esta fatura já está paga.' using errcode = 'OV001';
  end if;
  if v_f.status = 'cancelada' then
    raise exception 'Fatura cancelada não pode ser paga.' using errcode = 'OV001';
  end if;
  if p_data is null then
    raise exception 'Informe a data do pagamento.' using errcode = 'OV001';
  end if;
  if p_data > hoje_sp() then
    raise exception 'A data do pagamento não pode estar no futuro.' using errcode = 'OV001';
  end if;
  if p_metodo is null then
    raise exception 'Informe o método de pagamento.' using errcode = 'OV001';
  end if;

  update faturas
     set status = 'paga', data_pagamento = p_data, metodo = p_metodo,
         observacao = coalesce(nullif(trim(p_observacao), ''), observacao)
   where id = p_fatura;

  -- A primeira fatura paga é a entrada do cliente na base ativa.
  update clientes set status = 'ativo'
   where id = v_f.cliente_id and status = 'cadastro_andamento';

  -- D8: o pagamento da 1ª fatura libera a 1ª entrega. O instante do corte (D9) é o
  -- da CONFIRMAÇÃO (agora), não uma data digitada.
  if v_f.assinatura_id is not null and exists (
       select 1 from assinaturas a
        where a.id = v_f.assinatura_id and a.status = 'ativa'
          and a.aguardando_pagamento_desde is not null
          -- a 1ª fatura da assinatura (D1: o período dela começa na 1ª entrega, não em data_inicio)
          and p_fatura = (select f.id from faturas f
                           where f.assinatura_id = a.id and f.status <> 'cancelada'
                           order by f.criado_em, f.periodo_inicio limit 1)
     ) then
    perform liberar_primeira_entrega(v_f.assinatura_id, now());
  end if;
end;
$$;

-- Down Migration

drop trigger if exists faturas_reavaliar_bloqueio_tg on faturas;
drop function if exists faturas_reavaliar_bloqueio();
drop trigger if exists entregas_nao_para_bloqueada_tg on entregas;
drop function if exists entregas_nao_para_bloqueada();

-- Volta às funções da migration 427 / Etapa 1 / Fase 4.
drop function if exists processar_rotina_diaria();
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
  v_canceladas int := 0;
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

  -- D8: quem assinou e não pagou a 1ª fatura no prazo é cancelado (e a fatura, cancelada junto).
  -- O cliente volta a "cadastro em andamento" (nunca pagou) e pode assinar de novo.
  for v_r in
    select a.id, a.cliente_id
      from assinaturas a
      cross join config_negocio c
     where c.id = 1 and a.status = 'ativa' and a.aguardando_pagamento_desde is not null
       and a.aguardando_pagamento_desde + c.dias_para_pagar_1a_fatura <= v_hoje
  loop
    begin
      perform cancelar_assinatura(v_r.id, 'Primeira fatura não paga no prazo');
      update clientes set status = 'cadastro_andamento' where id = v_r.cliente_id and status = 'cancelado';
      v_canceladas := v_canceladas + 1;
    exception when others then
      v_falhas := array_append(v_falhas, 'cancelar sem pagamento ' || v_r.id || ': ' || sqlerrm);
    end;
  end loop;

  -- Cobranças vencidas até hoje (até 12 períodos atrasados por assinatura).
  for v_r in
    select id from assinaturas
     where status = 'ativa' and proxima_cobranca <= v_hoje and aguardando_pagamento_desde is null
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
    'canceladas_sem_pagamento', v_canceladas,
    'faturas_atrasadas', v_atrasadas,
    'falhas', to_jsonb(v_falhas)
  );
end;
$$;

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

  -- D8: quem aguarda o 1º pagamento já tem a fatura certa em aberto. Gerar outra (pelo botão
  -- "Gerar cobrança" do painel) só empilharia cobrança de uma assinatura que nem recebeu entrega.
  -- A 1ª chamada (de criar_assinatura) passa: ainda não há fatura.
  if v_ass.aguardando_pagamento_desde is not null and exists (
       select 1 from faturas
        where assinatura_id = p_assinatura and status in ('pendente', 'atrasada')
     ) then
    raise exception 'Esta assinatura aguarda o pagamento da 1ª fatura, que já está em aberto: não há outra cobrança a gerar.'
      using errcode = 'OV001';
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

create or replace function marcar_faturas_atrasadas()
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_n integer;
begin
  update faturas set status = 'atrasada'
   where status = 'pendente' and vencimento < hoje_sp();
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

drop function if exists inserir_fatura_com_snapshot(uuid, date, status_fatura, date, date, text, integer, integer);
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

drop function if exists calcular_detalhe_fatura(uuid, integer);
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

drop function if exists reavaliar_bloqueio(uuid);
drop function if exists bloquear_inadimplentes();
drop function if exists entregas_do_calendario_no_periodo(date, date, frequencia_plano);
drop function if exists fatura_atrasada_em(date, date);

drop index if exists assinaturas_bloqueada_idx;
alter table assinaturas drop column if exists bloqueada_desde;
alter table config_negocio
  drop column if exists dias_tolerancia_atraso,
  drop column if exists dias_bloqueio_apos_tolerancia,
  drop column if exists dias_antecedencia_fatura;

create or replace function registrar_pagamento(
  p_fatura     uuid,
  p_data       date,
  p_metodo     metodo_pagamento,
  p_observacao text default null
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_f faturas%rowtype;
begin
  select * into v_f from faturas where id = p_fatura for update;
  if not found then
    raise exception 'Fatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_f.status = 'paga' then
    raise exception 'Esta fatura já está paga.' using errcode = 'OV001';
  end if;
  if v_f.status = 'cancelada' then
    raise exception 'Fatura cancelada não pode ser paga.' using errcode = 'OV001';
  end if;
  if p_data is null then
    raise exception 'Informe a data do pagamento.' using errcode = 'OV001';
  end if;
  if p_data > hoje_sp() then
    raise exception 'A data do pagamento não pode estar no futuro.' using errcode = 'OV001';
  end if;
  if p_metodo is null then
    raise exception 'Informe o método de pagamento.' using errcode = 'OV001';
  end if;

  update faturas
     set status = 'paga', data_pagamento = p_data, metodo = p_metodo,
         observacao = coalesce(nullif(trim(p_observacao), ''), observacao)
   where id = p_fatura;

  -- A primeira fatura paga é a entrada do cliente na base ativa.
  update clientes set status = 'ativo'
   where id = v_f.cliente_id and status = 'cadastro_andamento';

  -- D8: o pagamento da 1ª fatura libera a 1ª entrega. O instante do corte (D9) é o
  -- da CONFIRMAÇÃO (agora), não uma data digitada.
  if v_f.assinatura_id is not null and exists (
       select 1 from assinaturas a
        where a.id = v_f.assinatura_id and a.status = 'ativa'
          and a.aguardando_pagamento_desde is not null
          and a.data_inicio = v_f.periodo_inicio
     ) then
    perform liberar_primeira_entrega(v_f.assinatura_id, now());
  end if;
end;
$$;
