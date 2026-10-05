-- ═══════════════════════════════════════════════════════════════════════════
-- Etapa 1 (3/4) — selo do plano ("Recomendado"), controlado pelo dado.
--
-- DECISOES.md, D13: o plano semanal leva o selo "Recomendado", no lugar do
-- antigo "Mais escolhido" que estava escrito fixo no componente do site.
--
-- `planos.selo` guarda o texto do selo (nulo = sem selo). O site só mostra o
-- que o banco devolve; o dono edita em /configuracoes.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

alter table planos
  add column selo text check (selo is null or char_length(selo) between 1 and 30);

comment on column planos.selo is
  'Selo exibido no cartão do plano na vitrine (ex.: Recomendado). Nulo = sem selo. Editável em /configuracoes.';

-- D13: só o semanal.
update planos set selo = 'Recomendado' where frequencia = 'semanal';

-- planos_publicos passa a devolver o selo. Colunas de saída mudam, então a
-- função é recriada (create or replace não permite mudar o retorno).
drop function if exists planos_publicos();

create function planos_publicos()
returns table (
  id                        smallint,
  frequencia                text,
  nome                      text,
  intervalo_dias            smallint,
  ancorar_em_quarta         boolean,
  preco_centavos            integer,
  freshness_max_dias        smallint,
  frete_centavos            integer,
  desconto_primeiro_mes_pct numeric,
  selo                      text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.frequencia::text, p.nome, p.intervalo_dias, p.ancorar_em_quarta,
         (c.preco_pente_centavos * p.entregas_por_mes)::integer,
         p.freshness_max_dias, p.frete_centavos, p.desconto_primeiro_mes_pct,
         p.selo
    from planos p
    cross join config_negocio c
   where p.ativo and c.id = 1
   order by p.intervalo_dias;
$$;

comment on function planos_publicos() is
  'Vitrine de planos para quem não está logado. Preço = preço do pente × entregas por mês (1 pente por entrega, como calcular_valor_fatura). Sem preço no código. Inclui o selo.';

revoke execute on function planos_publicos() from public;
grant  execute on function planos_publicos() to app_anon, app_usuario;


-- Down Migration

drop function if exists planos_publicos();

create function planos_publicos()
returns table (
  id                        smallint,
  frequencia                text,
  nome                      text,
  intervalo_dias            smallint,
  ancorar_em_quarta         boolean,
  preco_centavos            integer,
  freshness_max_dias        smallint,
  frete_centavos            integer,
  desconto_primeiro_mes_pct numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.frequencia::text, p.nome, p.intervalo_dias, p.ancorar_em_quarta,
         (c.preco_pente_centavos * p.entregas_por_mes)::integer,
         p.freshness_max_dias, p.frete_centavos, p.desconto_primeiro_mes_pct
    from planos p
    cross join config_negocio c
   where p.ativo and c.id = 1
   order by p.intervalo_dias;
$$;

comment on function planos_publicos() is
  'Vitrine de planos para quem não está logado. Preço = preço do pente × entregas por mês (1 pente por entrega, como calcular_valor_fatura). Sem preço no código.';

revoke execute on function planos_publicos() from public;
grant  execute on function planos_publicos() to app_anon, app_usuario;

alter table planos drop column if exists selo;
