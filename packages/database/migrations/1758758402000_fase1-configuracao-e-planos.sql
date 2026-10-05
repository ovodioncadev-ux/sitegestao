-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 1 — tabelas de configuração.
--
-- Aqui moram os valores que hoje estão espalhados pelo site e pela
-- calculadora, se contradizendo. Preço, frescor, frete e desconto passam a
-- ter UM lugar. Nenhum componente escreve esses números.
--
-- Dinheiro é SEMPRE inteiro em centavos. `0.1 + 0.2` não dá `0.3`, e isso
-- vira diferença de centavo em cobrança recorrente. Sem exceção.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Configuração do negócio — uma linha só, para sempre
-- ───────────────────────────────────────────────────────────────────────────
create table config_negocio (
  id                        smallint primary key default 1 check (id = 1),
  dia_corte                 smallint not null default 1
                              check (dia_corte between 0 and 6),
  hora_corte                time     not null default '18:00',
  preco_pente_centavos      integer  not null check (preco_pente_centavos >= 0),
  preco_duzia_centavos      integer  not null check (preco_duzia_centavos >= 0),
  bonus_indicador_pct       numeric(5,2) not null default 0
                              check (bonus_indicador_pct between 0 and 100),
  teto_credito_indicacao_pct numeric(5,2) not null default 100
                              check (teto_credito_indicacao_pct between 0 and 100),
  atualizado_em             timestamptz not null default now()
);

comment on table config_negocio is
  'Uma linha só (id = 1). Os valores que o negócio inteiro usa. Nenhum deles é escrito direto num componente.';
comment on column config_negocio.dia_corte is
  'Dia da semana do corte, no padrão do Postgres: 0 = domingo, 3 = quarta. Padrão 1 = segunda.';
comment on column config_negocio.preco_pente_centavos is
  'Preço do pente de 30 ovos, em centavos. R$ 41,00 = 4100.';
comment on column config_negocio.preco_duzia_centavos is
  'Preço da dúzia avulsa, em centavos. A dúzia não é plano: ela acompanha o pente. Ver DECISOES.md #12.';

insert into config_negocio (id, preco_pente_centavos, preco_duzia_centavos)
values (1, 4100, 0);

-- Uma linha, e só uma: o gatilho recusa a segunda.
create or replace function config_negocio_linha_unica()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'config_negocio tem uma linha só. Use UPDATE, não INSERT nem DELETE.';
end;
$$;

create trigger config_negocio_sem_insert
  before insert or delete on config_negocio
  for each row execute function config_negocio_linha_unica();

revoke execute on function config_negocio_linha_unica() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- 2. Planos
--
-- Frescor, frete e desconto viram COLUNAS. No sistema antigo eles não
-- existiam no schema, e era por isso que o site e a calculadora se
-- contradiziam e ninguém conseguia arbitrar.
-- ───────────────────────────────────────────────────────────────────────────
create type frequencia_plano as enum ('semanal', 'quinzenal', 'mensal');

create table planos (
  id                         smallint generated always as identity primary key,
  frequencia                 frequencia_plano not null unique,
  nome                       text not null,
  intervalo_dias             smallint not null check (intervalo_dias > 0),
  ancorar_em_quarta          boolean not null default true,
  freshness_max_dias         smallint not null check (freshness_max_dias > 0),
  frete_centavos             integer  not null default 0 check (frete_centavos >= 0),
  desconto_primeiro_mes_pct  numeric(5,2) not null default 0
                               check (desconto_primeiro_mes_pct between 0 and 100),
  ativo                      boolean not null default true,
  criado_em                  timestamptz not null default now()
);

comment on table planos is
  'Os três planos. Frescor, frete e desconto moram aqui, não no componente. Ver DECISOES.md.';
comment on column planos.intervalo_dias is
  'Dias entre uma entrega e a seguinte. Decidido em 24/09/2026: 7, 15 e 30 — em dias, não em quartas.';
comment on column planos.ancorar_em_quarta is
  'true: a data calculada é arredondada para a quarta mais próxima, e a entrega sempre cai na quarta. '
  'false: o intervalo é exato e o dia da semana escorrega. 15 e 30 não são múltiplos de 7, então as '
  'duas coisas não podem valer ao mesmo tempo. Trocar é um UPDATE, sem migration. Ver DECISOES.md.';
comment on column planos.freshness_max_dias is
  'Prazo máximo entre a coleta e a entrega. 7 em todos os planos, confirmado em 24/09/2026.';
comment on column planos.frete_centavos is
  'Zero nos três: o frete já está incluso no valor da assinatura, confirmado em 24/09/2026.';
comment on column planos.desconto_primeiro_mes_pct is
  '10% na primeira mensalidade, valendo para PIX e cartão, confirmado em 24/09/2026.';

insert into planos (frequencia, nome, intervalo_dias, freshness_max_dias, frete_centavos, desconto_primeiro_mes_pct)
values
  ('semanal',   'Semanal',    7, 7, 0, 10),
  ('quinzenal', 'Quinzenal', 15, 7, 0, 10),
  ('mensal',    'Mensal',    30, 7, 0, 10);

create index planos_ativo_idx on planos (ativo) where ativo;


-- ───────────────────────────────────────────────────────────────────────────
-- 3. Área de entrega
-- ───────────────────────────────────────────────────────────────────────────
create table faixas_cep_atendidas (
  id         integer generated always as identity primary key,
  cep_inicio char(8) not null check (cep_inicio ~ '^\d{8}$'),
  cep_fim    char(8) not null check (cep_fim ~ '^\d{8}$'),
  bairro     text,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now(),
  check (cep_fim >= cep_inicio)
);

comment on table faixas_cep_atendidas is
  'Faixas de CEP atendidas. Vazia = ninguém está dentro da área. Nunca o contrário.';

create index faixas_cep_busca_idx on faixas_cep_atendidas (cep_inicio, cep_fim) where ativo;

create or replace function cep_dentro_area_entrega(p_cep text)
returns boolean
language sql
stable
set search_path = public
as $$
  -- Sem nenhuma faixa cadastrada, o resultado é "fora de área". Um sistema
  -- que responde "dentro" quando não sabe promete entrega que não existe.
  select exists (
    select 1 from faixas_cep_atendidas
    where ativo
      and regexp_replace(coalesce(p_cep, ''), '\D', '', 'g') between cep_inicio and cep_fim
  );
$$;

comment on function cep_dentro_area_entrega(text) is
  'O CEP está numa faixa atendida e ativa? Sem faixas cadastradas, devolve false.';

revoke execute on function cep_dentro_area_entrega(text) from public;
grant execute on function cep_dentro_area_entrega(text) to app_anon, app_usuario;


-- ───────────────────────────────────────────────────────────────────────────
-- 4. RLS
--
-- Estas três são tabelas de configuração, não de cliente: qualquer pessoa
-- logada lê, e ninguém escreve pelo app. A escrita é do dono, pela conexão
-- administrativa, depois de exigirDono() aprovar.
--
-- `faixas_cep_atendidas` é legível também por quem não está logado: a tela
-- de cadastro precisa dizer "atendemos seu bairro" antes de existir conta.
-- ───────────────────────────────────────────────────────────────────────────
alter table config_negocio enable row level security;
alter table planos enable row level security;
alter table faixas_cep_atendidas enable row level security;

revoke all on table config_negocio, planos, faixas_cep_atendidas from app_anon, app_usuario;
grant select on table planos to app_anon, app_usuario;
grant select on table faixas_cep_atendidas to app_anon, app_usuario;
grant select on table config_negocio to app_usuario;

create policy "planos: anonimo le os ativos"
  on planos for select to app_anon
  using (ativo);

create policy "planos: usuario logado le ativos ou inativ os se for dono"
  on planos for select to app_usuario
  using (ativo or (select sou_dono()));

create policy "faixas: anonimo le as ativas"
  on faixas_cep_atendidas for select to app_anon
  using (ativo);

create policy "faixas: usuario logado le ativas ou inativas se for dono"
  on faixas_cep_atendidas for select to app_usuario
  using (ativo or (select sou_dono()));

create policy "config: quem esta logado le"
  on config_negocio for select to app_usuario
  using (true);

-- Nenhuma policy de insert, update ou delete: escrita só pela conexão
-- administrativa, que ignora a RLS por ser dona das tabelas.


-- Down Migration

drop policy if exists "config: quem esta logado le" on config_negocio;
drop policy if exists "faixas: qualquer um le as ativas" on faixas_cep_atendidas;
drop policy if exists "planos: qualquer um le os ativos" on planos;
drop function if exists cep_dentro_area_entrega(text);
drop table if exists faixas_cep_atendidas;
drop table if exists planos;
drop type if exists frequencia_plano;
drop trigger if exists config_negocio_sem_insert on config_negocio;
drop function if exists config_negocio_linha_unica();
drop table if exists config_negocio;
