# Claude Code Guide for Ovo di Onça

## Codebase Overview

**Ovo di Onça** é um sistema de subscription de ovos caipiras: ordem → entrega quinzenal/semanal/mensal → pagamento manual (PIX). Backend em Postgres com RLS, três apps Next.js (assinante, gestão e site, a landing page). Segurança em camadas: middleware, Better Auth, RLS, funções SQL com lista fechada.

**Stack:** pnpm monorepo, Node ≥ 20.11, Postgres 16 (Neon), Next.js 15, React 19, TypeScript 5, Better Auth.

**Structure:** `apps/assinante` (API + portal do assinante, porta 3001), `apps/site` (landing page Next.js, porta 3002), `apps/gestao` (admin panel, porta 3000), `packages/database` (acesso ao Postgres), `packages/ui` (tokens CSS), `packages/config` (headers de segurança).

For detailed architecture, routing, data flow and conventions, see [docs/CODEBASE_MAP.md](docs/CODEBASE_MAP.md).

## Current State (atualizado 23/10/2026)

- **Mudanças desde 29/09** (detalhe em [docs/CODEBASE_MAP.md](docs/CODEBASE_MAP.md), seção "Atualização de 22/10/2026"): 24 migrations (421 calendário/corte; 422 RLS em tabelas com dados pessoais; 423 rate limit no banco, ainda sem uso); `.github/workflows/ci.yml` recriado, mas não commitado; visual novo do gestão (`packages/ui/src/ds.css`, componentes em `apps/gestao/src/app/_componentes/`, etapas C1 e C2 do `docs/PLANO-VISUAL-GESTAO-20261019.md`, sem commit); Hero do site com o slogan do `design.md`.
- **Regras de cobrança D1–D15:** só D9 e D10 (datas) estão no código. O resto está em `docs/PLANO-GESTAO-20261013.md`. Decisões de 22/10 em `DECISOES.md`. Pagamento segue manual (PIX + comprovante); sem provedor de e-mail.
- **Atenção:** rate limit em banco, CSP em bloqueio e rate limit em Server Actions estão documentados, mas **não efetivos** (CSP em report-only; Better Auth com rate limit em memória). O Down da migration 422 desliga a RLS original.


- **Database:** 22 migrations (Fases 0–9 + Etapas 1–2; a 421 aplicada também no principal em 30/09/2026). Testes SQL: `pnpm teste:banco` (fase1..10) + `pnpm seguranca`. Os testes SQL exigem `DATABASE_TEST_URL` (branch de teste do Neon; sem fallback para o principal). `pnpm db:migrar:teste` migra só o teste. Ver README, "Banco de testes".
- **Auditoria de estabilidade (30/09/2026):** rotina diária serializada por advisory lock e resistente a falha isolada; defeito duplicado recusado; `dentro_area_entrega` recalculado por gatilho ao mexer nas faixas; pools do `pg` com ouvinte de erro (o Neon derruba conexões ociosas); `/api/plans` e `/api/neighborhoods` com cache de 30 s. Dados `[TESTE]` ainda no banco: `pnpm db:limpar-teste` remove (não toca na auditoria).
- **Fase 9:** cobrança do período (`gerar_cobranca`, forma pix|cartao), pausa com retorno previsto, reposição de defeitos (`reposicoes`), resposta aos pedidos do assinante, horário de entrega, `/configuracoes`, rotina diária (`processar_rotina_diaria`; botão no painel e `POST /api/rotina` com `CRON_SECRET`).
- **Fluxo de assinatura pelo site:** site (`Assinar`) → `assinante:/assinar?plano=<semanal|quinzenal|mensal>` → conta (`/cadastro`) → endereço (`criar_meu_cadastro`) → confirmação (`assinar_plano`). Nenhum dado pessoal vai por URL; o site não coleta nada.
- **Site** lê planos/bairros/área por rewrites para o assinante (sem CORS). **Preço** vem de `planos_publicos()` (pente × entregas_por_mes), sem valor no código. **Bairros** = faixas de CEP ativas (hoje 0 → lista vazia, e todo CEP é "fora da área").
- **Vínculo conta↔cliente por e-mail só com e-mail confirmado** (migration 13). Sem serviço de e-mail ninguém tem e-mail confirmado: o dono vincula na ficha do cliente.
- **Não existe:** integração de pagamento (InfinitePay/Asaas), serviço de e-mail configurado, faixas de CEP. Ver DECISOES.md ("Fase 8").
- **Testes unitários:** `pnpm test` (assinante: `caminhoInterno`, `ehFrequencia`).

## Key Decisions

- **Security:** RLS no banco é a proteção real; middleware e sessão são conveniência.
  Veja [docs/SEGURANCA.md](docs/SEGURANCA.md) para threat model, mitigações, rate limit e runbook de incident.
- **Data:** nenhuma política de `insert`, `update` ou `delete` a `app_anon` ou `app_usuario`; toda escrita passa por função SQL com lista fechada.
- **Audit:** auditoria imutável, gatilho `auditar()` em 8 tabelas, inclui antes/depois e quem agiu.
- **Preço:** hardcoded em SQL (semanal 16400¢, quinzenal 8200¢, mensal 4100¢); cliente não envia preço.
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
- `Ovo di Onça Design System/` (85 MB) continua fora do fluxo; os `_tmp_*` foram removidos.
- Descartes da triagem de 23/10 estão em `_a-apagar/` (ignorada no git) — ver `_a-apagar/LEIA-ME.md`.

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
