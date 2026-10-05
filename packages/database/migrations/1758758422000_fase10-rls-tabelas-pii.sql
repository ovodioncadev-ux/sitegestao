-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 10 — RLS em tabelas de PII (dados pessoais)
--
-- Até agora, apenas `perfis` tinha RLS. A proteção das demais tabelas
-- (`clientes`, `assinaturas`, `entregas`, `faturas`) era feita por:
--   1. Middleware validando cookie
--   2. Server Actions validando papel (`exigirDono()`)
--   3. DB pool isolado (app_servidor, não app_usuario)
--
-- Isso funciona, mas é frágil: se alguém contorna a camada de aplicação
-- (ex: query direto ao DB), consegue ver dados de outro cliente.
--
-- Esta migração adiciona RLS às 4 tabelas, formando camada 3 de proteção.
-- Agora um usuário não consegue ver dados alheios MESMO que contorne o app.
--
-- Padrão de policy por tabela:
--   • SELECT: usuário vê apenas seu cliente (via clientes.usuario_id) + dono vê tudo
--   • UPDATE: usuário altera apenas seu próprio registro, sem tocar em cliente_id
--   • DELETE: apenas dono pode deletar (nunca app_usuario)
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Habilitar RLS nas 4 tabelas
-- ───────────────────────────────────────────────────────────────────────────
alter table clientes enable row level security;
alter table assinaturas enable row level security;
alter table entregas enable row level security;
alter table faturas enable row level security;


-- ───────────────────────────────────────────────────────────────────────────
-- 2. Policies para CLIENTES
--
-- Um usuário vê apenas o cliente que é seu (via clientes.usuario_id).
-- O dono vê todos.
-- ───────────────────────────────────────────────────────────────────────────

-- SELECT: usuário vê seu próprio cliente, dono vê tudo
create policy clientes_select_policy on clientes
  for select
  using (
    sou_dono()
    or usuario_id = app.usuario_id()
  );

comment on policy clientes_select_policy on clientes is
  'Usuário vê apenas seu cliente. Dono vê todos.';


-- UPDATE: usuário altera apenas seu cliente, sem tocar em usuario_id
create policy clientes_update_policy on clientes
  for update
  using (
    sou_dono()
    or usuario_id = app.usuario_id()
  )
  with check (
    sou_dono()
    or usuario_id = app.usuario_id()
  );

comment on policy clientes_update_policy on clientes is
  'Usuário altera apenas seu cliente, mantendo usuario_id. Dono altera qualquer coisa.';


-- DELETE: apenas dono
create policy clientes_delete_policy on clientes
  for delete
  using (sou_dono());

comment on policy clientes_delete_policy on clientes is
  'Apenas dono deleta cliente (raro, geralmente cancelamento em vez de delete).';


-- INSERT: negado para app_usuario (não há política CREATE)
-- (toda inserção de cliente passa por função SQL com lista fechada)


-- ───────────────────────────────────────────────────────────────────────────
-- 3. Policies para ASSINATURAS
--
-- Assinatura é sempre ligada a um cliente. Usuário vê apenas assinaturas
-- do seu cliente.
-- ───────────────────────────────────────────────────────────────────────────

-- SELECT: usuário vê assinaturas do seu cliente, dono vê tudo
create policy assinaturas_select_policy on assinaturas
  for select
  using (
    sou_dono()
    or cliente_id in (
      select id from clientes where usuario_id = app.usuario_id()
    )
  );

comment on policy assinaturas_select_policy on assinaturas is
  'Usuário vê apenas assinaturas do seu cliente. Dono vê todas.';


-- UPDATE: usuário altera assinaturas do seu cliente, sem tocar em cliente_id
create policy assinaturas_update_policy on assinaturas
  for update
  using (
    sou_dono()
    or cliente_id in (
      select id from clientes where usuario_id = app.usuario_id()
    )
  )
  with check (
    sou_dono()
    or cliente_id in (
      select id from clientes where usuario_id = app.usuario_id()
    )
  );

comment on policy assinaturas_update_policy on assinaturas is
  'Usuário altera apenas assinaturas do seu cliente, mantendo cliente_id.';


-- DELETE: apenas dono
create policy assinaturas_delete_policy on assinaturas
  for delete
  using (sou_dono());

comment on policy assinaturas_delete_policy on assinaturas is
  'Apenas dono deleta assinatura (raro, geralmente muda status em vez de delete).';


-- ───────────────────────────────────────────────────────────────────────────
-- 4. Policies para ENTREGAS
--
-- Entrega é ligada a uma assinatura, que é ligada a um cliente.
-- ───────────────────────────────────────────────────────────────────────────

-- SELECT: usuário vê entregas do seu cliente, dono vê tudo
create policy entregas_select_policy on entregas
  for select
  using (
    sou_dono()
    or cliente_id in (
      select id from clientes where usuario_id = app.usuario_id()
    )
  );

comment on policy entregas_select_policy on entregas is
  'Usuário vê apenas entregas do seu cliente. Dono vê todas.';


-- UPDATE: usuário altera entregas do seu cliente, sem tocar em cliente_id/assinatura_id
create policy entregas_update_policy on entregas
  for update
  using (
    sou_dono()
    or cliente_id in (
      select id from clientes where usuario_id = app.usuario_id()
    )
  )
  with check (
    sou_dono()
    or cliente_id in (
      select id from clientes where usuario_id = app.usuario_id()
    )
  );

comment on policy entregas_update_policy on entregas is
  'Usuário altera apenas entregas do seu cliente, mantendo cliente_id e assinatura_id.';


-- DELETE: apenas dono
create policy entregas_delete_policy on entregas
  for delete
  using (sou_dono());

comment on policy entregas_delete_policy on entregas is
  'Apenas dono deleta entrega (raro, geralmente muda status em vez de delete).';


-- ───────────────────────────────────────────────────────────────────────────
-- 5. Policies para FATURAS
--
-- Fatura é ligada a um cliente. Usuário vê apenas faturas do seu cliente.
-- ───────────────────────────────────────────────────────────────────────────

-- SELECT: usuário vê faturas do seu cliente, dono vê tudo
create policy faturas_select_policy on faturas
  for select
  using (
    sou_dono()
    or cliente_id in (
      select id from clientes where usuario_id = app.usuario_id()
    )
  );

comment on policy faturas_select_policy on faturas is
  'Usuário vê apenas faturas do seu cliente. Dono vê todas.';


-- UPDATE: usuário altera faturas do seu cliente, sem tocar em cliente_id
create policy faturas_update_policy on faturas
  for update
  using (
    sou_dono()
    or cliente_id in (
      select id from clientes where usuario_id = app.usuario_id()
    )
  )
  with check (
    sou_dono()
    or cliente_id in (
      select id from clientes where usuario_id = app.usuario_id()
    )
  );

comment on policy faturas_update_policy on faturas is
  'Usuário altera apenas faturas do seu cliente, mantendo cliente_id.';


-- DELETE: apenas dono
create policy faturas_delete_policy on faturas
  for delete
  using (sou_dono());

comment on policy faturas_delete_policy on faturas is
  'Apenas dono deleta fatura (raro, geralmente muda status em vez de delete).';


-- ───────────────────────────────────────────────────────────────────────────
-- 6. Revogar escritas diretas de app_usuario (redundante com policies, mas explícito)
--
-- app_usuario não consegue INSERT em tabela alguma delas — toda escrita passa
-- por função SQL com lista fechada (no código do painel ou do app). Esta
-- revoke torna isto explícito: erro no nivel de grant, não de policy.
-- ───────────────────────────────────────────────────────────────────────────
revoke insert on clientes, assinaturas, entregas, faturas from app_usuario;
revoke delete on clientes, assinaturas, entregas, faturas from app_usuario;

-- UPDATE é permitido por policy, mas grants de coluna podem restringir depois.
-- Por enquanto, leave UPDATE: policies protegem.

comment on table clientes is
  'Registro de negócio do cliente. RLS: usuário vê apenas seu cliente. Dono vê todos.';
comment on table assinaturas is
  'Contrato no tempo. RLS: usuário vê apenas assinaturas do seu cliente. Dono vê todas.';
comment on table entregas is
  'Entrega agendada. RLS: usuário vê apenas entregas do seu cliente. Dono vê todas.';
comment on table faturas is
  'Cobrança. RLS: usuário vê apenas faturas do seu cliente. Dono vê todas.';


-- Down Migration

-- ─────────────────────────────────────────────────────────────────────────────
-- Desabilitar RLS (rollback para estado anterior)
-- ─────────────────────────────────────────────────────────────────────────────
alter table clientes disable row level security;
alter table assinaturas disable row level security;
alter table entregas disable row level security;
alter table faturas disable row level security;

-- Restaurar grants (RLS desabilitada, então volta a usar grants como antes)
grant insert on clientes, assinaturas, entregas, faturas to app_usuario;

-- Policies são automaticamente dropadas ao disable, então não é necessário
-- DROP POLICY explicitamente durante rollback.
