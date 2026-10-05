# 🔐 SEGURANÇA — Threat Model, Mitigações e Runbook

**Documento de Referência:** Segurança operacional do Ovo di Onça  
**Data:** 2026-10-05  
**Baseado em:** Auditoria de Segurança Operacional (Fase 2)  
**Validade:** Revisar anualmente ou após mudanças em autenticação/banco  

---

## 📖 ÍNDICE

1. [Threat Model](#threat-model) — Cenários de ataque
2. [Mitigações](#mitigações) — Proteções implementadas
3. [Rate Limit Tunning](#rate-limit-tunning) — Configuração por endpoint
4. [Superfície de Exposição](#superfície-de-exposição) — Endpoints públicos
5. [Disaster Recovery](#disaster-recovery) — Restore e rollback
6. [Runbook de Incident](#runbook-de-incident) — O que fazer em emergência
7. [Auditoria e Compliance](#auditoria-e-compliance) — Logs e verificação

---

## Threat Model

### Cenário 1: SQL Injection via User Input

**Risco:** 🟡 Médio  
**Probabilidade:** Baixa (mitigação forte)  
**Impacto:** Alto (acesso a dados de todos os clientes)

#### Ataque
Usuário envia: `' OR '1'='1` em formulário de cadastro  
Esperado: Input tratado como string literal  
Falha de mitigação: Query construída com concatenação

#### Proteção Atual
- ✅ **Nível DB:** Prepared statements via `pg` (params vinculados)
- ✅ **Nível App:** TypeScript + Zod validation em todos os Server Actions
- ✅ **Nível RLS:** Even se SQL injection passasse, RLS bloqueia dados de outros clientes

#### Mitigação
```typescript
// ✅ SEGURO: parâmetros vinculados
const result = await pool.query(
  'SELECT * FROM clientes WHERE email = $1',
  [email]  // Nunca concatenar!
);

// ❌ NUNCA FAZER:
const result = await pool.query(
  `SELECT * FROM clientes WHERE email = '${email}'`  // SQL injection!
);
```

**Severidade:** 🟢 Baixa em produção (protegida em 3 camadas)

---

### Cenário 2: Acesso Lateral — Usuário Vê Dados de Outro Cliente

**Risco:** 🔴 Crítico  
**Probabilidade:** Muito baixa (múltiplas proteções)  
**Impacto:** Crítico (vazamento de dados pessoais)

#### Ataque
Usuário autenticado chama `/api/cliente/123` sendo cliente 456  
Esperado: Erro 403 (acesso negado)  
Falha de mitigação: Retorna dados de cliente 123

#### Proteção Atual
- ✅ **Nível 1 (Middleware):** Valida cookie de sessão
- ✅ **Nível 2 (App):** `usuarioAtual()` retorna próprio ID, Server Action valida
- ✅ **Nível 3 (DB):** RLS previne query mesmo se app falha

```typescript
// Server Action exemplo:
export async function obterMeuCliente() {
  const usuario = await usuarioAtual();  // ← Lança erro se não autenticado
  if (!usuario) throw new Error('Não autenticado');
  
  // `cliente` é vinculado ao usuário no banco
  const cliente = await db.query(
    'SELECT * FROM clientes WHERE perfil_id = $1',
    [usuario.id]  // Sempre usa ID do usuário autenticado
  );
}
```

RLS complementa:
```sql
CREATE POLICY clientes_select_policy ON clientes
  FOR SELECT
  USING (
    auth.uid() = perfil_id  -- Usuário só vê seu próprio cliente
    OR meu_papel() = 'dono'  -- Ou é dono
  );
```

**Severidade:** 🟢 Muito baixa (3 camadas de validação)

---

### Cenário 3: Exploração via Rate Limit

**Risco:** 🟡 Médio  
**Probabilidade:** Alta em serverless  
**Impacto:** Médio (brute force, force password, resource exhaustion)

#### Ataque
Atacante faz 1000 req/s para `/api/auth/signin`  
Esperado: Bloqueado após 5 req/min  
Falha de mitigação: Rate limit em memória (por instância) ⟶ múltiplas instâncias = limite frouxo

#### Proteção Atual
- ✅ **Global:** Better Auth + rate limit por IP (100 req/60s)
- ✅ **Por endpoint:** Limite específico (sign-in: 5 req/60s)
- ❌ **Problema:** Armazenado em memória (não sincroniza entre instâncias)

#### Mitigação (Implementada em PR-4)
```typescript
// Better Auth config (packages/database/src/auth.ts)
export const auth = betterAuth({
  database: {
    db: db,  // ← Usar DB para rate limit
  },
  rateLimit: {
    enabled: true,
    windowMs: 60 * 1000,
    max: 100,  // 100 req/min global
    storage: 'database',  // ← Usar DB em vez de memória
  },
  signInRateLimit: {
    enabled: true,
    windowMs: 60 * 1000,
    max: 5,  // 5 signin attempts/min
  },
});
```

**Severidade:** 🟡 Média até PR-4 (rate limit em DB)

---

### Cenário 4: Comprometimento da Credencial Admin (DATABASE_ADMIN_URL)

**Risco:** 🔴 Crítico  
**Probabilidade:** Muito baixa (credencial em `.env`, não versionada)  
**Impacto:** Crítico (acesso total ao banco, sem RLS)

#### Ataque
Alguém obtém `DATABASE_ADMIN_URL` (ex: git history, logs, leak de `.env`)  
Esperado: Conexão como `neondb_owner`, sem RLS  
Falha: Acesso a todos os dados de todos os clientes, sem restrição

#### Proteção Atual
- ✅ `.env` em `.gitignore` (não é versionado)
- ✅ `scripts/verificar-segredos.sh` detecta secrets em commits
- ✅ Neon: credenciais regeneradas periodicamente
- ✅ Conexão admin = pool pequeno (4 conexões max), apenas para migrations + auth
- ✅ CI roda varredura de secrets antes de cada push

#### Mitigação
```bash
# Detectar secrets em histórico:
bash scripts/verificar-segredos.sh

# Se encontrado, reescrever história:
git filter-repo --invert-paths --path .env  # Remove de todos commits
git push --force-with-lease
```

**Severidade:** 🔴 Crítica até descoberta (por isso verificação automática)

---

### Cenário 5: CSRF — Falsificação de Requisição Entre Sites

**Risco:** 🟡 Médio  
**Probabilidade:** Baixa (mitigação implementada)  
**Impacto:** Médio (alguém faz ação em nome do usuário)

#### Ataque
Usuário logado em `assinante.ovodionca.local` clica link malicioso  
Esperado: Ação rejeita CSRF  
Falha: Ação executada sem consentimento (ex: cancelar assinatura)

#### Proteção Atual
- ✅ **Better Auth:** Valida `trustedOrigins` (lista de domínios permitidos)
- ✅ **Cookies:** `sameSite=lax` (bloqueia cross-site POST)
- ✅ **Session:** Cookie de sessão não é enviado a origem desconhecida

```typescript
// Better Auth config
export const auth = betterAuth({
  trustedOrigins: [
    'http://localhost:3001',        // desenvolvimento
    'http://localhost:3000',        // gestão
    'https://assinante.ovodionca.com',  // produção
  ],
});
```

**Severidade:** 🟢 Baixa (trustedOrigins + sameSite)

---

## Mitigações

### Arquitetura de Proteção em 3 Camadas

```
┌─────────────────────────────────────────┐
│ CAMADA 1: Middleware & Sessão           │
│ - Valida cookie de sessão               │
│ - Bloqueia requests sem cookie          │
│ - Rate limit global por IP              │
└──────────────────┬──────────────────────┘
                   ↓
┌─────────────────────────────────────────┐
│ CAMADA 2: Server Actions & Better Auth  │
│ - Valida papel (usuário/dono)           │
│ - `exigirDono()` antes de qualquer ação │
│ - `usuarioAtual()` retorna ID           │
│ - Rate limit por endpoint (sign-in)     │
└──────────────────┬──────────────────────┘
                   ↓
┌─────────────────────────────────────────┐
│ CAMADA 3: RLS & Banco de Dados          │
│ - Queries preparadas (params vinculados)│
│ - RLS policies por tabela               │
│ - Triggers para validação               │
│ - Roles (app_anon, app_usuario, dono)   │
└─────────────────────────────────────────┘
```

### Por Aspecto

#### 1️⃣ Autenticação
- ✅ Better Auth (JWT + session cookie)
- ✅ Email verificação (condicional, via Resend)
- ✅ Password ≥ 12 caracteres (validado no sign-up)
- ✅ Google OAuth (único provedor que garante email)
- ❌ 2FA: não implementado
- ❌ Token rotation: não implementado (7 dias estático)

#### 2️⃣ Autorização
- ✅ RLS no banco (políticas por tabela)
- ✅ Papéis: anon, usuário, dono, assinante
- ✅ `exigirDono()` em Server Actions críticas
- ✅ Grants de coluna (usuário não consegue alterar `papel`)
- ✅ Auditoria: triggers gravando antes/depois

#### 3️⃣ Criptografia
- ✅ Senhas: Argon2id via Better Auth
- ✅ Cookies: httpOnly, secure, sameSite
- ✅ Conexão BD: SSL/TLS (Neon obrigatório)
- ✅ Session storage: encrypted via Better Auth

#### 4️⃣ Entrada
- ✅ Validação Zod em todos Server Actions
- ✅ Prepared statements (params vinculados)
- ✅ Sanitização de e-mail (E.164 para telefone)
- ✅ CEP validação: apenas numeração

#### 5️⃣ Network
- ✅ HTTPS obrigatório (produção)
- ✅ CORS: Next.js default (restritivo)
- ✅ CSP: report-only (será enforced em PR-5)
- ❌ WAF: não implementado (delegado ao provedor)

---

## Rate Limit Tunning

### Configuração Atual (PR-1)

| Endpoint | Limite | Janela | Armazenamento | Status |
|----------|--------|--------|---------------|--------|
| Global | 100 req | 60s | Memória | ⚠️ Serverless |
| `/api/auth/signin` | 5 req | 60s | Memória | ⚠️ Serverless |
| `/api/auth/signup` | 5 req | 3600s | Memória | ⚠️ Serverless |
| Server Actions | Nenhum | — | — | ❌ Não limitado |

### Ideal (PR-4)

| Endpoint | Limite | Janela | Armazenamento | Status |
|----------|--------|--------|---------------|--------|
| Global | 100 req | 60s | **DB** | ✅ Sincronizado |
| `/api/auth/signin` | 5 req | 60s | **DB** | ✅ Sincronizado |
| `/api/auth/signup` | 5 req | 3600s | **DB** | ✅ Sincronizado |
| `assinar_plano` (SA) | 10 req | 3600s | **DB** | ✅ Implementado |
| `gerar_cobranca` (SA) | 5 req | 3600s | **DB** | ✅ Implementado |

### Por Cenário

**Brute Force Sign-in:**
- 5 tentativas/min = 300 tentativas/hora
- Esperado: senha forte + email confirmation ⟹ impraticável

**DDoS em Server Actions:**
- Rate limit em DB = sincronizado entre instâncias
- Exemplo: `gerar_cobranca` limitado a 5/hora ⟹ falha para 6ª chamada

**Bot/Crawler:**
- Global 100 req/min = 6000 req/hora
- Atacante precisa de múltiplos IPs para escalar

---

## Superfície de Exposição

### Endpoints Públicos (4 total)

#### 1. `GET /api/plans`
```typescript
// Exemplo de chamada:
GET /api/plans

// Resposta:
{
  "planos": [
    { "id": "semanal", "descricao": "1x por semana", "preço": 164.00 },
    { "id": "quinzenal", "descricao": "2x por mês", "preço": 82.00 },
    { "id": "mensal", "descricao": "1x por mês", "preço": 41.00 }
  ]
}
```

**Proteção:**
- ✅ Anônimo permitido (dados públicos)
- ✅ Cache 5 min (reduz carga)
- ✅ Sem input do usuário (sem validação necessária)
- ✅ RLS: dados vem de `planos_publicos()` (função view)

**Risco:** 🟢 Nenhum

---

#### 2. `GET /api/neighborhoods?cep=01310100`
```typescript
// Exemplo:
GET /api/neighborhoods?cep=01310100

// Resposta:
{
  "inArea": true,
  "neighborhood": "Centro",
  "deliveryDays": ["quarta", "sábado"]
}
```

**Proteção:**
- ✅ Anônimo permitido (dados públicos)
- ✅ Validação: CEP apenas numeração (10 algarismos)
- ✅ Sem SQL injection: função PL/pgSQL `cep_dentro_area_entrega()`
- ✅ Rate limit: 100 req/min global

**Risco:** 🟢 Baixo (input validado)

---

#### 3. `GET /api/area?cep=01310100`
```typescript
// Mesmo que /api/neighborhoods
GET /api/area?cep=01310100
// (alias, mesmo endpoint)
```

**Proteção:** Idêntica a `/api/neighborhoods`

**Risco:** 🟢 Baixo

---

#### 4. `GET/POST /api/auth/[...all]`
```typescript
// Exemplo:
POST /api/auth/signin
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "senha-forte-12+"
}
```

**Proteção:**
- ✅ Better Auth valida (10+ rotas auth)
- ✅ Rate limit: 5 signin/min, 5 signup/hora
- ✅ Email verification: condicional (se RESEND_API_KEY)
- ✅ Password: ≥ 12 caracteres
- ✅ Argon2id hashing

**Risco:** 🟢 Baixo a Médio (rate limit em memória até PR-4)

---

### Rotas Protegidas (Autenticadas)

Todas as demais rotas:
- ✅ Require valid session cookie
- ✅ Redirect para login se sem cookie
- ✅ Validação de papel em Server Actions (`exigirDono()`)

Exemplo:
```typescript
// POST /assinar — Server Action
export async function assinar_plano(formData: FormData) {
  const usuario = await usuarioAtual();
  if (!usuario) throw new Error('Não autenticado');  // ← Valida sessão
  
  // Cria assinatura vinculada ao usuário
  const resultado = await db.query(
    'INSERT INTO assinaturas (cliente_id, plano) VALUES ($1, $2)',
    [usuario.cliente_id, formData.get('plano')]
  );
}
```

---

## Disaster Recovery

### Restore do Banco

#### Cenário 1: Corrupção de Dados

```bash
# 1. Perceber que dados estão corrompidos
# 2. Neon: Point-in-Time Recovery (PITR)

# Neon Console → Branches → main → Restore to a past point
# Escolher: timestamp antes da corrupção
# Novo branch: "main-restored"

# 3. Validar dados no restored branch
pnpm db:test --database-url=postgresql://...main-restored

# 4. Se OK, failover:
# - Parar aplicação (AWS Lambda, Next.js deployment)
# - Deletar branch "main" (ou renomear)
# - Renomear "main-restored" → "main"
# - Reiniciar aplicação

# 5. Tempo de RTO: ~15 min (parada + failover)
```

#### Cenário 2: Perda Total (Neon down)

```bash
# Neon oferece multi-region redundancy (paid tier)
# Se não tiver:

# 1. Backup manual diário
pg_dump postgresql://... | gzip > backup-2026-10-05.sql.gz

# 2. Restore via:
gunzip < backup-2026-10-05.sql.gz | psql postgresql://...

# 3. Aplicar migrações faltantes (se restore é de ontem)
pnpm db:migrar

# 4. Validar: pnpm teste:banco
```

#### Cenário 3: Rollback de Migration Problemática

```bash
# 1. Última migration quebrou

# 2. Rollback local (desenvolvimento)
pnpm db:reverter

# 3. Verificar: migration anterior passa testes?
pnpm teste:banco

# 4. Se sim, deploy do rollback para produção
# 5. Tempo de RTO: ~5 min

# Ver: packages/database/migrations/
# Cada arquivo tem UP e DOWN (reversível)
```

---

## Runbook de Incident

### Alerta: Possível Vazamento de DATABASE_ADMIN_URL

```
⏰ Descoberta: [timestamp]
📍 Fonte: Git history, logs, screenshot, etc
🚨 Severidade: CRÍTICA

AÇÃO IMEDIATA (< 5 min):
1. Confirmar: URL estava em git? SIM/NÃO
2. Se SIM:
   - git log --all | grep -i "DATABASE_ADMIN"
   - Contar commits expostos

3. Revogar acesso:
   - Neon Console → Roles → neondb_owner → Revoke all
   - Criar novo role: neondb_owner_v2
   - Atualizar DATABASE_ADMIN_URL

4. Reescrever histórico (git):
   git filter-repo --invert-paths --path .env
   git push --force-with-lease
   
VALIDAÇÃO (próximos 15 min):
- Executar: pnpm seguranca (detecta se secrets ainda expostos)
- Rodar testes: pnpm teste:banco
- Verificar CI: passa?

COMUNICAÇÃO:
- Avisar: Não houve acesso não autorizado identificado? (verificar logs Neon)
- Registrar em postmortem
```

### Alerta: Ataque de Força Bruta em Sign-in

```
⏰ Descoberta: Logs mostram 100+ failed signin de mesmo IP
📍 IP: [IP do atacante]
🚨 Severidade: MÉDIA

AÇÃO IMEDIATA:
1. Rate limit está funcionando?
   - Verificar: 5 req/min bloqueados? SIM/NÃO
   
2. Se NÃO:
   - PR-4 talvez não foi deployado
   - Atacante está brute-forcing com múltiplos IPs
   
3. Mitigação:
   - Bloquear IP (firewall/WAF) — [não configurado, delegado a provedor]
   - Aumentar limite de sign-in? (em PR-4: 5→3 req/min)
   
VALIDAÇÃO:
- Confirmar: nenhuma senha foi descoberta? (verificar logs de tentativas)
- Listar usuários com última mudança de senha há > 6 meses
- Notificar: "Detectamos ataque brute-force, revise sua senha"
```

### Alerta: SQL Injection Detectado

```
⏰ Descoberta: WAF ou manual testing
🚨 Severidade: CRÍTICA

AÇÃO IMEDIATA:
1. Confirmar: query foi executada?
   - Logs do PostgreSQL: SELECT pg_read_file('...') ?
   
2. Se SIM:
   - Neon: revoke current role permission, restrict
   - RLS: verificar que vazamento foi contido (SIM/NÃO)
   
3. Pausar aplicação:
   - Se é code flaw: pnpm build (valida tipos)
   - Se é input: deploy patch com validação Zod

VALIDAÇÃO:
- Verificar: logs RLS bloquearam acesso a outros clientes? (SIM/NÃO)
- Executar: git blame no arquivo vulnerável
- Adicionar: teste SQL para impedir regressão
```

---

## Auditoria e Compliance

### Log de Auditoria

Tabela `auditoria` rastreia **todas** as mudanças em 8 tabelas:

```sql
CREATE TABLE auditoria (
  id BIGSERIAL PRIMARY KEY,
  tabela TEXT NOT NULL,       -- clientes, assinaturas, etc
  acao TEXT NOT NULL,         -- INSERT, UPDATE, DELETE
  antes JSONB,                -- valores antes da mudança
  depois JSONB,               -- valores depois da mudança
  usuario_id UUID,            -- quem fez (NULL se app_anon)
  papel TEXT,                 -- papel do usuário (usuario/dono)
  criado_em TIMESTAMP         -- quando (São Paulo timezone)
);
```

#### Exemplo: Auditoria de Cancelamento

```sql
-- INSERT em auditoria quando assinatura é cancelada:
{
  "tabela": "assinaturas",
  "acao": "UPDATE",
  "antes": {
    "id": "assin_123",
    "cliente_id": "cliente_456",
    "status": "ativa",
    "cancelada_em": null
  },
  "depois": {
    "id": "assin_123",
    "cliente_id": "cliente_456",
    "status": "ativa",
    "cancelada_em": "2026-10-05T14:30:00-03:00"
  },
  "usuario_id": "user_789",
  "papel": "usuario",
  "criado_em": "2026-10-05T14:30:00-03:00"
}
```

#### Consultar Auditoria

```sql
-- Últimas 10 mudanças de um cliente:
SELECT * FROM auditoria
WHERE dados->>'cliente_id' = 'cliente_456'
ORDER BY criado_em DESC
LIMIT 10;

-- Todas as ações de um usuário em um dia:
SELECT * FROM auditoria
WHERE usuario_id = 'user_789'
  AND criado_em::date = '2026-10-05'
ORDER BY criado_em;
```

### Verificações de Segurança Automáticas (CI)

Toda vez que faz push:

```yaml
# .github/workflows/ci.yml
seguranca:
  - bash scripts/verificar-segredos.sh  # Detecta secrets vazados
  - pnpm audit --audit-level=high      # Vulnerabilidades de deps
  - pnpm dlx depcheck                  # Deps desnecessárias

tipos:
  - pnpm typecheck                     # TypeScript tipo-seguro
  - pnpm test                          # Unit tests
  - pnpm teste:banco (se DATABASE_TEST_URL)  # SQL tests
```

### Checklist: Antes de Lançar em Produção

- [ ] SEGURANCA.md revisado (este arquivo)
- [ ] `pnpm seguranca` passa (0 secrets)
- [ ] `pnpm teste:banco` passa (14/14 suites)
- [ ] `pnpm typecheck` sem erros
- [ ] Rate limit em DB (PR-4 deployado)
- [ ] CSP headers ativos (PR-5, mode: report-only)
- [ ] Email verification configurado (RESEND_API_KEY)
- [ ] 2FA não é bloqueador (road para futuro)
- [ ] Backup diário do banco configurado
- [ ] Logs centralizados (opcional, não implementado)
- [ ] Runbook documentado e testado (este arquivo)

---

## 📚 Referências Cruzadas

- **DECISOES.md** — Decisões de negócio + segurança
- **CLAUDE.md** — Guia técnico (estrutura, conventions)
- **README.md** — Setup e instruções
- **packages/database/src/auth/papel.ts** — Implementação de roles
- **scripts/verificar-segredos.sh** — Detecção de secrets
- **.github/workflows/ci.yml** — CI/CD configuration

---

## 📝 Histórico de Revisão

| Data | Versão | Mudança | Autor |
|------|--------|---------|-------|
| 2026-10-05 | 1.0 | Documento criado | Claude Haiku 4.5 |
| — | 1.1 | (pendente: PR-4 rate limit DB) | — |
| — | 1.2 | (pendente: PR-5 CSP enforced) | — |

---

**Preparado por:** Claude Haiku 4.5  
**Data:** 2026-10-05  
**Próxima revisão:** 2027-10-05 ou após mudança crítica
