-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 4 — faturas (cobrança MANUAL).
--
--     cliente ──< assinatura ──< fatura
--
-- Sem gateway, sem PIX automático (DECISOES.md #4): o dono cria a fatura,
-- confere o comprovante no WhatsApp e marca como paga.
--
-- Dinheiro é sempre inteiro em centavos.
--
-- Decidido pelo dono em 25/09/2026:
--   • o VALOR da fatura é calculado:
--         (pentes × preço do pente + dúzias × preço da dúzia) × entregas do mês
--     com o desconto do 1º mês (planos.desconto_primeiro_mes_pct) se o cliente
--     tem `desconto_primeiro_mes_aplicavel` e é a primeira fatura dele;
--   • a primeira fatura paga torna o cliente `ativo` (o comentário do enum
--     status_cliente já dizia isso);
--   • o dono pode ajustar o valor antes de criar.
--
-- ⚠ A CONFIRMAR: `planos.entregas_por_mes` (4, 2 e 1) foi DERIVADO dos preços
--   documentados no projeto (semanal R$ 164, quinzenal R$ 82, mensal R$ 41,
--   com o pente a R$ 41 por entrega). O banco não guardava esse número.
-- ⚠ PENDENTE: `config_negocio.preco_duzia_centavos` está em 0 (placeholder).
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

alter table planos add column entregas_por_mes smallint check (entregas_por_mes > 0);

update planos
   set entregas_por_mes = case frequencia
         when 'semanal'   then 4
         when 'quinzenal' then 2
         when 'mensal'    then 1
       end;

alter table planos alter column entregas_por_mes set not null;

comment on column planos.entregas_por_mes is
  'Entregas cobradas em uma mensalidade: semanal 4, quinzenal 2, mensal 1. DERIVADO dos preços documentados (R$ 164 / 82 / 41 com o pente a R$ 41) — a confirmar com o dono.';


create type status_fatura     as enum ('pendente', 'paga', 'atrasada', 'cancelada');
create type metodo_pagamento  as enum ('pix', 'dinheiro', 'transferencia', 'outro');

create table faturas (
  id              uuid primary key default gen_random_uuid(),

  cliente_id      uuid not null references clientes (id)    on delete restrict,
  assinatura_id   uuid not null references assinaturas (id) on delete restrict,

  valor_centavos  integer not null check (valor_centavos > 0),
  vencimento      date    not null,
  data_pagamento  date,
  status          status_fatura not null default 'pendente',
  metodo          metodo_pagamento,
  observacao      text check (char_length(observacao) <= 500),

  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),

  -- Paga TEM data e método de pagamento, e só ela tem.
  check ((status = 'paga') = (data_pagamento is not null)),
  check ((status = 'paga') = (metodo is not null))
);

comment on table faturas is
  'Cobrança manual de uma assinatura. Valor em centavos. Paga exige data e método.';
comment on column faturas.status is
  '`atrasada` é gravada por marcar_faturas_atrasadas() (chamada ao abrir a tela de faturas): pendente com vencimento anterior a hoje.';

create index faturas_cliente_idx    on faturas (cliente_id);
create index faturas_assinatura_idx on faturas (assinatura_id);
create index faturas_status_idx     on faturas (status, vencimento);

-- Uma fatura viva por assinatura e vencimento: clique duplo não cobra duas vezes.
create unique index faturas_vencimento_unico_idx
  on faturas (assinatura_id, vencimento)
  where status <> 'cancelada';


create or replace function faturas_antes_de_gravar()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if not exists (
      select 1 from assinaturas where id = new.assinatura_id and cliente_id = new.cliente_id
    ) then
      raise exception 'A fatura precisa ser do mesmo cliente da assinatura.' using errcode = 'OV001';
    end if;
  else
    new.id            := old.id;
    new.cliente_id    := old.cliente_id;
    new.assinatura_id := old.assinatura_id;
    new.criado_em     := old.criado_em;
  end if;
  new.atualizado_em := now();
  return new;
end;
$$;

create trigger faturas_antes_de_gravar_tg
  before insert or update on faturas
  for each row execute function faturas_antes_de_gravar();

revoke execute on function faturas_antes_de_gravar() from public;


-- RLS: o assinante vê as próprias faturas; o dono, todas; ninguém escreve direto.
alter table faturas enable row level security;

revoke all on table faturas from app_anon, app_usuario;
grant select on table faturas to app_usuario;

create policy "faturas: le as proprias, dono le todas"
  on faturas for select to app_usuario
  using (
    (select sou_dono())
    or exists (
      select 1 from clientes c
      where c.id = faturas.cliente_id
        and c.usuario_id = app.usuario_id()
    )
  );


-- ───────────────────────────────────────────────────────────────────────────
-- Valor calculado
-- ───────────────────────────────────────────────────────────────────────────
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

  -- Pente é o produto: sem quantidade padrão no cliente, conta 1.
  v_valor := (coalesce(v_cli.pentes_padrao, 1) * v_cfg.preco_pente_centavos
              + coalesce(v_cli.duzias_padrao, 0) * v_cfg.preco_duzia_centavos)
             * v_plano.entregas_por_mes;

  -- Desconto do 1º mês: só na primeira fatura (não cancelada) do cliente.
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


-- ───────────────────────────────────────────────────────────────────────────
-- Criar, pagar, cancelar
-- ───────────────────────────────────────────────────────────────────────────
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

revoke execute on function registrar_pagamento(uuid, date, metodo_pagamento, text) from public;


create or replace function cancelar_fatura(p_fatura uuid, p_motivo text default null)
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
    raise exception 'Fatura paga não pode ser cancelada.' using errcode = 'OV001';
  end if;
  if v_f.status = 'cancelada' then
    raise exception 'Esta fatura já está cancelada.' using errcode = 'OV001';
  end if;

  perform set_config('app.motivo', coalesce(p_motivo, ''), true);
  update faturas
     set status = 'cancelada',
         observacao = left(concat_ws(' | ', observacao,
                                     case when nullif(trim(p_motivo), '') is not null
                                          then 'Cancelada: ' || trim(p_motivo) end), 500)
   where id = p_fatura;
  perform set_config('app.motivo', '', true);
end;
$$;

revoke execute on function cancelar_fatura(uuid, text) from public;


-- Pendente com vencimento anterior a hoje vira atrasada.
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

revoke execute on function marcar_faturas_atrasadas() from public;


-- Down Migration

drop function if exists marcar_faturas_atrasadas();
drop function if exists cancelar_fatura(uuid, text);
drop function if exists registrar_pagamento(uuid, date, metodo_pagamento, text);
drop function if exists criar_fatura(uuid, date, integer, text);
drop function if exists calcular_valor_fatura(uuid);
drop policy if exists "faturas: le as proprias, dono le todas" on faturas;
drop trigger if exists faturas_antes_de_gravar_tg on faturas;
drop function if exists faturas_antes_de_gravar();
drop table if exists faturas;
drop type if exists metodo_pagamento;
drop type if exists status_fatura;
alter table planos drop column if exists entregas_por_mes;
