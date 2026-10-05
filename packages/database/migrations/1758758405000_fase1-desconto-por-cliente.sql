-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 1 (extensão) — exceção de desconto por cliente.
--
-- planos.desconto_primeiro_mes_pct decide o desconto padrão de todo mundo
-- (10% para os três planos, ver DECISOES.md). Esta coluna é a exceção:
-- clientes específicos que não recebem o desconto do primeiro mês, por
-- decisão do dono no cadastro — não uma regra nova de negócio, só um
-- registro de caso a caso.
--
-- Ninguém além da conexão administrativa grava aqui: mesma regra de
-- `clientes` inteira, nenhum grant de insert/update para papel de
-- aplicação. Ver DECISOES.md se algum dia isso virar regra geral em vez
-- de exceção.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

alter table clientes
  add column desconto_primeiro_mes_aplicavel boolean not null default true;

comment on column clientes.desconto_primeiro_mes_aplicavel is
  'false = este cliente específico não recebe o desconto do primeiro mês, por decisão do dono no cadastro. Padrão true (recebe, como todo mundo).';

-- Down Migration

alter table clientes drop column desconto_primeiro_mes_aplicavel;
