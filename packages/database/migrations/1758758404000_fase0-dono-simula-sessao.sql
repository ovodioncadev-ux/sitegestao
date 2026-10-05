-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 0 (correção) — o dono precisa poder simular sessão para testar.
--
-- Descoberto rodando os testes de autorização contra um Postgres de verdade
-- (Neon): a conexão administrativa (`DATABASE_ADMIN_URL`) não é superusuário
-- lá — diferente de um Postgres local, onde a conta que cria os papéis
-- normalmente também pode `set role` para qualquer um deles sem permissão
-- explícita. Sem essa concessão, `set local role app_usuario` dentro dos
-- testes falha com "permission denied to set role", e TODOS os cenários —
-- inclusive os de ataque, que deveriam falhar mesmo — "passam" pelo motivo
-- errado. É exatamente o problema que os controles positivos (itens 8, 15,
-- 19 de tests/teste-autorizacao.sql) existem para pegar.
--
-- `with inherit false`, igual ao app_servidor: quem roda a migration não
-- ganha os privilégios de app_usuario/app_anon só por estar conectado — só
-- alcança depois de um `set local role` explícito, exatamente como o app
-- real faz. `current_user` captura quem executa a migration (neondb_owner
-- no Neon, `postgres` num Postgres local, etc.) — nunca um nome fixo.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

grant app_anon, app_usuario to current_user with inherit false;

-- Down Migration

revoke app_anon, app_usuario from current_user;
