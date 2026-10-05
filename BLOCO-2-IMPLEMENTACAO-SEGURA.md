# 🔐 BLOCO 2: IMPLEMENTAÇÃO SEGURA COM VERSIONAMENTO

**Status:** Pronto para execução  
**Data:** 2026-10-05  
**Baseado em:** Auditoria de Segurança Operacional (seções 1–5)  
**Modelo:** Claude Haiku 4.5  

---

## VISÃO GERAL

Após diagnóstico de limpeza estrutural (BLOCO 1) e auditoria de segurança (FASE 2), este bloco implementa as correções priorizadas via 5 PRs sequenciadas. Cada PR é mergeable independentemente mas segue ordem de dependências.

**Objetivo:** Banco seguro + código versionado + CI validando mudanças.

---

## ORDEM DE EXECUÇÃO

### 🟦 PR-1: CI/CD Setup & Testes SQL (Bloqueante)

**Dependência:** Nenhuma  
**Impacto:** Base para todas as outras PRs  
**Esforço:** 2–3h  
**Risco:** Baixo (apenas setup)

**O que faz:**
- Reabilita `.github/workflows/ci.yml` (varredura secrets + typecheck + lint)
- Configura `DATABASE_TEST_URL` (branch de teste Neon)
- Roda `pnpm teste:banco` (14 suítes SQL: fase1..10, seguranca)
- Registra baseline de testes passando

**Mudanças:**
```
.github/workflows/ci.yml          ← Ativa secrets scan, tests, lint
.env.example                       ← Adiciona DATABASE_TEST_URL
packages/database/README.md        ← Documenta como rodar testes locais
pnpm-lock.yaml                     ← (Sync se dependências mudarem)
```

**Checklist:**
- [ ] Validar `.gitignore` (`.env`, Design System, node_modules)
- [ ] Configurar secrets em GitHub: `CRON_SECRET`, `RESEND_API_KEY` (se houver)
- [ ] Rodar `pnpm teste:banco` localmente — todos os 14 suítes passam
- [ ] Merge: CI passa, baseline registrado

**Resultado esperado:**
```
✅ pnpm teste:banco: 14/14 suítes
✅ pnpm seguranca: 0 secrets encontrados
✅ pnpm typecheck: sem erros
✅ pnpm lint: sem erros críticos
```

---

### 🟩 PR-2: SEGURANCA.md — Documentação Centralizada (Low Priority)

**Dependência:** PR-1 (CI passando)  
**Impacto:** Referência, não código  
**Esforço:** 1–2h  
**Risco:** Nenhum (doc only)

**O que faz:**
- Cria `docs/SEGURANCA.md` (threat model + mitigações)
- Documenta rate limit tunning (Better Auth + DB)
- Registra disaster recovery (restore do backup Neon)
- Mapeia superfície de exposição (4 endpoints + policies RLS)
- Links para DECISOES.md (referência cruzada)

**Seções:**
```markdown
1. Threat Model — 5 cenários + probabilidade + impacto
2. Mitigações — RLS, Better Auth, Server Actions, DB pool
3. Rate Limit Tunning — por endpoint, em memória vs DB
4. Superfície de Exposição — endpoints públicos + proteção cada
5. Disaster Recovery — restore Neon, rollback migrations
6. Runbook — o que fazer se alguém acessa DATABASE_ADMIN_URL
7. Auditoria — triggers + log em `auditoria` table
```

**Mudanças:**
```
docs/SEGURANCA.md                 ← Novo (3KB)
CLAUDE.md                          ← Referencia SEGURANCA.md (1 linha)
```

**Resultado esperado:**
```
✅ Arquivo criado com 7 seções
✅ Threats mapeados (criticidade: alta/média/baixa)
✅ Mitigações vinculadas a código/config específicos
✅ Runbook claro para incident
```

---

### 🔴 PR-3: RLS em Tabelas PII — Proteção no Banco (High Priority)

**Dependência:** PR-1 (testes SQL rodando)  
**Impacto:** Segurança crítica  
**Esforço:** 4–6h  
**Risco:** Médio (altera dados + políticas)

**O que faz:**
- Adiciona RLS a 4 tabelas: `clientes`, `assinaturas`, `entregas`, `faturas`
- Define 3 políticas por tabela:
  - `select`: usuário vê apenas dados de seu perfil + dono vê todos
  - `update`: usuário altera apenas seu registro (sem `papel`/`pin_hash`)
  - `delete`: apenas dono pode deletar
- Revoga default `INSERT/UPDATE/DELETE` de `app_usuario` em todas
- Migração SQL: adiciona policies + testa com queries de exemplo
- Testes SQL: 5 novos testes (select+update+delete por papel)

**Mudanças:**
```
packages/database/migrations/migration_23_rls_tabelas_pii.sql
  ├── CREATE POLICY clientes_select_policy ...
  ├── CREATE POLICY clientes_update_policy ...
  ├── CREATE POLICY clientes_delete_policy ...
  ├── (repeate para assinaturas, entregas, faturas)
  └── REVOKE UPDATE/DELETE FROM app_usuario ...

packages/database/tests/fase_rls_pii.sql
  ├── test: usuário vê apenas seu cliente ✅
  ├── test: usuário não consegue update de papel ✅
  ├── test: dono vê todos os clientes ✅
  ├── test: delete é só dono ✅
  └── test: anon não consegue update ✅
```

**Checklist:**
- [ ] Escrever migration (migration_23_*)
- [ ] Rodar localmente: `pnpm db:migrar` + `pnpm teste:banco fase_rls_pii`
- [ ] Testar com role `app_usuario` (SELECT + UPDATE + DELETE)
- [ ] Testar com role `dono` (todos os dados, sem bloqueio)
- [ ] Testar com role `app_anon` (sem acesso)
- [ ] Merge: CI passa, 5 testes SQL novos passam

**Resultado esperado:**
```
✅ 4 tabelas com RLS (clientes, assinaturas, entregas, faturas)
✅ Policies para select/update/delete por papel
✅ 5 testes SQL passam (antes/depois RLS)
✅ Sem impacto em Server Actions (já fazem `exigirDono()`)
```

---

### 🟡 PR-4: Rate Limit em DB (Medium Priority)

**Dependência:** PR-1 (testes SQL rodando)  
**Impacto:** Resiliência em serverless  
**Esforço:** 2–3h  
**Risco:** Baixo (config apenas)

**O que faz:**
- Migração: cria tabela `rateLimit` (ip TEXT, endpoint TEXT, count INT, reset_at TIMESTAMP)
- Better Auth: configura `storage: 'database'` (pool admin)
- Adiciona trigger: limpa registros expirados (reset_at < now())
- Documenta em SEGURANCA.md + `.env.example`

**Mudanças:**
```
packages/database/migrations/migration_24_rate_limit_table.sql
  ├── CREATE TABLE rateLimit (...)
  └── CREATE TRIGGER limpar_rate_limit_expirados ...

apps/assinante/src/lib/auth.ts
  ├── better_auth config: storage: 'database'
  └── uncomment rate limit config

.env.example
  ├── DATABASE_RATE_LIMIT_URL (opcional, usa DATABASE_URL se não set)

docs/SEGURANCA.md
  └── "Rate Limit em DB: vê Deployment" (link a PR-4)
```

**Checklist:**
- [ ] Escrever migration
- [ ] Testar: `pnpm db:migrar`, tabela criada ✅
- [ ] Configurar Better Auth: `storage: 'database'`
- [ ] Testar rate limit: 5 req/min depois bloqueia (função BEFORE INSERT)
- [ ] Merge: CI passa, rate limit em DB funciona

**Resultado esperado:**
```
✅ Tabela rateLimit criada
✅ Better Auth usando DB em vez de memória
✅ Em serverless: limite global (não por instância)
✅ Sem impacto em latência (<1ms por check)
```

---

### 🟢 PR-5: CSP Headers & Rate Limit Server Actions (Low Priority)

**Dependência:** PR-1 (CI passando), opcional PR-2 (doc)  
**Impacto:** Defesa contra XSS + DDoS em críticas  
**Esforço:** 1–2h  
**Risco:** Baixo (headers apenas, sem lógica)

**O que faz:**
- Adiciona CSP headers em `next.config.ts` (modo report-only inicialmente)
- Adiciona rate limit wrapper em Server Actions críticas: `assinar_plano`, `gerar_cobranca`, `processar_rotina_diaria`
- Documenta em SEGURANCA.md + código comentado

**Mudanças:**
```
next.config.ts
  ├── csp: {
  │   ├── "default-src": ["'self'"],
  │   ├── "script-src": ["'self'", "'nonce-...'"],
  │   └── modoRelatorio: true  (para prod: false)
  └── }

apps/assinante/src/app/assinar/acoes.ts
  ├── export const assinar_plano = rateLimitServerAction(
  │   { limit: 10, period: '1h' },
  │   async (formData) => { ... }
  └── )

apps/gestao/src/app/financeiro/acoes.ts
  ├── export const gerar_cobranca = rateLimitServerAction(...)
  └── export const processar_rotina_diaria = rateLimitServerAction(...)

packages/database/src/auth/rate-limit-server-action.ts
  └── Função helper (checa DB + incrementa counter)
```

**Checklist:**
- [ ] Adicionar CSP headers em `next.config.ts` (modo report-only)
- [ ] Criar `rate-limit-server-action.ts` helper
- [ ] Envolver 3 Server Actions críticas
- [ ] Testar: 11ª chamada retorna erro de rate limit ✅
- [ ] Merge: CI passa, CSP headers setados

**Resultado esperado:**
```
✅ CSP headers em resposta (mode: report-only)
✅ Rate limit em Server Actions críticas (via DB)
✅ XSS reduzido via CSP
✅ DDoS em criticalidades reduzido via rate limit
```

---

## DEPENDÊNCIAS E MERGE ORDER

```
PR-1 (CI/CD Setup)  ← Bloqueante, merge primeiro
│
├─→ PR-2 (SEGURANCA.md)  ← Independente, pode ser paralelo
├─→ PR-3 (RLS em PII)    ← Requer PR-1, crítico
├─→ PR-4 (Rate Limit DB) ← Requer PR-1, pode ser paralelo a PR-3
└─→ PR-5 (CSP + Rate Limit SA) ← Requer PR-1, pode ser paralelo a 3–4
```

**Timeline recomendada:**
- **Dia 1:** PR-1 merge (CI passa) + PR-2 draft (doc)
- **Dia 2:** PR-3 + PR-4 em paralelo (feature branches)
- **Dia 3:** PR-5 (finalização)
- **Dia 4:** Validação em staging (todos rodando)

---

## VALIDAÇÃO POR PR

| PR | Testes | Merge Criteria |
|----|--------|----------------|
| PR-1 | CI passes, 14 SQL suites | `pnpm teste:banco`, `pnpm seguranca` ✅ |
| PR-2 | Manual review | Doc claro, links corretos, sem typos |
| PR-3 | 5 new SQL tests + CI | Policies ativas, RLS validada, sem impacto SA |
| PR-4 | Rate limit test + CI | DB table criado, Better Auth usando DB |
| PR-5 | CSP + rate limit test + CI | CSP headers preset, SA limita corretamente |

---

## PRONTO PARA EXECUTAR?

**Decisões pendentes:**
1. ✅ Repositório: usar git atual (já em raiz)
2. ✅ Acesso Neon: DATABASE_TEST_URL (qual branch?)
3. ⚠️ Modo CSP: report-only (seguro) ou enforced (pode quebrar)?

**Próximo passo:**
- [ ] Confirmar DATABASE_TEST_URL
- [ ] Rodar PR-1 (CI/CD Setup)
- [ ] Validar que 14 testes SQL passam
- [ ] Depois: PR-3 (RLS) é crítica, execute segunda

---

**Preparado por:** Claude Haiku 4.5  
**Data:** 2026-10-05  
**Versão:** 1.0
