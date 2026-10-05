# Claude Code Guide for Ovo di Onça

## Codebase Overview

**Ovo di Onça** é um sistema de subscription de ovos caipiras: ordem → entrega quinzenal/semanal/mensal → pagamento manual (PIX). Backend em Postgres com RLS, dois Next.js apps (assinante e gestão), landing page SPA (site). Segurança em camadas: middleware, Better Auth, RLS, funções SQL com lista fechada.

**Stack:** pnpm monorepo, Node ≥ 20.11, Postgres 16 (Neon), Next.js 15, React 19, TypeScript 5, Better Auth.

**Structure:** `apps/assinante` (API + portal do assinante, porta 3001), `apps/site` (landing page SPA, porta 3002), `apps/gestao` (admin panel, porta 3000), `packages/database` (acesso ao Postgres), `packages/ui` (tokens CSS), `packages/config` (headers de segurança).

For detailed architecture, routing, data flow and conventions, see [docs/CODEBASE_MAP.md](docs/CODEBASE_MAP.md).

## Current State (05/10/2026)

- **Database:** 29 migrations (Fases 0–10, Etapas 1–2 e Blocos 3–8; as migrations 424–428 só foram aplicadas no banco de teste local, **não no Neon**). Testes SQL: `pnpm teste:banco` (~280 verificações + concorrência do limite de login) + `pnpm seguranca`. Exigem `DATABASE_TEST_URL` (branch de teste; sem fallback para o principal). `pnpm db:migrar:teste` migra só o teste. Ver README, "Banco de testes".
- **CI:** (4 jobs: segurança, qualidade, banco, e2e). `.github/workflows/ci.yml`: roda em push na `main` e em pull request. **Nunca rodou no GitHub ainda** (foi simulado passo a passo localmente). Passo a passo de lançamento: [docs/LANCAMENTO.md](docs/LANCAMENTO.md).
- **Site (Blocos 1–2):** `apps/site` com componentes base (`components/ui`), fontes via `next/font`, seções do Stitch. Conteúdo público (planos por entrega, frescor, frete, desconto, corte, FAQ) vem de `GET /api/site` e `/api/plans` (Bloco 3). Contraste AA nos tokens (`--cor-sobre-ouro`, `--cor-ouro-escuro`, `--cor-whatsapp`).
- **Fluxo de assinatura (Bloco 4):** site → `assinante:/assinar` com indicador de etapas → conta → endereço → confirmação. Funil anônimo (`eventos_funil`, `POST /api/evento`); `scripts/e2e/assinatura.mjs`.
- **Fora da área (Bloco 5):** "Avise-me" (`POST /api/interesse`, `registrar_interesse`), consentimento versionado (`@ovo/config/privacidade`), `/interessados` no painel. Sem auditoria nesta tabela, de propósito (LGPD).
- **D8 (Bloco 6):** chave `exigir_pagamento_antes_da_1a_entrega` em `/configuracoes` (**desligada** por padrão): ligada, a assinatura nasce aguardando o 1º pagamento (`aguardando_pagamento_desde`), com a 1ª fatura e sem entrega; pagar libera a entrega (corte D9 no instante da confirmação); quem não paga em N dias é cancelado pela rotina. **Pagamento online:** papel `app_pagamentos` + `confirmar_pagamento_online`, webhook `POST /api/pagamento/webhook` que **nunca confia no corpo** (consulta o provedor). Provedores: `nenhum` (padrão) | `simulado` (dev) | `infinitepay` (**contrato A CONFIRMAR**, só liga com `INFINITEPAY_CONTRATO_CONFIRMADO=sim`).
- **Entrada no ar (Bloco 8):** limite de login no Postgres (`consumir_rate_limit` + `customStorage` do Better Auth), CSP com `CSP_MODO=relatorio|impor` (lido no build), `GET /api/saude`, `scripts/smoke.mjs`, `scripts/rodar-rotina.sh`, `scripts/e2e/{assinatura,pagamento,csp}.mjs`.
- **Auditoria de estabilidade (30/09/2026):** rotina diária serializada por advisory lock e resistente a falha isolada; defeito duplicado recusado; `dentro_area_entrega` recalculado por gatilho ao mexer nas faixas; pools do `pg` com ouvinte de erro; `/api/plans` e `/api/neighborhoods` com cache de 30 s.
- **Regras de cobrança D1–D15:** decididas em `DECISOES.md`; **implementadas só D8, D9 e D10 (calendário de entregas)**. Faltam D1/D2 (vencimento dia 3, inadimplência), D3–D7, D11, D15.
- **Não existe:** serviço de e-mail configurado, faixas de CEP cadastradas (sem elas ninguém assina), fotos/depoimentos reais, ferramenta de monitoramento de erros.
- **Testes unitários:** `pnpm test` (assinante: segurança, whatsapp, cache, funil, interesse, pagamento, limite; gestão: csv).

## Key Decisions

- **Security:** RLS no banco é a proteção real; middleware e sessão são conveniência.
  Veja [docs/SEGURANCA.md](docs/SEGURANCA.md) para threat model, mitigações, rate limit e runbook de incident.
- **Data:** nenhuma política de `insert`, `update` ou `delete` a `app_anon` ou `app_usuario`; toda escrita passa por função SQL com lista fechada.
- **Audit:** auditoria imutável, gatilho `auditar()` em 8 tabelas, inclui antes/depois e quem agiu.
- **Preço:** vem do banco (`config_negocio.preco_pente_centavos` × entregas por mês, via `planos_publicos()`); o cliente nunca envia preço.
- **Datas:** sem `Date` do JS; tudo via `::text` ou `::timestamp` com fuso São Paulo no SQL.
- **Limites:** listas do gestão sem paginação (200/300/500 linhas).

## Common Tasks

### Run both apps in dev
```bash
npm run dev     # assinante (3001) e site (3002) em paralelo
# Or separately:
cd apps/assinante && npm run dev  # 3001
cd apps/site && npm run dev       # 3002
cd apps/gestao && npm run dev     # 3000
```

### Database migrations
```bash
npm run db:migrar      # Apply all pending
npm run db:reverter    # Revert last one
npm run db:papel-servidor  # Create/update app_servidor role
pnpm --filter @ovo/database teste:estrutura   # Run structure tests
```

### Add a new page to gestão
1. Create `apps/gestao/src/app/nova-rota/page.tsx` with `exigirDono()` at top.
2. If writing: create `apps/gestao/src/app/nova-rota/acoes.ts` with `comoDono` wrapper.
3. Use `FormAcao` for forms, render errors/success via `{ok, mensagem}`.
4. All writes go through functions with closed list of fields (never `update(req.body)`).

### Fix a security issue
1. Check `scripts/verificar-segredos.sh` (8 verifications).
2. Test: `pnpm seguranca` and `pnpm typecheck`.
3. CI runs these automatically.

## Gotchas

- Rate limit do Better Auth é em memória (por instância).
- `.env` na raiz; `next.config.ts` de assinante e site o carregam.
- Bash do Claude Code colapsa `\` em heredocs: para código com barra invertida use a ferramenta de edição.
- CSP em report-only; para aplicar, `{ modoRelatorio: false }` em `next.config.ts`.
- `Ovo di Onça Design System/` (85 MB) e `_tmp_*` continuam fora do fluxo.

## Key Files

- `packages/database/src/acesso.ts:82–118` — `emTransacao`, como os papéis são definidos
- `packages/database/src/auth/papel.ts:30–50` — `usuarioAtual`, `exigirDono`
- `packages/database/migrations/` — Fases 0–9
- **`apps/assinante/src/app/assinar/`** — passos de cadastro e confirmação (`acoes.ts` chama `criar_meu_cadastro` / `assinar_plano`)
- `apps/assinante/src/lib/seguranca.ts` — `caminhoInterno()` (anti open redirect)
- `apps/gestao/src/lib/dono.ts` — `comoDono(fn)` = `exigirDono() + comoAdmin`

## Notes for Future Work

- Pagamento online (InfinitePay/Asaas) e e-mail (Resend ou outro): precisam de decisão e credenciais.
- Cadastrar faixas de CEP em `/area-de-entrega` (gestão) — sem elas ninguém consegue assinar.
- `marcar_faturas_atrasadas()` e recálculos precisam virar job; listas do gestão sem paginação.
