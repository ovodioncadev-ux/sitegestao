# 📱 Funcionalidades do Site (apps/site)

## Visão Geral

Landing page SPA responsiva em **Next.js 15 + React 19** com integração ao backend. Tudo em **português (pt-BR)**. Sem autenticação própria; redirecionamento para `/entrar` do assinante apenas por CTA.

**URL:** `http://localhost:3002`  
**Tipo:** Client Component (`'use client'`) com dados dinâmicos via fetch HTTP  
**Tokens CSS:** importa `@ovo/ui/tokens.css`

---

## 🗺️ Mapa Visual da Página

```
┌─────────────────────────────────────┐
│        NAVBAR (Sticky)              │
│ Ovo di Onça | Menu scroll-spy | CTA│
└─────────────────────────────────────┘
│                                     │
│  HERO SECTION                       │
│  "Ovos caipiras, da fazenda..."     │
│  [Botão "Assinar agora"]            │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  PLANS SECTION (#planos)            │
│  [Plano Semanal] [Quinzenal] [Mensal]
│  Mostra: preço, frescor, frete,     │
│          desconto 1º mês, features  │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  COMPARISON TABLE (#comparativo)    │
│  [Tabela com 5 comparações]         │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  NEIGHBORHOOD SECTION (#entrega)    │
│  [Search] [Dropdown de bairros]     │
│  22 bairros de BH                   │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  FAQ SECTION (#faq)                 │
│  [6 perguntas + respostas]          │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  FOOTER                             │
│  WhatsApp link, direitos            │
│                                     │
└─────────────────────────────────────┘

OVERLAY (quando checkout aberto):
┌─────────────────────────────────────┐
│   CHECKOUT MODAL                    │
│   [Nome] [Telefone] [Bairro]        │
│   [Cancelar] [Continuar no WhatsApp]│
└─────────────────────────────────────┘
```

---

## 📋 Funcionalidades por Seção

### 1. **NAVBAR** (Sticky no topo)
- **Menu com scroll-spy:** Navbar muda cor/peso dos itens conforme seção em viewport
  - Links para: `#planos`, `#comparativo`, `#entrega`, `#faq`
- **Logo:** "Ovo di Onça" (link para `#inicio`)
- **CTA "Falar no WhatsApp":** Abre o link de `@ovo/config/whatsapp` (`wa.me/553125167561`, D12)
- **Implementação:** `components/Navbar.tsx`
  - `IntersectionObserver` monitora 4 seções
  - Muda `aria-current` do link ativo
  - Cores: texto suave (padrão) → ouro escuro (ativo)

### 2. **HERO** (Seção inicial, id="inicio")
- **Título:** "Ovos caipiras, da fazenda direto pra sua casa"
- **Subtítulo:** "Máx. 7 dias entre a colheita e a entrega. Frete grátis na área atendida."
- **CTA "Assinar agora":** Abre checkout modal com plano `semanal` pré-selecionado
- **Implementação:** `components/Hero.tsx`

### 3. **PLANS SECTION** (id="planos")
- **Dados dinâmicos:** Busca `/api/plans` (público, `app_anon`)
  - Carrega ao montar; mostra "Carregando..." ou erro
  - Mapeia `intervalo_dias` (7/15/30) → `PlanId` (semanal/quinzenal/mensal)
- **3 planos exibidos em cards:**
  - **Semanal (7 dias):** R$164/mês, badge "Mais escolhido", destaque
  - **Quinzenal (15 dias):** R$82/mês
  - **Mensal (30 dias):** R$41/mês
- **Informações por plano:**
  - Preço mensal em reais
  - Frescor máximo (7 dias)
  - Frete (grátis, R$0)
  - Desconto 1º mês (10%)
  - Lista de features (hardcoded, 4 itens por plano)
- **Ação:** Clique em plano abre `CheckoutModal`
- **Implementação:** `components/PlansSection.tsx`, `hooks/usePlanos.ts`

### 4. **COMPARISON TABLE** (id="comparativo")
- **Tabela com 5 linhas de comparação:**
  1. Intervalo de entrega (7/15/30 dias)
  2. Frescor máximo (7 dias em todas)
  3. Frete (grátis em todas)
  4. Desconto 1º mês (10% em todas)
  5. Status (Ativo em todas)
- **Dados:** Hardcoded (não vem da API; independente)
- **Implementação:** `components/ComparisonTable.tsx`
  - Constante `COMPARISON_ROWS` com 5 objetos

### 5. **NEIGHBORHOOD SECTION** (id="entrega", anteriormente "entrega")
- **Dados dinâmicos:** Busca `/api/neighborhoods` (público)
  - Lista de 22 bairros de BH
  - Estado: `{name, isServed: true}`
- **Funcionalidades:**
  1. **Input de busca:** Filtro local (case-insensitive) nos 22 bairros
  2. **Dropdown/Lista de tags:** Mostra bairros encontrados ou todos
  3. **Validação de bairro:** Usado pelo checkout para validar entrada
- **Implementação:** `components/NeighborhoodSection.tsx`, `hooks/useBairros.ts`
  - Busca ao montar
  - Filtro com `name.toLowerCase().includes(q.toLowerCase())`

### 6. **FAQ SECTION** (id="faq")
- **6 perguntas + respostas sobre o serviço:**
  1. "Como funciona a assinatura?" → Explicação de ciclos
  2. "Posso pausar ou cancelar?" → Sim, sem penalidade
  3. "Como é o pagamento?" → PIX manual
  4. "Qual é a área de entrega?" → 22 bairros de BH
  5. "Os ovos são frescos?" → Máx 7 dias
  6. "Posso alterar meu plano?" → Sim, a qualquer momento
- **Dados:** Hardcoded (não muda via API)
- **Implementação:** `components/FaqSection.tsx`
  - Constante `FAQ_ITEMS` com 6 objetos

### 7. **FOOTER**
- **Informações:**
  - Logo "Ovo di Onça"
  - Links: `#planos`, `#comparativo`, `#faq`
- **CTA:** Botão "Falar no WhatsApp" → o link de `@ovo/config/whatsapp` (`wa.me/553125167561`, D12)
- **Copyright:** "© 2026 Ovo di Onça. Todos os direitos reservados."
- **Implementação:** `components/Footer.tsx`

### 8. **CHECKOUT MODAL** (Overlay)
- **Acionado por:** Clique em plano ou "Assinar agora" no hero
- **Campos obrigatórios:**
  1. **Nome:** Mín. 3 caracteres (validação no cliente)
  2. **Telefone:** Formato (31) 9xxxx-xxxx ou (31) 9xxxxxxxx (máscara + validação)
  3. **Bairro:** Dropdown com 22 bairros (validado contra lista do servidor)
- **Validações:**
  - Nome: `nome.trim().length >= 3`
  - Telefone: `telefoneValido(telefone)` (10 ou 11 dígitos com DDD)
  - Bairro: Deve estar na lista do servidor (isolamento)
- **Fluxo:**
  1. Usuário preenche e clica "Continuar no WhatsApp"
  2. Valida no cliente (se houver erro, mostra lista)
  3. POST para `/api/subscriptions` do assinante (requer autenticação)
     - **BUG:** Site é anônimo, mas API exige login. Falha com CORS.
  4. Se OK: abre WhatsApp com resumo + redireciona para `/entrar`
  5. Se erro: mostra mensagem de erro
- **Estado:** Loading ("Enviando..."), sucesso (toast 5s), erro (mostra msg)
- **Implementação:** `components/CheckoutModal.tsx`
  - `useActionState` com `startTransition`
  - Não zera campos em erro (UX)
  - Limpa em sucesso
- **Bug known:** Envia `plan.priceCents` em vez de `plan.id` → API rejeita como "Plano inválido"

---

## 🔌 Integração com Backend

### Endpoints Chamados

| Endpoint | Método | Autenticação | Resposta | Implementação |
|---|---|---|---|---|
| `/api/plans` | GET | app_anon | `{planos: [{id, nome, intervalo_dias, priceCents, …}]}` | `PlansSection`, `usePlanos()` |
| `/api/neighborhoods` | GET | app_anon | `{bairros: [{name, isServed}]}` | `NeighborhoodSection`, `useBairros()` |
| `/api/subscriptions` | POST | app_usuario (❌ BUG) | `{ok, mensagem}` | `CheckoutModal.handleSubmit()` |

### Cliente HTTP

**Arquivo:** `src/lib/api.ts`

```typescript
const API_BASE = 
  typeof window === 'undefined' 
    ? process.env.NEXT_PUBLIC_URL_ASSINANTE || 'http://localhost:3001'
    : window.location.hostname === 'localhost'
      ? 'http://localhost:3001'
      : '/api'  // ❌ BUG: gera /api/api/plans em produção

export async function buscarPlanos(): Promise<Plan[]>
export async function buscarBairros(): Promise<Neighborhood[]>
export async function criarAssinatura(plano_id: number, bairro: string): Promise<{ok: boolean}>
```

- **CORS:** Fixo em `localhost:3002`; sem origem de produção
- **Cookies:** `credentials: 'include'` (tenta enviar sessão Better Auth)
- **Erro:** Genérico "Erro ao carregar" ou "Erro ao criar assinatura"

---

## 🎨 Estilos e Tokens

**Arquivo:** `src/app/globals.css` (mínimo)  
**Tokens:** Importados de `@ovo/ui/tokens.css`

**Variáveis de token usadas:**
- Cores: `--cor-fundo`, `--cor-ouro`, `--cor-ouro-app`, `--cor-erro`, `--cor-sucesso`, `--cor-whatsapp`
- Espaçamento: `--esp-1` a `--esp-24` (2px até 140px, escala 4px)
- Tamanho de texto: `--texto-pequeno`, `--texto-medio`, `--texto-grande`, `--texto-hero`
- Fonts: `--fonte-titulo` (Aclonica), `--fonte-corpo` (Poppins)
- Layout: `--largura-conteudo`, `--altura-controle`, `--alvo-toque`
- Raios: `--raio-controle`, `--raio-card`
- Sombras: `--sombra-flutuante`

**Componentes usam `style={{}}` inline** (sem classes Tailwind).

---

## 📊 Tipos

**Arquivo:** `src/types.ts`

```typescript
type PlanId = 'semanal' | 'quinzenal' | 'mensal'

type Plan = {
  id: PlanId
  name: string
  intervalDays: number
  priceCents: number
  freshnessMaxDays: number
  freightCents: number
  firstMonthDiscountPct: number
  features: string[]
  highlighted?: boolean
  badge?: string
}

type Neighborhood = {
  name: string
  isServed: boolean
}
```

---

## 🐛 Bugs Conhecidos

1. **CheckoutModal envia preço em vez de plano_id**
   - Linha: `apps/site/src/components/CheckoutModal.tsx:60`
   - Causa: `criarAssinatura(plan.priceCents, bairro)` deveria ser `criarAssinatura(plan.id, bairro)`
   - Efeito: API rejeita porque 16400, 8200 ou 4100 não são IDs válidos de plano

2. **Checkout exige autenticação mas site é anônimo**
   - Problema: `/api/subscriptions` requer sessão `app_usuario`
   - Site: sem login, so anônimo
   - Cookie: Better Auth é do assinante (`:3001`), não é enviado do site (`:3002`) por CORS
   - Efeito: POST falha com "not authenticated" ou CORS preflight

3. **API_BASE em produção gera `/api/api/...`**
   - Condição: `window.location.hostname !== 'localhost'` muda para `/api`
   - Efeito: `/api/plans` vira `/api/api/plans`

4. **Lista de bairros hardcoded em dois lugares**
   - `apps/assinante/src/app/api/neighborhoods/route.ts`
   - `apps/assinante/src/app/api/subscriptions/route.ts`
   - Sem sincronização; se um muda, o outro fica desatualizado

---

## 🔄 Estado da Página

- **Sem persistência:** Tudo fica em memória (hooks `useState`)
- **Sem autenticação:** Redirecionamento para `/entrar` do assinante via CTA "Assinar agora" após sucesso do checkout
- **Sem histórico de compras:** O site é apenas o ponto de entrada

---

## 📦 Estrutura de Arquivos

```
apps/site/
├── src/
│   ├── app/
│   │   ├── layout.tsx              # Metadata, robots: noindex, importa tokens
│   │   └── page.tsx                # Renderiza <SiteApp>
│   ├── components/
│   │   ├── SiteApp.tsx             # Container principal, state do checkout + toast
│   │   ├── Navbar.tsx              # Scroll-spy, menu
│   │   ├── Hero.tsx                # CTA "Assinar agora"
│   │   ├── PlansSection.tsx        # Busca /api/plans, cards dinâmicos
│   │   ├── ComparisonTable.tsx     # Tabela estática
│   │   ├── NeighborhoodSection.tsx # Busca /api/neighborhoods, search
│   │   ├── FaqSection.tsx          # FAQ estática
│   │   ├── CheckoutModal.tsx       # Modal overlay, POST /api/subscriptions
│   │   └── Footer.tsx              # Footer, WhatsApp link
│   ├── hooks/
│   │   ├── usePlanos.ts            # Busca /api/plans, mapeia intervalo_dias → PlanId
│   │   └── useBairros.ts           # Busca /api/neighborhoods
│   ├── lib/
│   │   ├── api.ts                  # Cliente HTTP (buscar, criar assinatura)
│   │   └── formatar.ts             # formatarReais, mascararTelefone
│   └── types.ts                    # Plan, PlanId, Neighborhood
├── next.config.ts                  # Transpila @ovo/ui, headers de segurança
├── package.json                    # next, react 19
└── ...
```

---

## ✅ Checklist de Funcionalidades

- [x] Navbar com scroll-spy
- [x] Hero com CTA
- [x] Seção de planos com fetch dinâmico
- [x] Tabela de comparação
- [x] Seção de bairros com busca
- [x] FAQ estática
- [x] Footer com WhatsApp
- [x] Modal de checkout com validação
- [x] Toast de sucesso
- [x] Responsivo (mobile-first)
- [x] Tokens CSS compartilhados
- [ ] ❌ Checkout funcional (bug: autenticação)
- [ ] ❌ Página de termos/privacidade
- [ ] ❌ Página de carrinho (não existe)

---

**Última atualização:** 29/09/2026
