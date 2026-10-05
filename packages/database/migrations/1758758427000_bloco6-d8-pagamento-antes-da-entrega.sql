-- ═══════════════════════════════════════════════════════════════════════════
-- Bloco 6 (rodada 1) — D8: a 1ª entrega só depois do 1º pagamento, com
-- confirmação automática do pagamento online.
--
-- SEGURA POR PADRÃO: a chave config_negocio.exigir_pagamento_antes_da_1a_entrega
-- nasce DESLIGADA, e com ela desligada o comportamento é o de sempre.
--
--   · Ligada, criar_assinatura() gera a 1ª fatura (10% do 1º mês, vence hoje) e
--     NÃO cria entrega; a assinatura fica "aguardando pagamento"
--     (assinaturas.aguardando_pagamento_desde). Pagar a fatura libera a entrega
--     (liberar_primeira_entrega), aplicando o corte da D9 ao instante da confirmação.
--   · Quem não paga no prazo (dias_para_pagar_1a_fatura) é cancelado pela rotina.
--   · Pagamento online: o webhook roda como o papel app_pagamentos, que só executa
--     confirmar_pagamento_online() — sem comoAdmin, sem alcance a mais nada.
--     A função é idempotente (transacao_id único por provedor), recusa valor menor
--     que o da fatura e nunca aceita dado do navegador: quem chama já conferiu o
--     pagamento junto ao provedor.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Colunas
-- ───────────────────────────────────────────────────────────────────────────
alter table config_negocio
  add column exigir_pagamento_antes_da_1a_entrega boolean  not null default false,
  add column dias_para_pagar_1a_fatura            smallint not null default 7
    check (dias_para_pagar_1a_fatura between 1 and 60);

comment on column config_negocio.exigir_pagamento_antes_da_1a_entrega is
  'D8. Desligada (padrão): a assinatura nasce com a 1ª entrega agendada, como antes. Ligada: nasce aguardando o 1º pagamento, com a 1ª fatura gerada.';
comment on column config_negocio.dias_para_pagar_1a_fatura is
  'Dias, a partir da assinatura, para pagar a 1ª fatura. Passou, a rotina cancela a assinatura (só com a chave D8 ligada).';

alter table assinaturas add column aguardando_pagamento_desde date;
comment on column assinaturas.aguardando_pagamento_desde is
  'Preenchida só por criar_assinatura() com a chave D8 ligada: dia em que a assinatura passou a aguardar o 1º pagamento. Nula = normal. Zerada quando a 1ª entrega é liberada.';

create index assinaturas_aguardando_idx on assinaturas (aguardando_pagamento_desde)
  where aguardando_pagamento_desde is not null;

alter table faturas add column link_pagamento_url text
  check (link_pagamento_url is null or (char_length(link_pagamento_url) <= 500 and link_pagamento_url like 'https://%'));
comment on column faturas.link_pagamento_url is
  'Link de pagamento online gerado para esta fatura (provedor externo). Só https.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Liberar a 1ª entrega
-- ───────────────────────────────────────────────────────────────────────────
create function liberar_primeira_entrega(p_assinatura uuid, p_agora timestamptz default null)
returns date
language plpgsql
set search_path = public
as $$
declare
  v_ass     assinaturas%rowtype;
  v_cliente clientes%rowtype;
  v_agora   timestamptz := coalesce(p_agora, now());
  v_data    date;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' then
    raise exception 'Só assinaturas ativas recebem entregas.' using errcode = 'OV001';
  end if;

  -- Idempotente: já liberada (ou nunca esperou), não faz nada.
  if v_ass.aguardando_pagamento_desde is null then
    return v_ass.proxima_entrega;
  end if;

  select * into v_cliente from clientes where id = v_ass.cliente_id;

  -- D9: o corte vale para o instante da confirmação do pagamento.
  v_data := data_primeira_entrega((v_agora at time zone 'America/Sao_Paulo')::date, v_ass.plano_id, v_agora);

  insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
  values (p_assinatura, v_ass.cliente_id, v_data,
          coalesce(v_cliente.pentes_padrao, 1), coalesce(v_cliente.duzias_padrao, 0));

  update assinaturas set aguardando_pagamento_desde = null where id = p_assinatura;
  return v_data;
end;
$$;

comment on function liberar_primeira_entrega(uuid, timestamptz) is
  'D8: cria a 1ª entrega de uma assinatura que aguardava o 1º pagamento, na 1ª data do calendário do plano após o corte (D9) contado a partir de p_agora. Idempotente. Não é alcançável pelos papéis de aplicação.';

revoke execute on function liberar_primeira_entrega(uuid, timestamptz) from public;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Funções existentes, agora cientes da espera pelo pagamento
-- ───────────────────────────────────────────────────────────────────────────
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
  v_espera  boolean;   -- D8: a 1ª entrega só depois do pagamento
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

  select exigir_pagamento_antes_da_1a_entrega into v_espera from config_negocio where id = 1;

  if v_espera then
    -- D8: a assinatura nasce "aguardando 1º pagamento": sem entrega, com a 1ª fatura
    -- (10% do 1º mês, vencimento hoje) já gerada. A entrega é criada por
    -- liberar_primeira_entrega(), quando o pagamento é confirmado.
    insert into assinaturas (cliente_id, plano_id, status, data_inicio, aguardando_pagamento_desde)
    values (p_cliente, p_plano, 'ativa', v_inicio, hoje_sp())
    returning id into v_id;

    perform gerar_cobranca(v_id);
  else
    v_primeira := data_primeira_entrega(v_inicio, p_plano, v_agora);

    insert into assinaturas (cliente_id, plano_id, status, data_inicio, proxima_entrega)
    values (p_cliente, p_plano, 'ativa', v_inicio, v_primeira)
    returning id into v_id;

    insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
    values (v_id, p_cliente, v_primeira,
            coalesce(v_cliente.pentes_padrao, 1), coalesce(v_cliente.duzias_padrao, 0));
  end if;

  update clientes set plano_id = p_plano where id = p_cliente and plano_id is distinct from p_plano;

  return v_id;
end;
$$;

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

create or replace function pausar_assinatura(
  p_assinatura       uuid,
  p_motivo           text default null,
  p_retorno_previsto date default null
)
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
  if v_ass.aguardando_pagamento_desde is not null then
    raise exception 'Esta assinatura aguarda o 1º pagamento: não há o que pausar. Cancele ou aguarde o pagamento.'
      using errcode = 'OV001';
  end if;
  if p_retorno_previsto is not null and p_retorno_previsto <= hoje_sp() then
    raise exception 'O retorno previsto precisa ser depois de hoje.' using errcode = 'OV001';
  end if;

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);

  update assinaturas
     set status = 'pausada', pausada_em = hoje_sp(), data_retorno_prevista = p_retorno_previsto
   where id = p_assinatura;
  perform cancelar_pendencias_da_assinatura(p_assinatura, 'assinatura pausada');
  update clientes set status = 'suspenso' where id = v_ass.cliente_id;

  perform set_config('app.motivo', '', true);
end;
$$;

create or replace function alterar_plano_assinatura(p_assinatura uuid, p_plano smallint)
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
    raise exception 'Só assinaturas ativas ou pausadas podem trocar de plano.' using errcode = 'OV001';
  end if;
  if v_ass.aguardando_pagamento_desde is not null then
    raise exception 'A 1ª fatura já saiu com o plano atual: cancele e assine de novo para trocar de plano.'
      using errcode = 'OV001';
  end if;
  if not exists (select 1 from planos where id = p_plano and ativo) then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;

  update assinaturas set plano_id = p_plano where id = p_assinatura;
  update clientes set plano_id = p_plano where id = v_ass.cliente_id and plano_id is distinct from p_plano;
end;
$$;

create or replace function agendar_entrega(p_assinatura uuid, p_data date)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass     assinaturas%rowtype;
  v_cliente clientes%rowtype;
  v_id      uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' then
    raise exception 'Só assinaturas ativas recebem entregas.' using errcode = 'OV001';
  end if;
  if v_ass.aguardando_pagamento_desde is not null then
    raise exception 'Aguardando o 1º pagamento: registre o pagamento da 1ª fatura para liberar a entrega.'
      using errcode = 'OV001';
  end if;
  if p_data is null then
    raise exception 'Informe a data da entrega.' using errcode = 'OV001';
  end if;
  if p_data < hoje_sp() then
    raise exception 'A data da entrega não pode estar no passado.' using errcode = 'OV001';
  end if;

  select * into v_cliente from clientes where id = v_ass.cliente_id;

  insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
  values (p_assinatura, v_ass.cliente_id, p_data,
          coalesce(v_cliente.pentes_padrao, 1), coalesce(v_cliente.duzias_padrao, 0))
  returning id into v_id;

  return v_id;
end;
$$;

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


-- ───────────────────────────────────────────────────────────────────────────
-- 4. Pagamento online
-- ───────────────────────────────────────────────────────────────────────────
create table pagamentos_online (
  id                  uuid primary key default gen_random_uuid(),
  fatura_id           uuid not null references faturas(id) on delete restrict,
  provedor            text not null check (char_length(provedor) between 1 and 40),
  transacao_id        text not null check (char_length(transacao_id) between 1 and 200),
  valor_pago_centavos integer not null check (valor_pago_centavos >= 0),
  metodo              metodo_pagamento,
  status              text not null check (status in ('confirmado', 'divergente', 'sem_efeito')),
  criado_em           timestamptz not null default now(),
  unique (provedor, transacao_id)
);

create index pagamentos_online_fatura_idx on pagamentos_online (fatura_id);
create index pagamentos_online_status_idx on pagamentos_online (status) where status <> 'confirmado';

comment on table pagamentos_online is
  'Cada pagamento online já conferido junto ao provedor. unique(provedor, transacao_id) é a idempotência do webhook. divergente = valor menor que o da fatura (não pagou); sem_efeito = chegou para fatura já paga/cancelada (possível estorno manual).';

alter table pagamentos_online enable row level security;

revoke all on table pagamentos_online from app_anon, app_usuario;
grant select on table pagamentos_online to app_usuario;

create policy "pagamentos online: dono le tudo, assinante os das proprias faturas"
  on pagamentos_online for select to app_usuario
  using ((select sou_dono()) or exists (select 1 from faturas f where f.id = pagamentos_online.fatura_id));

-- Papel mínimo do webhook: executa UMA função. O app_servidor recebe o papel sem
-- herdar (criar-papel-servidor.mjs) e troca para ele com set local role.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_pagamentos') then
    create role app_pagamentos nologin;
  end if;
end;
$$;
grant usage on schema public to app_pagamentos;

-- Quem roda a migration precisa poder `set local role app_pagamentos` (testes e
-- simulações), como na migration 4: no Neon a conta administrativa não é superusuária.
grant app_pagamentos to current_user with inherit false;

create function confirmar_pagamento_online(
  p_fatura      uuid,
  p_provedor    text,
  p_transacao   text,
  p_valor_pago  integer,
  p_metodo      text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_f      faturas%rowtype;
  v_metodo metodo_pagamento;
begin
  if coalesce(btrim(p_provedor), '') = '' or coalesce(btrim(p_transacao), '') = ''
     or p_valor_pago is null or p_valor_pago < 0 then
    raise exception 'Dados do pagamento inválidos.' using errcode = 'OV001';
  end if;

  -- Serializa avisos simultâneos da mesma fatura.
  select * into v_f from faturas where id = p_fatura for update;
  if not found then
    raise exception 'Fatura não encontrada.' using errcode = 'OV001';
  end if;

  -- Aviso repetido (o provedor reenvia): nada a fazer.
  if exists (select 1 from pagamentos_online where provedor = p_provedor and transacao_id = p_transacao) then
    return 'ja_processado';
  end if;

  v_metodo := case lower(coalesce(p_metodo, ''))
                when 'pix' then 'pix' when 'cartao' then 'cartao' else 'outro'
              end::metodo_pagamento;

  if v_f.status not in ('pendente', 'atrasada') then
    insert into pagamentos_online (fatura_id, provedor, transacao_id, valor_pago_centavos, metodo, status)
    values (p_fatura, p_provedor, p_transacao, p_valor_pago, v_metodo, 'sem_efeito');
    return 'sem_efeito';
  end if;

  if p_valor_pago < v_f.valor_centavos then
    insert into pagamentos_online (fatura_id, provedor, transacao_id, valor_pago_centavos, metodo, status)
    values (p_fatura, p_provedor, p_transacao, p_valor_pago, v_metodo, 'divergente');
    return 'divergente';
  end if;

  perform set_config('app.motivo', 'Confirmado automaticamente (' || p_provedor || ')', true);
  perform registrar_pagamento(p_fatura, hoje_sp(), v_metodo, 'Confirmado automaticamente: ' || p_provedor);
  perform set_config('app.motivo', '', true);

  insert into pagamentos_online (fatura_id, provedor, transacao_id, valor_pago_centavos, metodo, status)
  values (p_fatura, p_provedor, p_transacao, p_valor_pago, v_metodo, 'confirmado');
  return 'confirmado';
end;
$$;

comment on function confirmar_pagamento_online(uuid, text, text, integer, text) is
  'Baixa automática de fatura. SÓ para quem já conferiu o pagamento junto ao provedor (nunca com dado vindo do navegador). Idempotente por (provedor, transacao). Valor menor que o da fatura grava "divergente" e não paga. Executável apenas pelo papel app_pagamentos.';

revoke execute on function confirmar_pagamento_online(uuid, text, text, integer, text) from public, app_anon, app_usuario;
grant  execute on function confirmar_pagamento_online(uuid, text, text, integer, text) to app_pagamentos;

-- Lado do assinante: pegar o que precisa para gerar o link, só da PRÓPRIA fatura.
create function iniciar_pagamento_online(p_fatura uuid)
returns table (valor_centavos integer, referencia text, link_existente text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select f.valor_centavos, f.id::text, f.link_pagamento_url
      from faturas f
      join clientes c on c.id = f.cliente_id
     where f.id = p_fatura
       and c.usuario_id = app.usuario_id()
       and f.status in ('pendente', 'atrasada');
  if not found then
    raise exception 'Fatura não encontrada ou já paga.' using errcode = 'OV001';
  end if;
end;
$$;

comment on function iniciar_pagamento_online(uuid) is
  'Devolve valor, referência (id da fatura) e link já gerado, só se a fatura é da conta da sessão e está em aberto.';

revoke execute on function iniciar_pagamento_online(uuid) from public;
grant  execute on function iniciar_pagamento_online(uuid) to app_usuario;

create function anexar_link_pagamento(p_fatura uuid, p_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update faturas f
     set link_pagamento_url = p_url
    from clientes c
   where f.id = p_fatura and c.id = f.cliente_id
     and c.usuario_id = app.usuario_id()
     and f.status in ('pendente', 'atrasada');
  if not found then
    raise exception 'Fatura não encontrada ou já paga.' using errcode = 'OV001';
  end if;
end;
$$;

comment on function anexar_link_pagamento(uuid, text) is
  'Guarda o link de pagamento (https, até 500 caracteres) na PRÓPRIA fatura em aberto.';

revoke execute on function anexar_link_pagamento(uuid, text) from public;
grant  execute on function anexar_link_pagamento(uuid, text) to app_usuario;

-- Limite da rota do webhook.
create or replace function limitar_acesso_publico(p_ip text, p_rota text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip     text := coalesce(nullif(left(btrim(p_ip), 64), ''), 'desconhecido');
  v_limite integer;
begin
  v_limite := case p_rota
    when 'area'      then 30   -- /api/area: uma ida ao banco por consulta
    when 'evento'    then 60   -- /api/evento: contagem do funil
    when 'interesse' then 5    -- /api/interesse: grava dado pessoal
    when 'webhook'   then 120  -- /api/pagamento/webhook: o provedor pode reenviar
    else null
  end;
  if v_limite is null then
    raise exception 'Rota pública desconhecida.';
  end if;

  return verificar_rate_limit(v_ip, 'publico:' || p_rota, v_limite, 60);
end;
$$;


-- Down Migration

create or replace function limitar_acesso_publico(p_ip text, p_rota text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip     text := coalesce(nullif(left(btrim(p_ip), 64), ''), 'desconhecido');
  v_limite integer;
begin
  v_limite := case p_rota
    when 'area'      then 30   -- /api/area: uma ida ao banco por consulta
    when 'evento'    then 60   -- /api/evento: contagem do funil
    when 'interesse' then 5    -- /api/interesse: grava dado pessoal
    else null
  end;
  if v_limite is null then
    raise exception 'Rota pública desconhecida.';
  end if;

  return verificar_rate_limit(v_ip, 'publico:' || p_rota, v_limite, 60);
end;
$$;

drop function if exists anexar_link_pagamento(uuid, text);
drop function if exists iniciar_pagamento_online(uuid);
drop function if exists confirmar_pagamento_online(uuid, text, text, integer, text);
drop table if exists pagamentos_online;
drop owned by app_pagamentos;
drop role if exists app_pagamentos;

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
end;
$$;

create or replace function pausar_assinatura(
  p_assinatura       uuid,
  p_motivo           text default null,
  p_retorno_previsto date default null
)
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
  if p_retorno_previsto is not null and p_retorno_previsto <= hoje_sp() then
    raise exception 'O retorno previsto precisa ser depois de hoje.' using errcode = 'OV001';
  end if;

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);

  update assinaturas
     set status = 'pausada', pausada_em = hoje_sp(), data_retorno_prevista = p_retorno_previsto
   where id = p_assinatura;
  perform cancelar_pendencias_da_assinatura(p_assinatura, 'assinatura pausada');
  update clientes set status = 'suspenso' where id = v_ass.cliente_id;

  perform set_config('app.motivo', '', true);
end;
$$;

create or replace function alterar_plano_assinatura(p_assinatura uuid, p_plano smallint)
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
    raise exception 'Só assinaturas ativas ou pausadas podem trocar de plano.' using errcode = 'OV001';
  end if;
  if not exists (select 1 from planos where id = p_plano and ativo) then
    raise exception 'Plano inválido.' using errcode = 'OV001';
  end if;

  update assinaturas set plano_id = p_plano where id = p_assinatura;
  update clientes set plano_id = p_plano where id = v_ass.cliente_id and plano_id is distinct from p_plano;
end;
$$;

create or replace function agendar_entrega(p_assinatura uuid, p_data date)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_ass     assinaturas%rowtype;
  v_cliente clientes%rowtype;
  v_id      uuid;
begin
  select * into v_ass from assinaturas where id = p_assinatura for update;
  if not found then
    raise exception 'Assinatura não encontrada.' using errcode = 'OV001';
  end if;
  if v_ass.status <> 'ativa' then
    raise exception 'Só assinaturas ativas recebem entregas.' using errcode = 'OV001';
  end if;
  if p_data is null then
    raise exception 'Informe a data da entrega.' using errcode = 'OV001';
  end if;
  if p_data < hoje_sp() then
    raise exception 'A data da entrega não pode estar no passado.' using errcode = 'OV001';
  end if;

  select * into v_cliente from clientes where id = v_ass.cliente_id;

  insert into entregas (assinatura_id, cliente_id, data_prevista, pentes, duzias)
  values (p_assinatura, v_ass.cliente_id, p_data,
          coalesce(v_cliente.pentes_padrao, 1), coalesce(v_cliente.duzias_padrao, 0))
  returning id into v_id;

  return v_id;
end;
$$;

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

drop function if exists liberar_primeira_entrega(uuid, timestamptz);
alter table faturas drop column if exists link_pagamento_url;
drop index if exists assinaturas_aguardando_idx;
alter table assinaturas drop column if exists aguardando_pagamento_desde;
alter table config_negocio
  drop column if exists dias_para_pagar_1a_fatura,
  drop column if exists exigir_pagamento_antes_da_1a_entrega;
