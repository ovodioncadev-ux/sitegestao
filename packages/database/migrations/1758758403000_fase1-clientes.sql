-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 1 — clientes.
--
-- É a tabela mais usada do painel e a mais perigosa do sistema: é aqui que
-- um assinante veria o endereço e o telefone de outro, se a autorização
-- falhasse.
--
-- Duas regras que valem para o arquivo inteiro:
--
--   1. O cliente NÃO escreve direto nesta tabela. Nenhum grant de insert,
--      update ou delete para papel de aplicação. Toda alteração passa por
--      função com lista fechada de campos.
--   2. O id é uuid, não sequencial. `/cliente/2` → `/cliente/3` não é um
--      ataque que funciona aqui.
--
-- Um cliente NÃO é um usuário. `clientes` é o registro de negócio;
-- `clientes.usuario_id` liga opcionalmente a uma conta. Cliente sem conta é
-- normal e precisa continuar funcionando: lead de evento, comprador avulso,
-- cliente importado de planilha.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

create type tipo_cliente  as enum ('b2c', 'b2b');
create type status_cliente as enum ('pre_venda', 'cadastro_andamento', 'ativo', 'suspenso', 'cancelado');
create type origem_lead    as enum ('trafego_pago', 'indicacao', 'influenciador', 'organico', 'b2b_direto');

comment on type status_cliente is
  'pre_venda: cadastrou mas está fora da área de entrega — é estágio de funil, não recusa. '
  'cadastro_andamento: escolheu plano, ainda não pagou a 1ª fatura. '
  'ativo: pagou. É a entrada na coorte, e é o que a análise de safra usa.';

create table clientes (
  id                   uuid primary key default gen_random_uuid(),

  -- Conta de acesso. `set null` de propósito: se a conta for apagada, o
  -- registro de negócio e todo o histórico continuam. Ver DECISOES.md #8.
  usuario_id           text unique references "user" (id) on delete set null,

  tipo                 tipo_cliente   not null default 'b2c',
  status               status_cliente not null default 'cadastro_andamento',

  nome                 text not null check (char_length(nome) between 1 and 120),
  apelido              text check (char_length(apelido) <= 60),
  telefone             text check (telefone ~ '^\+55\d{10,11}$'),
  email                text check (char_length(email) <= 254),

  cep                  char(8) check (cep ~ '^\d{8}$'),
  endereco             text check (char_length(endereco) <= 200),
  complemento          text check (char_length(complemento) <= 100),
  dentro_area_entrega  boolean not null default false,

  origem               origem_lead not null,
  motivo_assinatura    text check (char_length(motivo_assinatura) <= 500),

  codigo_indicacao     text not null unique
                         check (codigo_indicacao ~ '^[A-Z0-9-]{4,20}$'),
  indicado_por         uuid references clientes (id) on delete set null
                         check (indicado_por is distinct from id),

  plano_id             smallint references planos (id) on delete restrict,
  pentes_padrao        smallint check (pentes_padrao between 1 and 50),
  duzias_padrao        smallint check (duzias_padrao between 0 and 50),

  data_nascimento      date check (data_nascimento > date '1900-01-01'),

  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now()
);

comment on table clientes is
  'Registro de negócio do cliente. Ninguém escreve aqui pelo app: toda alteração passa por função com lista fechada de campos.';
comment on column clientes.usuario_id is
  'Conta do Better Auth, quando existe. Cliente sem conta é normal e precisa continuar funcionando.';
comment on column clientes.dentro_area_entrega is
  'Calculado pelo gatilho a partir do CEP. NUNCA vem do corpo da requisição.';
comment on column clientes.duzias_padrao is
  'Dúzias que acompanham o pente em cada entrega. A dúzia não é plano — ver DECISOES.md #12.';
comment on column clientes.indicado_por is
  'Quem indicou. `set null` ao apagar o indicador: o histórico do indicado não some junto.';

create index clientes_status_idx    on clientes (status);
create index clientes_plano_idx     on clientes (plano_id);
create index clientes_cep_idx       on clientes (cep);
create index clientes_indicado_idx  on clientes (indicado_por);
create index clientes_nome_idx      on clientes (lower(nome));


-- ───────────────────────────────────────────────────────────────────────────
-- Código de indicação
--
-- Formato ONCA-XXXX, sem os caracteres que a pessoa erra ao ditar no
-- WhatsApp: O e 0, I e 1 e l.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function gerar_codigo_indicacao()
returns text
language plpgsql
set search_path = public
as $$
declare
  v_alfabeto constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  v_codigo   text;
  v_tentativa int := 0;
begin
  loop
    v_codigo := 'ONCA-';
    for i in 1..4 loop
      v_codigo := v_codigo || substr(v_alfabeto, 1 + floor(random() * length(v_alfabeto))::int, 1);
    end loop;

    exit when not exists (select 1 from clientes where codigo_indicacao = v_codigo);

    v_tentativa := v_tentativa + 1;
    if v_tentativa > 50 then
      raise exception 'não consegui gerar um código de indicação único';
    end if;
  end loop;

  return v_codigo;
end;
$$;

revoke execute on function gerar_codigo_indicacao() from public;


create or replace function clientes_antes_de_gravar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.codigo_indicacao is null or new.codigo_indicacao = '' then
      new.codigo_indicacao := gerar_codigo_indicacao();
    end if;
    new.criado_em := now();
  else
    -- Imutáveis. O id nunca muda, e a data de criação não se reescreve.
    new.id        := old.id;
    new.criado_em := old.criado_em;
  end if;

  -- Sempre calculado, nunca recebido. Se viesse do corpo da requisição,
  -- qualquer pessoa se declararia dentro da área de entrega.
  new.dentro_area_entrega := cep_dentro_area_entrega(new.cep);

  new.atualizado_em := now();
  return new;
end;
$$;

comment on function clientes_antes_de_gravar() is
  'Gera o código de indicação, congela id e criado_em, e recalcula dentro_area_entrega a partir do CEP.';

create trigger clientes_antes_de_gravar_tg
  before insert or update on clientes
  for each row execute function clientes_antes_de_gravar();

revoke execute on function clientes_antes_de_gravar() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- RLS
-- ───────────────────────────────────────────────────────────────────────────
alter table clientes enable row level security;

revoke all on table clientes from app_anon, app_usuario;
grant select on table clientes to app_usuario;
-- Nenhum grant de insert/update/delete. Nem para o dono: o painel escreve
-- pela conexão administrativa, depois de exigirDono() aprovar.

create policy "clientes: le o proprio, dono le todos"
  on clientes for select to app_usuario
  using (
    usuario_id = app.usuario_id()
    or (select sou_dono())
  );


-- ───────────────────────────────────────────────────────────────────────────
-- O que o cliente pode alterar — lista fechada
--
-- Lei 5: nada de `update(req.body)`. Os campos que esta função aceita são
-- exatamente os que o cliente pode mudar, e nenhum outro existe aqui.
--
-- Fora da lista, e por isso inalcançáveis: status, plano_id, tipo,
-- usuario_id, dentro_area_entrega, indicado_por, qualquer preço.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function atualizar_meus_dados(
  p_cliente_id      uuid,
  p_nome            text default null,
  p_apelido         text default null,
  p_telefone        text default null,
  p_cep             text default null,
  p_endereco        text default null,
  p_complemento     text default null,
  p_data_nascimento date default null,
  p_codigo_indicacao text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_telefone text;
  v_cep      text;
  v_codigo   text;
begin
  -- SEMPRE a primeira instrução, antes de ler ou gravar qualquer coisa.
  if not (
    coalesce(sou_dono(), false)
    or exists (
      select 1 from clientes
      where id = p_cliente_id and usuario_id = app.usuario_id()
    )
  ) then
    raise exception 'sem permissão para esta operação';
  end if;

  -- Normalização e validação no servidor. O cliente valida também, para dar
  -- resposta rápida, mas quem decide é aqui.
  if p_telefone is not null then
    v_telefone := regexp_replace(p_telefone, '\D', '', 'g');
    if length(v_telefone) not between 10 and 11 then
      raise exception 'telefone inválido';
    end if;
    v_telefone := '+55' || v_telefone;
  end if;

  if p_cep is not null then
    v_cep := regexp_replace(p_cep, '\D', '', 'g');
    if length(v_cep) <> 8 then
      raise exception 'CEP inválido';
    end if;
  end if;

  if p_codigo_indicacao is not null then
    v_codigo := upper(trim(p_codigo_indicacao));
    if v_codigo !~ '^[A-Z0-9-]{4,20}$' then
      raise exception 'código de indicação inválido: use 4 a 20 letras, números ou hífen';
    end if;
    if exists (select 1 from clientes where codigo_indicacao = v_codigo and id <> p_cliente_id) then
      raise exception 'esse código de indicação já está em uso';
    end if;
  end if;

  update clientes set
    nome             = coalesce(nullif(trim(p_nome), ''), nome),
    apelido          = coalesce(nullif(trim(p_apelido), ''), apelido),
    telefone         = coalesce(v_telefone, telefone),
    cep              = coalesce(v_cep, cep),
    endereco         = coalesce(nullif(trim(p_endereco), ''), endereco),
    complemento      = coalesce(nullif(trim(p_complemento), ''), complemento),
    data_nascimento  = coalesce(p_data_nascimento, data_nascimento),
    codigo_indicacao = coalesce(v_codigo, codigo_indicacao)
  where id = p_cliente_id;

  if not found then
    raise exception 'cliente não encontrado';
  end if;
end;
$$;

comment on function atualizar_meus_dados(uuid, text, text, text, text, text, text, date, text) is
  'Único caminho para o cliente alterar os próprios dados. Lista fechada: status, plano, tipo, preço e vínculo de conta não estão aqui.';

revoke execute on function atualizar_meus_dados(uuid, text, text, text, text, text, text, date, text) from public;
grant execute on function atualizar_meus_dados(uuid, text, text, text, text, text, text, date, text) to app_usuario;


-- ───────────────────────────────────────────────────────────────────────────
-- Nome de quem indicou — função PÚBLICA de propósito
--
-- A tela de cadastro mostra "Você foi indicado por Maria" antes de existir
-- conta. Ela devolve SÓ O PRIMEIRO NOME: nada de sobrenome, telefone,
-- e-mail, endereço ou id. Uma exceção declarada, não um descuido.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function nome_do_indicador(p_codigo text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select split_part(trim(coalesce(apelido, nome)), ' ', 1)
  from clientes
  where codigo_indicacao = upper(trim(p_codigo))
    and status <> 'cancelado'
  limit 1;
$$;

comment on function nome_do_indicador(text) is
  'PÚBLICA DE PROPÓSITO: a tela de cadastro precisa dela antes de existir sessão. '
  'Devolve apenas o primeiro nome. NÃO devolve sobrenome, telefone, e-mail, endereço nem id. '
  'Código inexistente devolve null, sem dizer se existe ou não.';

revoke execute on function nome_do_indicador(text) from public;
grant execute on function nome_do_indicador(text) to app_anon, app_usuario;


-- Down Migration

drop function if exists nome_do_indicador(text);
drop function if exists atualizar_meus_dados(uuid, text, text, text, text, text, text, date, text);
drop policy if exists "clientes: le o proprio, dono le todos" on clientes;
drop trigger if exists clientes_antes_de_gravar_tg on clientes;
drop function if exists clientes_antes_de_gravar();
drop function if exists gerar_codigo_indicacao();
drop table if exists clientes;
drop type if exists origem_lead;
drop type if exists status_cliente;
drop type if exists tipo_cliente;
