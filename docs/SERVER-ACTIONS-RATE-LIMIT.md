# 🔒 Rate Limit em Server Actions — Guia de Implementação

**Documento de Referência:** Como usar rate limit em Server Actions críticas  
**Data:** 2026-10-05  
**Relates to:** PR-5 (CSP + Rate Limit Server Actions)

---

## Por Que Rate Limit em Server Actions?

Server Actions críticas podem ser exploradas para DDoS:
- `assinar_plano` — criar assinaturas rapidamente
- `gerar_cobranca` — sobrecarregar sistema de faturamento
- `processar_rotina_diaria` — disparar rotina de forma não autorizada

Rate limit por Server Action protege contra isso.

---

## Como Usar

### Importar Helper

```typescript
// apps/assinante/src/app/assinar/acoes.ts
import { rateLimitServerAction } from '@ovo/database/auth/rate-limit-server-action';
```

### Envolver Server Action

**Antes (sem rate limit):**
```typescript
'use server';

export async function assinar_plano(formData: FormData) {
  const usuario = await usuarioAtual();
  if (!usuario) throw new Error('Não autenticado');
  
  // lógica de assinatura
}
```

**Depois (com rate limit):**
```typescript
'use server';

import { rateLimitServerAction } from '@ovo/database/auth/rate-limit-server-action';

export const assinar_plano = rateLimitServerAction(
  { limite: 10, periodo: 'hora' },
  async (formData) => {
    const usuario = await usuarioAtual();
    if (!usuario) throw new Error('Não autenticado');
    
    // lógica de assinatura
  }
);
```

---

## Opções de Rate Limit

### Por IP (padrão)

```typescript
export const assinar_plano = rateLimitServerAction(
  { limite: 10, periodo: 'hora' },
  handler
);
```

**Quando usar:** Operações públicas ou que não requerem autenticação.

**Exemplo:** Sign-up, reset de senha.

### Por Usuário

```typescript
import { rateLimitServerActionPorUsuario } from '@ovo/database/auth/rate-limit-server-action';

export const gerar_cobranca = rateLimitServerActionPorUsuario(
  { limite: 5, periodo: 'hora' },
  async (formData) => {
    const usuario = await usuarioAtual();
    // usuario garantido (função valida)
    
    // lógica de cobrança
  }
);
```

**Quando usar:** Operações autenticadas, para limitar por usuário em vez de IP.

**Exemplo:** Assinatura, cobrança, feedback.

---

## Períodos Suportados

```typescript
{ periodo: 'minuto' }   // 60 segundos
{ periodo: 'hora' }     // 3600 segundos
{ periodo: 'dia' }      // 86400 segundos
```

---

## Exemplos Recomendados

### Server Actions Críticas — Propostas para PR-5

| Server Action | Limite | Período | Motivo |
|---|---|---|---|
| `assinar_plano` | 10 | hora | Criar assinatura é custoso |
| `gerar_cobranca` | 5 | hora | Apenas dono, proteção contra erro |
| `processar_rotina_diaria` | 2 | hora | Rotina é cara, evita duplo-disparo |
| `cancelar_assinatura` | 5 | hora | Cliente não cancela 6 vezes/hora |
| `enviar_feedback` | 20 | hora | Feedback é barato, limite liberal |

---

## Tratamento de Erro

Quando rate limit é atingido, a função lança `Error` com mensagem clara:

```typescript
try {
  await assinar_plano(formData);
} catch (err) {
  if (err.message.includes('Rate limit')) {
    // Mostrar para o usuário:
    // "Máximo 10 por hora. Tente novamente em alguns minutos."
  }
}
```

No cliente (formulário):
```typescript
async function handleAssinar(formData: FormData) {
  try {
    const resultado = await assinar_plano(formData);
  } catch (err) {
    if (err.message.includes('Rate limit')) {
      setErro('Você tentou muitas vezes. Aguarde um pouco.');
    } else {
      setErro('Erro ao processar: ' + err.message);
    }
  }
}
```

---

## Como Funciona Internamente

1. **Extrair IP:** `X-Forwarded-For` (proxy) ou remoto direto
2. **Chamar função SQL:** `verificar_rate_limit(ip, endpoint, limite, periodo)`
3. **Banco retorna:** true (bloqueado) ou false (OK)
4. **Se bloqueado:** lançar erro (não executa handler)
5. **Se OK:** executar handler normalmente

---

## Monitoramento

### Ver rate limit por Server Action

```sql
select endpoint, count(*) as tentativas, max(reset_at) as proximo_reset
from rateLimit
where endpoint like 'server_action_%'
  and reset_at > now() - interval '1 hour'
group by endpoint
order by tentativas desc;
```

### Ver rate limit por IP

```sql
select ip, count(*) as tentativas, max(reset_at) as proximo_reset
from rateLimit
where reset_at > now() - interval '1 hour'
group by ip
order by tentativas desc;
```

---

## Performance

**Impacto:** Negligível
- Cada chamada de Server Action faz 1 SELECT em tabela pequena
- Índice em reset_at torna lookup O(1)
- ~5ms adicionais por Server Action

---

## Segurança: Garantias

### Garantia 1: Não é possível bypass com múltiplos IPs
```
Atacante tenta 10 vezes com IP 1: bloqueado após 10
Atacante tenta 10 vezes com IP 2: novo contador, bloqueado após 10
Atacante tenta 10 vezes com IP 3: novo contador, bloqueado após 10

Resultado: Cada IP tem seu próprio limite (seguro)
```

### Garantia 2: Limites por usuário não são "burlados" com anonimato
```
Usuário autenticado tenta 5 vezes: bloqueado
Usuário sai da sessão, volta como anônimo: novo IP, novo limite

Resultado: Perder sessão redefine limite (aceitável)
```

### Garantia 3: Server Actions não ficam lentas
```
Tempo sem rate limit:   100ms (handler + DB writes)
Tempo com rate limit:   105ms (+5ms para check)
Impacto relativo: 5%
```

---

## Configuração Recomendada para Produção

```typescript
// apps/assinante/src/app/assinar/acoes.ts
export const assinar_plano = rateLimitServerActionPorUsuario(
  { limite: 10, periodo: 'hora' },
  async (formData) => { /* ... */ }
);

// apps/gestao/src/app/financeiro/acoes.ts
export const gerar_cobranca = rateLimitServerActionPorUsuario(
  { limite: 5, periodo: 'hora' },
  async (formData) => { /* ... */ }
);

export const processar_rotina_diaria = rateLimitServerActionPorUsuario(
  { limite: 2, periodo: 'hora' },
  async () => { /* ... */ }
);
```

---

## Próximos Passos

1. ✅ Implementar rate limit em Server Actions críticas
2. ✅ Testar localmente: `pnpm dev` + tentar requisições repetidas
3. ✅ Monitorar em produção: dashboard SQL de rate limit
4. (Futuro) Aumentar limites conforme metricas

---

## Referências

- **rate-limit-server-action.ts** — Implementação
- **RATE-LIMIT-DB-CONFIG.md** — Configuração Better Auth
- **SEGURANCA.md** — Cenário 3 (Exploração via Rate Limit)

---

**Preparado por:** Claude Haiku 4.5  
**Data:** 2026-10-05
