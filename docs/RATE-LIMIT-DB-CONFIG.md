# 🔒 Rate Limit em DB — Configuração Better Auth

**Documento de Referência:** Como configurar Better Auth para usar DB em vez de memória  
**Data:** 2026-10-05  
**Relates to:** PR-4 (Rate Limit em DB)

---

## Problema: Rate Limit em Memória

```
┌─────────────────┐
│  Instance 1     │
│  (memória)      │  Rate limit local: 5 req/min
│  IP: 192.0.2.1  │  Bloqueia após 5
└─────────────────┘
         │
    Atacante faz 5 req → bloqueado

┌─────────────────┐
│  Instance 2     │  ← Nueva instância (serverless)
│  (memória nova) │  Rate limit local: 0/5 (contador zerado!)
│  (outro IP)     │  Atacante faz 5 req → bloqueado
└─────────────────┘
         │
    Atacante faz 5 req → NÃO bloqueado! ⚠️
```

**Resultado:** Em serverless, límite é frouxo (múltiplas instâncias = múltiplos contadores).

---

## Solução: Rate Limit em DB

```
┌─────────────────┐         ┌─────────────────┐
│  Instance 1     │         │  Instance 2     │
│  serverless     │         │  serverless     │
└────────┬────────┘         └────────┬────────┘
         │                          │
         └──────────┬───────────────┘
                    │
              ┌──────▼──────┐
              │   Postgres  │
              │  (DB)       │
              │ rateLimit   │
              │   table     │
              └─────────────┘

Contador sincronizado: Instance 1 e 2 consultam o mesmo registro.
Limite global: 5 req/min em QUALQUER instância.
Atacante com múltiplos IPs: cada IP tem seu próprio contador.
```

---

## Configuração Better Auth

### Passo 1: Aplicar Migration

```bash
pnpm db:migrar:teste  # Cria tabela rateLimit + função verificar_rate_limit()
```

### Passo 2: Atualizar Better Auth Config

**Arquivo:** `packages/database/src/auth.ts`

```typescript
import { betterAuth } from "better-auth";
import { db } from "./acesso";

export const auth = betterAuth({
  database: {
    db: db,  // ← Usar objeto db (pool PostgreSQL)
  },
  
  // ✅ NOVO: Rate limit em banco de dados
  rateLimit: {
    enabled: true,
    windowMs: 60 * 1000,        // 60 segundos
    max: 100,                   // 100 requisições por janela
    storage: 'database',        // ← USAR BANCO (não memória)
    // skipSuccessfulRequests: false,  // Contar bem-sucedidas
    // skipFailedRequests: false,      // Contar falhadas
  },

  // ✅ NOVO: Sign-in específico (mais restritivo)
  signInRateLimit: {
    enabled: true,
    windowMs: 60 * 1000,    // 60 segundos
    max: 5,                 // 5 tentativas por janela
    // storage: 'database'  // Better Auth herda de rateLimit.storage
  },

  // ✅ NOVO: Sign-up específico (ainda mais restritivo)
  signUpRateLimit: {
    enabled: true,
    windowMs: 3600 * 1000,  // 1 hora
    max: 5,                 // 5 sign-ups por hora
    // storage: 'database'  // Better Auth herda de rateLimit.storage
  },

  // ... resto da configuração Better Auth
});
```

### Passo 3: Variáveis de Ambiente

**Arquivo:** `.env`

```bash
# Banco de dados (já deve estar preenchido)
DATABASE_URL=postgresql://app_servidor:...
DATABASE_ADMIN_URL=postgresql://neondb_owner:...

# Rate limit: compartilhado com DATABASE_URL (padrão)
# ou use DATABASE_RATE_LIMIT_URL se quiser connection string separada:
# DATABASE_RATE_LIMIT_URL=postgresql://app_servidor:...
```

**Arquivo:** `.env.example`

```bash
# ─── Rate Limit em DB (usa DATABASE_URL se não definido) ─────────────
# DATABASE_RATE_LIMIT_URL=postgresql://app_servidor:SENHA@ep-exemplo...
# Se vazio, usa DATABASE_URL. Pool pequeno (4 conexões) é suficiente.
```

---

## Verificação: Rate Limit Está Funcionar

### SQL Direto (desenvolvedores)

```sql
-- Ver registros de rate limit atuais
select * from rateLimit where reset_at > now();

-- Exemplo de resultado:
-- ip         | endpoint            | count | reset_at
-- 192.0.2.1  | /api/auth/signin    |     3 | 2026-10-05 14:30:00
-- 192.0.2.1  | /api/auth/signup    |     1 | 2026-10-05 14:35:00
-- 203.0.113.2| (null)              |    45 | 2026-10-05 14:31:00

-- Testar função diretamente:
select verificar_rate_limit(
  p_ip => '192.0.2.99',
  p_endpoint => '/api/auth/signin',
  p_limite_por_janela => 5,
  p_janela_segundos => 60
);
-- Retorna: false (não bloqueado, primeira requisição)
```

### No App (usuário final)

1. Abra navegador (ou curl)
2. Tente fazer 5 sign-ins com senha errada (mesmo IP)
3. 6ª tentativa: erro de "Too many requests" (429)
4. Aguarde 60s, tente novamente: funciona

---

## Limpeza Automática

A tabela `rateLimit` é mantida enxuta automaticamente:
- Trigger `limpar_rateLimit_expirados_tg` roda ANTES de INSERT/UPDATE
- Deleta automaticamente registros com `reset_at < now()`
- Sem intervenção manual

**Monitorar limpeza:**

```sql
-- Ver quantos registros "vivos" existem (não expirados)
select count(*) from rateLimit where reset_at > now();

-- Ver registros de até 1 hora atrás (incluindo expirados)
select count(*) from rateLimit where reset_at > now() - interval '1 hour';
```

---

## Configuração Avançada

### Limites Personalizados por Endpoint

```typescript
// Better Auth não oferece limites por endpoint nativamente.
// Mas você pode usar middleware custom:

export async function rateLimitMiddleware(req: Request) {
  const ip = req.ip || 'unknown';
  const endpoint = new URL(req.url).pathname;
  
  let limite = 100;
  let janela = 60;
  
  // Limites específicos
  if (endpoint === '/api/auth/signin') {
    limite = 5;
    janela = 60;  // 5 por minuto
  } else if (endpoint === '/api/auth/signup') {
    limite = 5;
    janela = 3600;  // 5 por hora
  }
  
  const bloqueado = await db.query(
    'select verificar_rate_limit($1, $2, $3, $4)',
    [ip, endpoint, limite, janela]
  );
  
  if (bloqueado.rows[0][0]) {
    return new Response('Too many requests', { status: 429 });
  }
}
```

### Rate Limit por Usuário Autenticado

Para Server Actions críticas, você pode limitar por usuário em vez de IP:

```typescript
// packages/database/src/auth/rate-limit-server-action.ts
export async function rateLimitServerAction(
  { limit, period }: { limit: number; period: string },
  handler: (data: any) => Promise<any>
) {
  return async (data: any) => {
    const usuario = await usuarioAtual();
    if (!usuario) throw new Error('Não autenticado');
    
    const bloqueado = await db.query(
      'select verificar_rate_limit($1, $2, $3, $4)',
      [
        usuario.id,  // User ID em vez de IP
        'server_action_critica',
        limit,
        periodToSeconds(period)
      ]
    );
    
    if (bloqueado.rows[0][0]) {
      throw new Error('Limite de requisições atingido');
    }
    
    return handler(data);
  };
}
```

---

## Troubleshooting

### Rate Limit não está funcionando

**Problema:** Ainda consigo fazer muitas requisições  
**Solução:**
1. Verificar: `select * from rateLimit` — tabela existe?
2. Verificar: `pnpm db:migrar:teste` — migration foi aplicada?
3. Verificar: `.env` — DATABASE_RATE_LIMIT_URL está preenchido?
4. Reiniciar aplicação (limpar cache de memória)

### Registro expirado não foi deletado

**Problema:** Tabela rateLimit está crescendo  
**Solução:**
1. Verificar trigger: `select * from pg_trigger where tgrelname = 'rateLimit'`
2. Forçar limpeza: `delete from rateLimit where reset_at < now();`
3. Monitore com: `select count(*) from rateLimit where reset_at < now();`

### Rate limit muito restritivo

**Problema:** Usuários legítimos estão sendo bloqueados  
**Solução:**
1. Aumentar `max` em Better Auth config (ex: 100 → 200)
2. Aumentar `windowMs` (ex: 60s → 120s)
3. Verificar: um cliente legítimo tem IP único, ou múltiplos IPs (proxy)?

---

## Monitoramento (Grafana, DataDog, etc)

```sql
-- Queries úteis para dashboards

-- Taxa de bloqueio por IP
select ip, count(*) as bloqueios, max(reset_at) as ultimo_reset
from rateLimit
where reset_at > now() - interval '1 hour'
group by ip
order by bloqueios desc;

-- Endpoints mais limitados
select endpoint, count(*) as eventos
from rateLimit
where reset_at > now() - interval '1 hour'
group by endpoint
order by eventos desc;

-- Crescimento da tabela (monitorar se está vazando memória)
select count(*) as registros_ativos from rateLimit where reset_at > now();
```

---

## Referências

- **Better Auth Docs:** https://www.better-auth.com/docs/concepts/session-management
- **Postgres RLS + Rate Limit:** Rate limit via trigger é padrão (ex: Django REST Framework)
- **SEGURANCA.md:** Cenário 3 — Exploração via Rate Limit

---

**Status:** 📝 Documento de referência para configuração Better Auth  
**Próximo:** Aplicar em PR-4, testar, e documentar em SEGURANCA.md

---

**Preparado por:** Claude Haiku 4.5  
**Data:** 2026-10-05
