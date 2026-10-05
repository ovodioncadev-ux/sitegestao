-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 1 (complemento) — clientes: endereço completo e e-mail único.
--
-- O que já existia em `clientes`: cep, endereco, complemento, status,
-- pentes_padrao e duzias_padrao. Faltavam número, bairro, cidade e estado, e
-- nada impedia dois cadastros com o mesmo e-mail.
--
-- Nenhum dado existente é alterado. As colunas novas nascem nulas.
--
-- E-mail único sem diferenciar maiúscula de minúscula. Vários clientes sem
-- e-mail continuam permitidos (lead de evento, comprador avulso): o índice só
-- vale onde o e-mail existe. O formato do e-mail é conferido no servidor, não
-- aqui — um `check` de formato reprovaria linhas antigas em silêncio.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

alter table clientes
  add column numero text     check (char_length(numero) <= 20),
  add column bairro text     check (char_length(bairro) <= 100),
  add column cidade text     check (char_length(cidade) <= 100),
  add column estado char(2)  check (estado ~ '^[A-Z]{2}$');

comment on column clientes.endereco is 'Logradouro (rua, avenida). Número e complemento ficam em colunas próprias.';
comment on column clientes.numero   is 'Número do imóvel, como texto: existe "s/n" e "123-A".';
comment on column clientes.estado   is 'UF em maiúsculas, duas letras.';

create unique index clientes_email_unico_idx
  on clientes (lower(email))
  where email is not null;

comment on index clientes_email_unico_idx is
  'E-mail único, sem diferenciar maiúscula. Cliente sem e-mail pode existir em quantidade.';

-- Down Migration

drop index if exists clientes_email_unico_idx;
alter table clientes
  drop column if exists estado,
  drop column if exists cidade,
  drop column if exists bairro,
  drop column if exists numero;
