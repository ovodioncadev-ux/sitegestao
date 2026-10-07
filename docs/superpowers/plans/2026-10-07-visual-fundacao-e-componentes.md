# Visual — Fundação e Componentes (Etapas 0 e 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar em `packages/ui` os tokens do Design System (com contraste AA corrigido) e a biblioteca completa de componentes, sem alterar nenhuma tela de produção.

**Architecture:** `tokens.css` passa a conter os tokens do Design System; os nomes antigos (`--cor-*`, `--fonte-*`) viram apelidos. Os componentes são TSX com classes `.ovo-*` num único `components.css` (zero estilo inline estático, zero cor literal). Componentes são de servidor por padrão; só `Tag` e `Dialog` levam `'use client'`. Navegação é por `href` (com `LinkComponent` opcional), nunca por callback.

**Tech Stack:** pnpm monorepo, Next 15, React 19, TypeScript 5 estrito, `next/font/google`, testes com `node:test` + `tsx` + `react-dom/server`.

**Spec:** `docs/superpowers/specs/2026-10-07-visual-design-system-design.md` (este plano cobre as **Etapas 0 e 1**; as Etapas 2–5 terão um plano cada, escritos depois da aprovação dos screenshots desta).

## Divergências em relação ao spec (aprovadas ao aprovar este plano)

| Spec dizia | Este plano faz | Por quê |
|---|---|---|
| Botão primário usa "tom escuro do dourado" | Dourado `#D4A437` com **texto marrom-escuro `#2B2419`** (6,69:1); hover/press em `gold-500` (5,22:1) | O texto claro sobre dourado reprova; o Design System já usava texto escuro, só precisava escurecer um pouco |
| "Contraste conferido" | Teste automático WCAG com 40+ pares e **5 correções de token** (texto suave, link, sucesso, texto sobre sunken, borda de campo) | O Design System puro reprova AA nesses pares (medido em 07/10/2026) |
| Página `/ui-kit` em cada app | **Só em `apps/site`**, só em desenvolvimento | `assinante` e `gestao` têm middleware de autenticação; abrir uma rota ali é mexer em segurança, fora do escopo |
| DataTable com ordenação, seleção e clique de linha | **Sem** ordenação/seleção/clique (tabela estática, com modo "cartões" no celular) | Nenhuma tela atual usa; e componente `'use client'` não aceita `render` de célula vindo de página de servidor |
| "Sem inline" | Sem estilo inline **estático**; só valores dinâmicos (largura da barra, altura do gráfico) | O CSP atual já permite `style-src 'unsafe-inline'` |
| Etapa 0: "nenhuma tela muda" | Os apelidos `--cor-*` passam a apontar para os tokens novos: **telas ainda não migradas mudam de cor e fonte** (laranja → dourado; Aclonica/Poppins → Outfit/Archivo) | É o que o spec descreve ("apelidos apontando para os tokens novos"); o ganho é consistência imediata |
| Etapa 5 remove "apelidos" | Remove os apelidos **e** o bloco "legado" de escala (`--texto-*`, `--esp-*`, `--raio-*`); a regra de movimento reduzido **permanece** | Ela é acessibilidade, não legado |

## Global Constraints

- Tudo em **português do Brasil**: identificadores de domínio, textos, mensagens de commit. (Nomes de props dos componentes seguem o Design System em inglês: `variant`, `size`, `icon`, `tone`.)
- **Nenhuma cor literal** (`#hex`, `rgb()`, `rgba()`, `hsl()`) fora de `packages/ui/src/tokens.css`.
- **Nenhum nome de família de fonte literal** fora de `tokens.css` e `fontes.ts`.
- **Nenhum `px` literal** em `font`/`font-size` dentro de `components.css` (tamanhos vêm de `--fs-*`).
- **Mínimo de 14px na área do cliente** (`site`, `assinante`): garantido por `.ovo-root--cliente` em `escala-cliente.css`. No painel, 11–12px só em rótulo/overline.
- **Contraste:** texto ≥ 4,5:1; borda de controle e anel de foco ≥ 3:1 (WCAG 2.2 AA). Medido por `tests/contraste.test.ts`.
- **Foco de teclado sempre visível** em todo controle.
- **Não alterar:** `acoes.ts`, `exigirDono()`, `comoDono`, `FormAcao`, `middleware.ts`, SQL, migrations, RLS, `packages/database`, `packages/config`.
- **Não escrever no banco.**
- Node ≥ 20.11 (hoje 24), pnpm 9.12.3, React ^19.1.1, Next ^15.5.4.
- Todo commit termina com a linha: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Pasta `Ovo di Onça Design System/` é **somente leitura** e está no `.gitignore`; os scripts deste plano a leem e gravam o resultado em `packages/ui`.

## Review Focus

Entradas e condições que o spec implica, mas que nenhuma tarefa exercitaria por padrão. Cada linha tem um teste na tarefa que é dona do código:

1. **`<Button>` dentro de `<form>` sem `type="submit"` nunca envia.** O padrão é `type="button"` (como no Design System); migrar um `<button>` HTML para `<Button>` sem passar `type="submit"` quebra o formulário em silêncio. Teste na Task 3 (padrão `button`, `submit` respeitado).
2. **ProgressBar com `max=0`, valor negativo, valor > max ou `NaN`** não pode gerar `width:NaN%`/`Infinity%`. Teste na Task 6.
3. **Paginação vazia** (`total=0`, `pageCount=0/1`, `page` acima de `pageCount`): sem "1–0 de 0", botões das pontas desativados, sem números inexistentes. Teste na Task 7.
4. **Campo com erro** deve expor o erro a leitor de tela (`aria-invalid`, `aria-describedby`) e o rótulo deve apontar para o campo (`for`/`id` via `useId`). Teste na Task 5.
5. **Tabela sem linhas e `Avatar` com nome vazio ou só espaços** não podem quebrar nem mostrar "undefined". Testes nas Tasks 4 e 6.

## File Structure

```
packages/ui/
  package.json                    # exports, scripts, devDeps (Task 1)
  tsconfig.json                   # jsx react-jsx (Task 1)
  src/
    tokens.css                    # tokens DS + correções de contraste + apelidos legados (Task 1)
    base.css                      # .ovo-root: fundo, texto, foco, links (Task 2)
    escala-cliente.css            # .ovo-root--cliente: mínimo 14px (Task 2)
    fontes.ts                     # next/font: Outfit, Archivo, IBM Plex Mono (Task 2)
    components.css                # todas as classes .ovo-* (Tasks 3–8)
    cx.ts                         # junta classes (Task 3)
    index.ts                      # barrel (Tasks 3–8)
    core/    icons.ts Icon.tsx Button.tsx Badge.tsx Card.tsx Avatar.tsx IconButton.tsx Tag.tsx Tooltip.tsx
    forms/   Input.tsx Textarea.tsx Select.tsx Checkbox.tsx Radio.tsx Switch.tsx SearchField.tsx
    data/    ProgressBar.tsx Trend.tsx StatCard.tsx BarChart.tsx DataTable.tsx
    navigation/ Sidebar.tsx Tabs.tsx TopBar.tsx BottomNav.tsx Pagination.tsx
    feedback/ Banner.tsx Dialog.tsx EmptyState.tsx Toast.tsx
    kit/     UiKit.tsx DialogDemo.tsx (Task 9)
  tests/
    _tokens.ts contraste.test.ts tokens-legados.test.ts guardas.test.ts
    button.test.tsx core.test.tsx forms.test.tsx data.test.tsx navigation.test.tsx feedback.test.tsx
apps/site/src/app/ui-kit/page.tsx            # só dev (Task 9)
apps/{site,assinante,gestao}/src/app/layout.tsx   # imports + fontes (Task 2)
.claude/launch.json                          # servidores de preview (Task 9)
```

---

### Task 1: Pacote, tokens e teste de contraste

**Files:**
- Modify: `packages/ui/package.json`
- Create: `packages/ui/tsconfig.json`, `packages/ui/tests/_tokens.ts`, `packages/ui/tests/contraste.test.ts`, `packages/ui/tests/tokens-legados.test.ts`
- Modify (rewrite): `packages/ui/src/tokens.css`

**Interfaces:**
- Consumes: arquivos `Ovo di Onça Design System/tokens/{colors,typography,spacing,radii,elevation,motion}.css` (somente leitura).
- Produces: `@ovo/ui/tokens.css` com os tokens do DS (`--gold-*`, `--brown-*`, `--olive-*`, `--cream-*`, `--surface-*`, `--text-*`, `--border-*`, `--action-*`, `--font-*`, `--fs-*`, `--space-*`, `--radius-*`, `--shadow-*`, `--ring-*`, `--dur-*`, `--control-height-*`, `--sidebar-width`…), mais os tokens novos `--gold-800`, `--text-on-sunken`, `--border-control`, `--surface-inverse-hover`, `--surface-on-accent-chip`, e os apelidos legados (`--cor-*`, `--fonte-*`, `--texto-*`, `--esp-*`, `--raio-*`, `--largura-conteudo`, `--altura-controle`, `--alvo-toque`, `--padding-*`, `--sombra-flutuante`, `--altura-linha-*`). `tests/_tokens.ts` exporta `RAIZ`, `lerTokens()`, `resolverCor()`, `contraste()`.

- [ ] **Step 0: Criar o branch de trabalho (não trabalhar na `main`)**

Run:
```bash
git switch -c feat/visual-fundacao-componentes
git branch --show-current
```
Expected: `feat/visual-fundacao-componentes`. Todos os commits deste plano vão nesse branch. (O spec e este plano já estão commitados; não repetir.)

- [ ] **Step 1: Reescrever `packages/ui/package.json`**

```json
{
  "name": "@ovo/ui",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "exports": {
    ".": "./src/index.ts",
    "./tokens.css": "./src/tokens.css",
    "./base.css": "./src/base.css",
    "./components.css": "./src/components.css",
    "./escala-cliente.css": "./src/escala-cliente.css",
    "./fontes": "./src/fontes.ts",
    "./kit": "./src/kit/UiKit.tsx"
  },
  "scripts": {
    "typecheck": "tsc --noEmit",
    "test": "node --import tsx --test tests/*.test.ts"
  },
  "peerDependencies": {
    "next": "^15.5.4",
    "react": "^19.1.1"
  }
}
```

- [ ] **Step 2: Criar `packages/ui/tsconfig.json`**

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "jsx": "react-jsx",
    "allowImportingTsExtensions": true,
    "types": ["node"]
  },
  "include": ["src/**/*.ts", "src/**/*.tsx", "tests/**/*.ts", "tests/**/*.tsx"]
}
```

- [ ] **Step 3: Instalar dependências de desenvolvimento**

Run:
```bash
pnpm --filter @ovo/ui add -D react@^19.1.1 react-dom@^19.1.1 @types/react@^19.1.10 @types/react-dom@^19.1.7 @types/node@^22.10.2 next@^15.5.4 typescript@^5.6.3 tsx
```
Expected: instalação sem erro; `pnpm-lock.yaml` e `packages/ui/package.json` (`devDependencies`) atualizados. (`typescript` já existe na raiz; instalar aqui garante `tsc` no pacote.)

- [ ] **Step 4: Escrever o helper de tokens `packages/ui/tests/_tokens.ts`**

```ts
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export const RAIZ = resolve(import.meta.dirname, '..');

/** Lê tokens.css e devolve nome → valor. Definição posterior vence a anterior. */
export function lerTokens(): Map<string, string> {
  const css = readFileSync(resolve(RAIZ, 'src/tokens.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  const mapa = new Map<string, string>();
  for (const m of css.matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)) mapa.set(m[1]!, m[2]!.trim());
  return mapa;
}

/** Segue var(--x) até chegar num #hex (ou devolve o valor como está). */
export function resolverCor(valorOuNome: string, mapa: Map<string, string>, fundo = 0): string {
  if (fundo > 12) throw new Error(`referência circular em ${valorOuNome}`);
  const valor = valorOuNome.startsWith('--') ? mapa.get(valorOuNome) : valorOuNome;
  if (valor === undefined) throw new Error(`token indefinido: ${valorOuNome}`);
  const ref = valor.match(/^var\((--[\w-]+)\)$/);
  return ref ? resolverCor(ref[1]!, mapa, fundo + 1) : valor;
}

function luminancia(hex: string): number {
  if (!/^#[0-9a-f]{6}$/i.test(hex)) throw new Error(`esperava #rrggbb, veio ${hex}`);
  const [r, g, b] = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  }) as [number, number, number];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** Razão de contraste WCAG entre duas cores #rrggbb. */
export function contraste(a: string, b: string): number {
  const [claro, escuro] = [luminancia(a), luminancia(b)].sort((x, y) => y - x) as [number, number];
  return (claro + 0.05) / (escuro + 0.05);
}
```

- [ ] **Step 5: Escrever o teste `packages/ui/tests/contraste.test.ts`**

```ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { contraste, lerTokens, resolverCor } from './_tokens.ts';

const tokens = lerTokens();
const cor = (nome: string) => resolverCor(`--${nome}`, tokens);

/** [texto, fundo, mínimo]. 4,5 = texto normal; 3 = borda de controle e anel de foco. */
const PARES: Array<[string, string, number]> = [
  ['text-body', 'surface-page', 4.5],
  ['text-body', 'surface-card', 4.5],
  ['text-body', 'surface-raised', 4.5],
  ['text-body', 'surface-highlight', 4.5],
  ['text-body', 'cream-300', 4.5],
  ['text-strong', 'surface-page', 4.5],
  ['text-strong', 'surface-card', 4.5],
  ['text-muted', 'surface-page', 4.5],
  ['text-muted', 'surface-card', 4.5],
  ['text-muted', 'surface-raised', 4.5],
  ['text-on-sunken', 'surface-sunken', 4.5],
  ['text-link', 'surface-page', 4.5],
  ['text-link', 'surface-raised', 4.5],
  ['text-link-hover', 'surface-page', 4.5],
  ['text-accent', 'surface-page', 4.5],
  ['text-accent', 'surface-raised', 4.5],
  ['text-on-accent', 'action-primary', 4.5],
  ['text-on-accent', 'action-primary-hover', 4.5],
  ['text-on-accent', 'action-primary-press', 4.5],
  ['text-on-accent', 'surface-accent', 4.5],
  ['text-on-inverse', 'surface-inverse', 4.5],
  ['text-on-inverse-muted', 'surface-inverse', 4.5],
  ['text-on-inverse', 'surface-inverse-soft', 4.5],
  ['text-on-olive', 'surface-olive', 4.5],
  ['text-on-olive-muted', 'surface-olive', 4.5],
  ['text-olive', 'surface-olive-soft', 4.5],
  ['text-success', 'surface-page', 4.5],
  ['text-success', 'surface-card', 4.5],
  ['text-success', 'surface-success-soft', 4.5],
  ['text-danger', 'surface-page', 4.5],
  ['text-danger', 'surface-card', 4.5],
  ['text-danger', 'surface-raised', 4.5],
  ['red-700', 'surface-danger-soft', 4.5],
  ['green-700', 'surface-success-soft', 4.5],
  ['gold-700', 'surface-accent-soft', 4.5],
  ['green-700', 'surface-olive-soft', 4.5],
  ['red-700', 'surface-olive-soft', 4.5],
  // Não-texto: borda de campo/caixa e anel de foco.
  ['border-control', 'surface-raised', 3],
  ['border-control', 'surface-page', 3],
  ['border-focus', 'surface-page', 3],
  ['border-focus', 'surface-raised', 3],
  ['clay-500', 'surface-raised', 3],
];

for (const [texto, fundo, minimo] of PARES) {
  test(`contraste ${texto} sobre ${fundo} ≥ ${minimo}`, () => {
    const razao = contraste(cor(texto), cor(fundo));
    assert.ok(razao >= minimo, `${texto} (${cor(texto)}) sobre ${fundo} (${cor(fundo)}) = ${razao.toFixed(2)}, mínimo ${minimo}`);
  });
}
```

- [ ] **Step 6: Escrever o teste `packages/ui/tests/tokens-legados.test.ts`**

```ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { lerTokens } from './_tokens.ts';

const RAIZ_REPO = resolve(import.meta.dirname, '../../..');
const tokens = lerTokens();
const IGNORAR = new Set(['node_modules', '.next', '.git', 'dist', 'build', 'out']);

function arquivos(dir: string): string[] {
  return readdirSync(dir).flatMap((nome) => {
    if (IGNORAR.has(nome)) return [];
    const caminho = join(dir, nome);
    return statSync(caminho).isDirectory() ? arquivos(caminho) : /\.(css|ts|tsx)$/.test(nome) ? [caminho] : [];
  });
}

test('todo var(--x) usado nos apps está definido em tokens.css (ou no próprio arquivo)', () => {
  const faltando: string[] = [];
  for (const arquivo of arquivos(join(RAIZ_REPO, 'apps'))) {
    const texto = readFileSync(arquivo, 'utf8');
    const locais = new Set([...texto.matchAll(/(--[\w-]+)\s*:/g)].map((m) => m[1]!));
    for (const m of texto.matchAll(/var\((--[\w-]+)/g)) {
      const nome = m[1]!;
      if (nome.startsWith('--tw-') || nome.startsWith('--next-') || locais.has(nome) || tokens.has(nome)) continue;
      faltando.push(`${arquivo.replace(RAIZ_REPO, '')}: ${nome}`);
    }
  }
  assert.deepEqual([...new Set(faltando)], []);
});

test('apelidos legados de cor e fonte apontam para tokens novos', () => {
  const esperado: Record<string, string> = {
    '--cor-fundo': 'var(--surface-page)',
    '--cor-texto': 'var(--text-body)',
    '--cor-ouro': 'var(--action-primary)',
    '--cor-ouro-escuro': 'var(--gold-700)',
    '--fonte-titulo': 'var(--font-display)',
    '--fonte-corpo': 'var(--font-sans)',
  };
  for (const [nome, valor] of Object.entries(esperado)) assert.equal(tokens.get(nome), valor, nome);
});
```

- [ ] **Step 7: Gerar a base de `tokens.css` a partir do Design System**

Run (na raiz do repositório):
```bash
DS="Ovo di Onça Design System/tokens"
{
  cat <<'EOF'
/* ═══════════════════════════════════════════════════════════════════════
   Tokens de design — fonte única para os três apps.

   Base: Ovo di Onça Design System (colors, typography, spacing, radii,
   elevation, motion), copiada sem edição. Tudo que o Design System não
   atende (contraste AA, apelidos antigos) vem DEPOIS, nas seções
   "Correções de contraste" e "Apelidos legados". Nenhuma cor literal fora
   deste arquivo (tests/guardas.test.ts).
   ═══════════════════════════════════════════════════════════════════════ */

EOF
  for f in colors typography spacing radii elevation motion; do
    echo "/* ── DS: $f ─────────────────────────────────────────────────── */"
    cat "$DS/$f.css"
    echo
  done
} > packages/ui/src/tokens.css
wc -l packages/ui/src/tokens.css
```
Expected: ~240 linhas.

- [ ] **Step 8: Rodar os testes e ver o contraste reprovar**

Run: `pnpm --filter @ovo/ui test`
Expected: **FAIL**. Reprovam (entre outros): `text-on-accent sobre action-primary-press`, `text-link sobre surface-page` (3,54), `text-muted sobre surface-page` (3,82), `text-success sobre surface-page` (4,10), `text-on-inverse-muted sobre surface-inverse` (4,45), os que citam `text-on-sunken`/`border-control` (token indefinido), `border-control`, e `tokens-legados` (apelidos ainda inexistentes). Isso prova que o teste mede o que o Design System tem.

- [ ] **Step 9: Acrescentar as correções de contraste ao fim de `tokens.css`**

Append:

```css
/* ── Correções de contraste (WCAG 2.2 AA) ───────────────────────────────
   O Design System puro reprova nestes pares (medido em 07/10/2026).
   Valores calculados e conferidos por tests/contraste.test.ts. */
:root {
  --gold-800: #5e4410;                          /* hover de link: 8,3:1 sobre o creme */
  --text-on-accent: #2b2419;                    /* sobre dourado: 6,7:1 (era 5,6) */
  --text-muted: var(--brown-500);               /* era brown-400: 3,8:1 */
  --text-on-sunken: var(--brown-600);           /* texto de cabeçalho de tabela: 6,1:1 */
  --text-accent: var(--gold-700);
  --text-link: var(--gold-700);                 /* era gold-600: 3,5:1 */
  --text-link-hover: var(--gold-800);
  --text-success: var(--green-700);             /* era green-600: 4,1:1 */
  --text-on-inverse-muted: #cdc1a8;             /* sobre marrom-escuro: 5,8:1 (era 4,45) */
  --text-on-olive-muted: #e6e3d6;               /* creme a 88% sobre oliva, opaco: 5,0:1 */
  --action-primary-hover: var(--gold-500);
  --action-primary-press: var(--gold-500);      /* gold-600 reprovava (3,97:1) com texto escuro */
  --border-control: var(--brown-400);           /* borda de campo/caixa: ≥ 3:1 (era 1,6:1) */
  --border-focus: var(--gold-700);
  --ring-focus: 0 0 0 var(--border-width-focus) var(--gold-700), 0 0 0 4px rgba(126, 90, 21, 0.22);
  --surface-inverse-hover: rgba(249, 245, 234, 0.09);   /* item de menu sob o mouse */
  --surface-on-accent-chip: rgba(43, 36, 25, 0.18);     /* selo sobre item ativo dourado */
}
```

- [ ] **Step 10: Acrescentar os apelidos legados e a regra de movimento ao fim de `tokens.css`**

Append:

```css
/* ── Apelidos legados ───────────────────────────────────────────────────
   Nomes antigos que as telas ainda não migradas usam. Cores e fontes
   apontam para os tokens novos. Removidos na Etapa 5 (junto com a escala
   antiga abaixo). */
:root {
  --cor-fundo: var(--surface-page);
  --cor-fundo-alt: var(--surface-card);
  --cor-texto: var(--text-body);
  --cor-texto-suave: var(--brown-600);
  --cor-ouro: var(--action-primary);
  --cor-ouro-escuro: var(--gold-700);
  --cor-ouro-app: var(--gold-400);
  --cor-borda: var(--border-default);
  --cor-sucesso: var(--text-success);
  --cor-erro: var(--text-danger);
  --cor-whatsapp: #1a9e4b;

  --fonte-titulo: var(--font-display);
  --fonte-corpo: var(--font-sans);

  --texto-rotulo: 12px;
  --texto-pequeno: 14px;
  --texto-corpo: 16px;
  --texto-medio: 18px;
  --texto-grande: 24px;
  --texto-titulo: 32px;
  --texto-hero: 44px;
  --altura-linha-corpo: 1.6;
  --altura-linha-titulo: 1.2;

  --esp-1: 4px;
  --esp-2: 8px;
  --esp-3: 12px;
  --esp-4: 16px;
  --esp-6: 24px;
  --esp-8: 32px;
  --esp-12: 48px;
  --esp-16: 64px;
  --esp-24: 96px;

  --largura-conteudo: 1120px;
  --altura-controle: 48px;
  --alvo-toque: 44px;
  --padding-card: var(--esp-6);
  --padding-celula: var(--esp-3);
  --raio-controle: 8px;
  --raio-card: 16px;
  --sombra-flutuante: 0 2px 8px rgb(28 40 38 / 8%);
}

/* ── Movimento reduzido (permanente) ────────────────────────────────────
   Acessibilidade, não legado: fica depois da Etapa 5. */
@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

- [ ] **Step 11: Rodar os testes e ver tudo passar**

Run: `pnpm --filter @ovo/ui test`
Expected: **PASS** em todos (≈ 45 testes). Se algum par de contraste reprovar, ajuste **só o token** (nunca o limite do teste) e rode de novo; o valor e a razão aparecem na mensagem. Se `tokens-legados` listar uma variável que alguma tela usa e que não existe, defina-a no bloco "Apelidos legados" com o valor que ela tinha antes (`git show HEAD:packages/ui/src/tokens.css`) e rode de novo.

- [ ] **Step 12: Conferir tipos**

Run: `pnpm --filter @ovo/ui typecheck`
Expected: sem erros (o pacote só tem testes por enquanto).

- [ ] **Step 13: Commit**

```bash
git add packages/ui pnpm-lock.yaml
git commit -m "feat(ui): tokens do Design System com contraste AA e apelidos legados

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Fontes, base escopada, escala do cliente e ligação nos apps

**Files:**
- Create: `packages/ui/src/fontes.ts`, `packages/ui/src/base.css`, `packages/ui/src/escala-cliente.css`
- Create: `packages/ui/src/components.css` (vazio, com cabeçalho)
- Create: `packages/ui/tests/escala-cliente.test.ts`
- Modify: `apps/site/src/app/layout.tsx`, `apps/assinante/src/app/layout.tsx`, `apps/gestao/src/app/layout.tsx`

**Interfaces:**
- Consumes: tokens da Task 1.
- Produces: `import { classeFontes } from '@ovo/ui/fontes'` (string de classes que define `--next-outfit`, `--next-archivo`, `--next-plex`); classes `.ovo-root` (base) e `.ovo-root--cliente` (mínimo 14px); `components.css` carregado nos três apps.

- [ ] **Step 1: Escrever o teste `packages/ui/tests/escala-cliente.test.ts`**

```ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { RAIZ } from './_tokens.ts';

const css = readFileSync(resolve(RAIZ, 'src/escala-cliente.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');

test('escala do cliente: todo --fs-* é ≥ 14px', () => {
  const tamanhos = [...css.matchAll(/--fs-[\w]+\s*:\s*(\d+)px/g)].map((m) => Number(m[1]));
  assert.ok(tamanhos.length >= 4, 'esperava redefinir --fs-3xs, --fs-2xs, --fs-xs e --fs-sm');
  for (const t of tamanhos) assert.ok(t >= 14, `tamanho ${t}px < 14px`);
});

test('escala do cliente: redefine os papéis compostos que usam os tamanhos pequenos', () => {
  // var() em propriedade customizada é resolvida onde é declarada: sem isto,
  // --type-caption continuaria com o 12px de :root.
  for (const papel of ['--type-body-sm', '--type-label', '--type-caption', '--type-overline']) {
    assert.match(css, new RegExp(`${papel}\\s*:`), `${papel} não redefinido em .ovo-root--cliente`);
  }
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `pnpm --filter @ovo/ui test`
Expected: **FAIL** — `ENOENT ... escala-cliente.css`.

- [ ] **Step 3: Criar `packages/ui/src/escala-cliente.css`**

```css
/* Área do cliente (site, portal do assinante): mínimo de 14px em qualquer texto.
   Usar junto de .ovo-root: <body class="ovo-root ovo-root--cliente">.
   Os papéis compostos são redeclarados aqui porque var() em propriedade
   customizada é resolvida onde a propriedade é declarada, não onde é usada. */
.ovo-root--cliente {
  --fs-3xs: 14px;
  --fs-2xs: 14px;
  --fs-xs: 14px;
  --fs-sm: 14px;
  --type-body-sm: var(--fw-regular) var(--fs-sm) / var(--lh-normal) var(--font-sans);
  --type-label: var(--fw-medium) var(--fs-sm) / 1.3 var(--font-sans);
  --type-caption: var(--fw-regular) var(--fs-xs) / 1.35 var(--font-sans);
  --type-overline: var(--fw-semibold) var(--fs-2xs) / 1.2 var(--font-sans);
}
```

- [ ] **Step 4: Criar `packages/ui/src/base.css`**

```css
/* Base escopada em .ovo-root: telas ainda não migradas não são afetadas.
   Cada app ganha a classe no <body> na sua própria etapa. */
.ovo-root {
  background: var(--surface-page);
  color: var(--text-body);
  font: var(--type-body);
  letter-spacing: var(--ls-normal);
  color-scheme: light;
  -webkit-font-smoothing: antialiased;
  text-wrap: pretty;
}
.ovo-root *,
.ovo-root *::before,
.ovo-root *::after { box-sizing: border-box; }
.ovo-root h1, .ovo-root h2, .ovo-root h3, .ovo-root h4, .ovo-root h5, .ovo-root h6 {
  margin: 0;
  color: var(--text-strong);
  letter-spacing: var(--ls-snug);
}
.ovo-root h1 { font: var(--type-h1); }
.ovo-root h2 { font: var(--type-h2); }
.ovo-root h3 { font: var(--type-h3); }
.ovo-root h4 { font: var(--type-h4); }
.ovo-root p { margin: 0; }
.ovo-root a { color: inherit; text-decoration: none; }
.ovo-root button, .ovo-root input, .ovo-root select, .ovo-root textarea { font: inherit; color: inherit; }
.ovo-root table { border-collapse: collapse; }
.ovo-root ::selection { background: var(--gold-200); color: var(--text-strong); }

/* Foco de teclado sempre visível, em qualquer elemento. */
.ovo-root :focus-visible {
  outline: 2px solid var(--border-focus);
  outline-offset: 2px;
}

/* Link de texto corrido: sublinhado sempre (não depender só de cor). */
.ovo-root .ovo-link {
  color: var(--text-link);
  text-decoration: underline;
  text-underline-offset: 3px;
  transition: var(--transition-control);
}
.ovo-root .ovo-link:hover { color: var(--text-link-hover); }
```

- [ ] **Step 5: Criar `packages/ui/src/fontes.ts`**

```ts
import { Archivo, IBM_Plex_Mono, Outfit } from 'next/font/google';

// next/font baixa as fontes no build e as serve do próprio domínio: sem
// requisição externa em tempo de execução. São substitutas do Google Fonts
// (a marca não enviou arquivos); para trocar por fontes licenciadas, edite só aqui.
const outfit = Outfit({ subsets: ['latin'], weight: ['400', '500', '600', '700'], variable: '--next-outfit', display: 'swap' });
const archivo = Archivo({ subsets: ['latin'], weight: ['400', '500', '600', '700'], variable: '--next-archivo', display: 'swap' });
const plexMono = IBM_Plex_Mono({ subsets: ['latin'], weight: ['400', '500', '600'], variable: '--next-plex', display: 'swap' });

/** Classes para o <html>: definem --next-outfit, --next-archivo e --next-plex. */
export const classeFontes = [outfit.variable, archivo.variable, plexMono.variable].join(' ');
```

- [ ] **Step 6: Ligar as variáveis do `next/font` aos tokens de fonte**

Em `packages/ui/src/tokens.css`, dentro do bloco **"Correções de contraste"**, adicionar no fim do `:root { ... }`:

```css
  --font-display: var(--next-outfit, 'Outfit'), 'Century Gothic', system-ui, sans-serif;
  --font-sans: var(--next-archivo, 'Archivo'), 'Helvetica Neue', system-ui, sans-serif;
  --font-mono: var(--next-plex, 'IBM Plex Mono'), ui-monospace, monospace;
```

(Esses são os únicos nomes de família literais permitidos; o teste de guardas da Task 3 libera `tokens.css`.)

- [ ] **Step 7: Criar `packages/ui/src/components.css` com cabeçalho**

```css
/* Biblioteca @ovo/ui — classes .ovo-*.
   Só var(--token): sem cor literal, sem família de fonte, sem px em font
   (tests/guardas.test.ts). Seções na ordem: utilitários, core, forms, data,
   navigation, feedback. */

@keyframes ovo-spin { to { transform: rotate(360deg); } }

/* ── Utilitários ───────────────────────────────────────────────────── */
.ovo-num { font-family: var(--font-mono); font-variant-numeric: tabular-nums; }
.ovo-overline {
  font: var(--type-overline);
  letter-spacing: var(--ls-caps);
  text-transform: uppercase;
  color: var(--text-muted);
}
.ovo-scroll::-webkit-scrollbar { width: 10px; height: 10px; }
.ovo-scroll::-webkit-scrollbar-thumb {
  background: var(--cream-500);
  border-radius: var(--radius-pill);
  border: 3px solid transparent;
  background-clip: content-box;
}
```

- [ ] **Step 8: Atualizar os três `layout.tsx`**

`apps/site/src/app/layout.tsx` (substituir o arquivo):

```tsx
import type { Metadata } from 'next';
import '@ovo/ui/tokens.css';
import '@ovo/ui/base.css';
import '@ovo/ui/escala-cliente.css';
import '@ovo/ui/components.css';
import './globals.css';
import { classeFontes } from '@ovo/ui/fontes';

export const metadata: Metadata = {
  title: 'Ovo di Onça — Ovos caipiras por assinatura',
  description: 'Ovos caipiras direto da fazenda, com frete grátis na área atendida. Assine em minutos.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" className={classeFontes}>
      <body>{children}</body>
    </html>
  );
}
```

`apps/assinante/src/app/layout.tsx` e `apps/gestao/src/app/layout.tsx`: manter `metadata` como está e trocar apenas as importações e a tag `<html>`:

```tsx
import type { Metadata } from 'next';
import '@ovo/ui/tokens.css';
import '@ovo/ui/base.css';
import '@ovo/ui/escala-cliente.css';   // só no assinante; NÃO importar na gestão
import '@ovo/ui/components.css';
import './globals.css';
import { classeFontes } from '@ovo/ui/fontes';
// ... metadata inalterado ...
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" className={classeFontes}>
      <body>{children}</body>
    </html>
  );
}
```

Na `gestao`, omitir a linha `escala-cliente.css`. Nenhum `<body>` ganha `ovo-root` ainda (isso é das Etapas 2–4).

- [ ] **Step 9: Rodar testes e checagens de tipo de todos os apps**

Run:
```bash
pnpm --filter @ovo/ui test
pnpm --filter @ovo/ui typecheck
pnpm typecheck
```
Expected: testes PASS; typecheck sem erros nos 4 pacotes.

- [ ] **Step 10: Provar que `next/font` funciona dentro do pacote (build do site)**

Run: `pnpm --filter @ovo/site build`
Expected: build conclui; a saída lista as rotas e não menciona erro de fonte. (Precisa de internet no build para baixar as fontes.)

Se falhar com `Font loaders must be called and assigned to a const in the module scope` ou `Module not found: next/font`: mover o conteúdo de `packages/ui/src/fontes.ts` para `apps/<app>/src/app/fontes.ts` nos três apps (mesmo código), trocar o import do layout para `./fontes`, apagar `packages/ui/src/fontes.ts` e a linha `"./fontes"` do `package.json`, e rodar o build de novo. Anotar a mudança no commit.

- [ ] **Step 11: Commit**

```bash
git add packages/ui apps/site/src/app/layout.tsx apps/assinante/src/app/layout.tsx apps/gestao/src/app/layout.tsx
git commit -m "feat(ui): fontes next/font, base escopada, escala do cliente e ligação nos apps

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Utilitários, ícones, Button e guardas

**Files:**
- Create: `packages/ui/src/cx.ts`, `packages/ui/src/core/icons.ts` (gerado), `packages/ui/src/core/Icon.tsx`, `packages/ui/src/core/Button.tsx`, `packages/ui/src/index.ts`
- Create: `packages/ui/tests/button.test.tsx`, `packages/ui/tests/guardas.test.ts`
- Modify: `packages/ui/src/components.css` (append), `packages/ui/package.json` (script `test`)

**Interfaces:**
- Produces: `cx(...partes: ClassValue[]): string`; `Icon({ name: IconName, size?, strokeWidth?, className?, ...svgProps })`; `type IconName`; `Button({ variant?: 'primary'|'secondary'|'ghost'|'inverse'|'danger', size?: 'sm'|'md'|'lg', icon?, iconAfter?, fullWidth?, loading?, type?: 'button'|'submit'|'reset' (padrão 'button'), href?, as?, ...buttonProps })`; `index.ts` exporta tudo.

- [ ] **Step 1: Gerar `icons.ts` a partir do Design System**

Run (raiz do repositório):
```bash
node -e "
const fs=require('node:fs');
const src=fs.readFileSync('Ovo di Onça Design System/components/core/Icon.jsx','utf8');
const m=src.match(/export const iconPaths = (\{[\s\S]*?\n\});/);
if(!m) throw new Error('iconPaths não encontrado');
fs.mkdirSync('packages/ui/src/core',{recursive:true});
fs.writeFileSync('packages/ui/src/core/icons.ts','// Gerado a partir do Design System (traçados derivados do Lucide, licença ISC).\n// Ícone novo: acrescente no fim, com o mesmo formato.\nexport const iconPaths = '+m[1]+' as const satisfies Record<string, readonly string[]>;\n\nexport type IconName = keyof typeof iconPaths;\n');
"
grep -c "^  " packages/ui/src/core/icons.ts
```
Expected: imprime um número ≥ 50 (linhas de ícones).

- [ ] **Step 2: Escrever os testes `packages/ui/tests/button.test.tsx`**

```tsx
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderToStaticMarkup } from 'react-dom/server';
import { Button } from '../src/core/Button';
import { Icon } from '../src/core/Icon';

test('Button: padrão é type="button" (não envia formulário sem pedir)', () => {
  const html = renderToStaticMarkup(<Button>Salvar</Button>);
  assert.match(html, /<button[^>]*type="button"/);
  assert.match(html, /ovo-btn--primary/);
  assert.match(html, /ovo-btn--md/);
});

test('Button: type="submit" é respeitado', () => {
  assert.match(renderToStaticMarkup(<Button type="submit">Enviar</Button>), /type="submit"/);
});

test('Button: loading desativa, marca aria-busy e troca o ícone inicial', () => {
  const html = renderToStaticMarkup(<Button loading icon="plus">Salvando</Button>);
  assert.match(html, /disabled=""/);
  assert.match(html, /aria-busy="true"/);
  assert.equal((html.match(/<svg/g) ?? []).length, 1);
});

test('Button: com href vira <a>; desativado vira aria-disabled sem tabindex ativo', () => {
  const ok = renderToStaticMarkup(<Button href="/assinar">Assinar</Button>);
  assert.match(ok, /^<a[^>]*href="\/assinar"/);
  const off = renderToStaticMarkup(<Button href="/assinar" disabled>Assinar</Button>);
  assert.match(off, /aria-disabled="true"/);
  assert.match(off, /tabindex="-1"/);
  assert.doesNotMatch(off, /\sdisabled=/);
});

test('Button: fullWidth, variante e tamanho viram classes', () => {
  const html = renderToStaticMarkup(<Button variant="danger" size="lg" fullWidth>Excluir</Button>);
  assert.match(html, /ovo-btn--danger/);
  assert.match(html, /ovo-btn--lg/);
  assert.match(html, /ovo-btn--block/);
});

test('Icon: nome desconhecido não quebra e continua escondido de leitor de tela', () => {
  const html = renderToStaticMarkup(<Icon name={'inexistente' as never} />);
  assert.match(html, /aria-hidden="true"/);
});
```

- [ ] **Step 3: Escrever os guardas `packages/ui/tests/guardas.test.ts`**

```ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { RAIZ } from './_tokens.ts';

const SRC = join(RAIZ, 'src');
const ler = (f: string) => readFileSync(f, 'utf8');
const semComentarios = (t: string) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|\s)\/\/.*$/gm, '$1');

function listar(dir: string): string[] {
  return readdirSync(dir).flatMap((n) => {
    const c = join(dir, n);
    return statSync(c).isDirectory() ? listar(c) : [c];
  });
}
const todos = listar(SRC);
const rel = (f: string) => relative(SRC, f).replaceAll('\\', '/');
const fonte = todos.filter((f) => /\.(css|ts|tsx)$/.test(f));

test('cor literal só existe em tokens.css', () => {
  const infratores = fonte
    .filter((f) => rel(f) !== 'tokens.css')
    .filter((f) => /#[0-9a-fA-F]{3,8}\b|\brgba?\(|\bhsla?\(/.test(semComentarios(ler(f))))
    .map(rel);
  assert.deepEqual(infratores, []);
});

test('família de fonte literal só existe em tokens.css e fontes.ts', () => {
  const infratores = fonte
    .filter((f) => !['tokens.css', 'fontes.ts'].includes(rel(f)))
    .filter((f) => /font-family\s*:\s*['"A-Za-z]|\b(Outfit|Archivo|Aclonica|Poppins|IBM Plex)\b/.test(semComentarios(ler(f)).replace(/font-family\s*:\s*var\([^)]*\)/g, '')))
    .map(rel);
  assert.deepEqual(infratores, []);
});

test('components.css: nenhum px literal em font/font-size (tamanhos vêm de --fs-*)', () => {
  const css = semComentarios(ler(join(SRC, 'components.css')));
  const ruins = [...css.matchAll(/font(?:-size)?\s*:[^;{}]*\b\d+(?:\.\d+)?px/g)].map((m) => m[0]);
  assert.deepEqual(ruins, []);
});

test('index.ts exporta todo componente de core/forms/data/navigation/feedback', () => {
  const indice = ler(join(SRC, 'index.ts'));
  const faltando = todos
    .filter((f) => /\/(core|forms|data|navigation|feedback)\/[A-Z]\w+\.tsx$/.test(f.replaceAll('\\', '/')))
    .map((f) => rel(f).replace(/\.tsx$/, ''))
    .filter((caminho) => !indice.includes(`./${caminho}`));
  assert.deepEqual(faltando, []);
});

test('toda classe .ovo-* usada nos .tsx existe em components.css', () => {
  const definidas = new Set<string>();
  for (const css of todos.filter((x) => x.endsWith('.css') && rel(x) !== 'tokens.css')) {
    for (const m of ler(css).matchAll(/\.(ovo-[\w-]+)/g)) definidas.add(m[1]!);
  }
  const faltando: string[] = [];
  for (const f of todos.filter((x) => x.endsWith('.tsx'))) {
    for (const m of semComentarios(ler(f)).matchAll(/\bovo-[\w-]+/g)) {
      const nome = m[0];
      if (nome.endsWith('-')) continue; // prefixo de classe montada com template (ex.: ovo-btn--${variant})
      if (!definidas.has(nome)) faltando.push(`${rel(f)}: ${nome}`);
    }
  }
  assert.deepEqual([...new Set(faltando)], []);
});

test('toda variante montada por template tem classe correspondente', () => {
  const css = ler(join(SRC, 'components.css'));
  const prefixos: Record<string, string[]> = {
    'ovo-btn--': ['primary', 'secondary', 'ghost', 'inverse', 'danger', 'sm', 'md', 'lg'],
  };
  for (const [prefixo, sufixos] of Object.entries(prefixos)) {
    for (const s of sufixos) assert.ok(css.includes(`.${prefixo}${s}`), `.${prefixo}${s} ausente`);
  }
  assert.ok(existsSync(join(SRC, 'components.css')));
});
```

- [ ] **Step 4: Atualizar o script `test` para incluir `.tsx` e rodar para ver falhar**

Em `packages/ui/package.json`, trocar a linha do script:

```json
    "test": "node --import tsx --test tests/*.test.ts tests/*.test.tsx"
```

Run: `pnpm --filter @ovo/ui test`
Expected: **FAIL** — `Cannot find module '../src/core/Button'` e falhas de guardas (`index.ts` inexistente).

- [ ] **Step 5: Criar `packages/ui/src/cx.ts`**

```ts
export type ClassValue = string | false | null | undefined;

/** Junta nomes de classe, ignorando valores falsos. */
export function cx(...partes: ClassValue[]): string {
  return partes.filter(Boolean).join(' ');
}
```

- [ ] **Step 6: Criar `packages/ui/src/core/Icon.tsx`**

```tsx
import type { SVGProps } from 'react';
import { cx } from '../cx';
import { iconPaths, type IconName } from './icons';

export type { IconName };

export type IconProps = Omit<SVGProps<SVGSVGElement>, 'name' | 'ref'> & {
  name: IconName;
  size?: number;
  strokeWidth?: number;
};

export function Icon({ name, size = 18, strokeWidth = 1.75, className, ...rest }: IconProps) {
  const caminhos: readonly string[] = iconPaths[name] ?? [];
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className={cx('ovo-icon', className)}
      {...rest}
    >
      {caminhos.map((d, i) => (
        <path key={i} d={d} />
      ))}
    </svg>
  );
}
```

- [ ] **Step 7: Criar `packages/ui/src/core/Button.tsx`**

```tsx
import type { ComponentPropsWithoutRef, ElementType } from 'react';
import { cx } from '../cx';
import { Icon, type IconName } from './Icon';

export type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'inverse' | 'danger';
export type ButtonSize = 'sm' | 'md' | 'lg';

const TAMANHO_ICONE: Record<ButtonSize, number> = { sm: 15, md: 17, lg: 19 };

export type ButtonProps = Omit<ComponentPropsWithoutRef<'button'>, 'type'> & {
  variant?: ButtonVariant;
  size?: ButtonSize;
  icon?: IconName;
  iconAfter?: IconName;
  fullWidth?: boolean;
  loading?: boolean;
  /** Padrão 'button': para enviar formulário, passe type="submit". */
  type?: 'button' | 'submit' | 'reset';
  /** Com href renderiza <a>. Para Next: as={Link}. */
  href?: string;
  as?: ElementType;
};

export function Button({
  variant = 'primary',
  size = 'md',
  icon,
  iconAfter,
  fullWidth,
  loading,
  disabled,
  type = 'button',
  href,
  as,
  className,
  children,
  ...rest
}: ButtonProps) {
  const desligado = Boolean(disabled || loading);
  const Tag: ElementType = as ?? (href ? 'a' : 'button');
  const nativo = Tag === 'button';
  const proprios = nativo
    ? { type, disabled: desligado }
    : { href, 'aria-disabled': desligado || undefined, tabIndex: desligado ? -1 : undefined };
  const inicio: IconName | undefined = loading ? 'refresh' : icon;
  return (
    <Tag
      className={cx('ovo-btn', `ovo-btn--${variant}`, `ovo-btn--${size}`, fullWidth && 'ovo-btn--block', className)}
      aria-busy={loading || undefined}
      {...proprios}
      {...rest}
    >
      {inicio && <Icon name={inicio} size={TAMANHO_ICONE[size]} />}
      {children}
      {iconAfter && <Icon name={iconAfter} size={TAMANHO_ICONE[size]} />}
    </Tag>
  );
}
```

- [ ] **Step 8: Criar `packages/ui/src/index.ts`**

```ts
export { cx } from './cx';
export { Icon } from './core/Icon';
export type { IconName, IconProps } from './core/Icon';
export { Button } from './core/Button';
export type { ButtonProps, ButtonSize, ButtonVariant } from './core/Button';
```

- [ ] **Step 9: Acrescentar o CSS de ícone e botão ao `components.css`**

Append:

```css
/* ── Icon ──────────────────────────────────────────────────────────── */
.ovo-icon { display: block; flex: none; }

/* ── Button ────────────────────────────────────────────────────────── */
.ovo-btn {
  display: inline-flex; align-items: center; justify-content: center;
  gap: var(--btn-gap); height: var(--btn-h); padding: 0 var(--btn-px);
  font: var(--fw-medium) var(--btn-fs) / 1 var(--font-sans);
  letter-spacing: var(--ls-snug); white-space: nowrap; text-decoration: none;
  border: 1px solid transparent; border-radius: var(--radius-control); cursor: pointer;
  transition: var(--transition-control), transform var(--dur-instant) var(--ease-standard);
}
.ovo-btn--sm { --btn-h: var(--control-height-sm); --btn-px: 12px; --btn-fs: var(--fs-sm); --btn-gap: 6px; }
.ovo-btn--md { --btn-h: var(--control-height-md); --btn-px: 16px; --btn-fs: var(--fs-md); --btn-gap: 8px; }
.ovo-btn--lg { --btn-h: var(--control-height-lg); --btn-px: 22px; --btn-fs: var(--fs-lg); --btn-gap: 10px; }
.ovo-btn--block { width: 100%; }
.ovo-btn--primary { background: var(--action-primary); color: var(--text-on-accent); border-color: var(--gold-500); box-shadow: var(--shadow-xs); }
.ovo-btn--primary:hover { background: var(--action-primary-hover); }
.ovo-btn--secondary { background: var(--surface-raised); color: var(--text-body); border-color: var(--border-control); }
.ovo-btn--secondary:hover { background: var(--action-secondary-hover); }
.ovo-btn--ghost { background: transparent; color: var(--text-body); }
.ovo-btn--ghost:hover { background: var(--action-ghost-hover); }
.ovo-btn--inverse { background: var(--surface-inverse); color: var(--text-on-inverse); border-color: var(--surface-inverse); }
.ovo-btn--inverse:hover { background: var(--surface-inverse-soft); }
.ovo-btn--danger { background: transparent; color: var(--text-danger); border-color: var(--clay-500); }
.ovo-btn--danger:hover { background: var(--surface-danger-soft); }
.ovo-btn:active { transform: scale(var(--press-scale)); }
.ovo-btn:disabled,
.ovo-btn[aria-disabled='true'] {
  background: var(--action-disabled-bg); color: var(--action-disabled-text);
  border-color: var(--border-subtle); box-shadow: none; cursor: not-allowed; transform: none;
}
a.ovo-btn[aria-disabled='true'] { pointer-events: none; }
.ovo-btn[aria-busy='true'] > .ovo-icon:first-child { animation: ovo-spin 1s linear infinite; }
```

- [ ] **Step 10: Rodar testes e tipos**

Run:
```bash
pnpm --filter @ovo/ui test
pnpm --filter @ovo/ui typecheck
```
Expected: **PASS** (guardas incluídos); typecheck limpo.

- [ ] **Step 11: Commit**

```bash
git add packages/ui
git commit -m "feat(ui): Icon, Button e guardas de tokens/fontes/classes

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Componentes core (Badge, Card, Avatar, IconButton, Tag, Tooltip)

**Files:**
- Create: `packages/ui/src/core/{Badge,Card,Avatar,IconButton,Tag,Tooltip}.tsx`
- Create: `packages/ui/tests/core.test.tsx`
- Modify: `packages/ui/src/index.ts`, `packages/ui/src/components.css` (append)

**Interfaces:**
- Consumes: `cx`, `Icon`, `IconName`.
- Produces: `Badge({ tone?: 'neutral'|'accent'|'success'|'warning'|'danger'|'inverse'|'olive'|'olive-soft', dot?, icon?, size?: 'sm'|'md' })`; `Card({ title?, subtitle?, action?, surface?: 'card'|'raised'|'highlight'|'inverse'|'olive'|'olive-soft'|'accent', padding?, compact?, interactive?, bodyClassName? })`; `Avatar({ name?, src?, size?: 'xs'|'sm'|'md'|'lg', tone?: 'brown'|'gold'|'olive'|'cream' })`; `IconButton({ icon, label, variant?, size?, active?, href?, as? })`; `Tag({ selected?, icon?, onClick?, onRemove? })` (`'use client'`); `Tooltip({ label, side? })`.

- [ ] **Step 1: Escrever `packages/ui/tests/core.test.tsx`**

```tsx
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderToStaticMarkup as html } from 'react-dom/server';
import { Avatar } from '../src/core/Avatar';
import { Badge } from '../src/core/Badge';
import { Card } from '../src/core/Card';
import { IconButton } from '../src/core/IconButton';
import { Tag } from '../src/core/Tag';
import { Tooltip } from '../src/core/Tooltip';

test('Badge: tom, tamanho e ponto', () => {
  const h = html(<Badge tone="success" size="sm" dot>Entregue</Badge>);
  assert.match(h, /ovo-badge--success/);
  assert.match(h, /ovo-badge--sm/);
  assert.match(h, /ovo-badge__dot/);
  assert.match(h, /Entregue/);
});

test('Card: título vira h3, subtítulo e ação aparecem, superfície vira classe', () => {
  const h = html(<Card title="Próxima entrega" subtitle="Quarta, 14/10" action={<a href="/x">Ver</a>} surface="olive">corpo</Card>);
  assert.match(h, /<h3[^>]*>Próxima entrega<\/h3>/);
  assert.match(h, /Quarta, 14\/10/);
  assert.match(h, /ovo-card--olive/);
  assert.match(h, /href="\/x"/);
  assert.match(h, /corpo/);
});

test('Card: sem título, subtítulo nem ação não renderiza cabeçalho', () => {
  assert.doesNotMatch(html(<Card>só corpo</Card>), /ovo-card__head/);
});

test('Card: padding numérico vira variável CSS (px)', () => {
  assert.match(html(<Card padding={32}>x</Card>), /--card-pad:32px/);
});

test('Avatar: iniciais de até duas palavras', () => {
  assert.match(html(<Avatar name="Maria da Silva" />), />MD</);
});

test('Avatar: nome vazio ou só espaços não quebra nem mostra "undefined"', () => {
  for (const nome of ['', '   ']) {
    const h = html(<Avatar name={nome} />);
    assert.doesNotMatch(h, /undefined/);
    assert.match(h, /ovo-avatar/);
  }
});

test('Avatar: com src usa <img> com alt do nome', () => {
  assert.match(html(<Avatar name="Ana" src="/ana.png" />), /<img[^>]*alt="Ana"/);
});

test('IconButton: exige rótulo acessível', () => {
  const h = html(<IconButton icon="bell" label="Notificações" />);
  assert.match(h, /aria-label="Notificações"/);
  assert.match(h, /type="button"/);
});

test('IconButton: com href vira link; desativado volta a ser botão desativado', () => {
  assert.match(html(<IconButton icon="x" label="Fechar" href="/" />), /^<a[^>]*href="\/"/);
  assert.match(html(<IconButton icon="x" label="Fechar" href="/" disabled />), /<button[^>]*disabled/);
});

test('Tag: clicável é botão acessível por teclado; removível tem botão com rótulo', () => {
  const h = html(<Tag selected onClick={() => {}} onRemove={() => {}}>Quinzenal</Tag>);
  assert.match(h, /role="button"/);
  assert.match(h, /tabindex="0"/);
  assert.match(h, /aria-pressed="true"/);
  assert.match(h, /aria-label="Remover"/);
});

test('Tag: sem onClick não vira botão', () => {
  assert.doesNotMatch(html(<Tag>Fixa</Tag>), /role="button"/);
});

test('Tooltip: balão com role e ligação aria-describedby', () => {
  const h = html(<Tooltip label="Copiar" side="bottom"><button type="button">c</button></Tooltip>);
  assert.match(h, /role="tooltip"/);
  assert.match(h, /ovo-tooltip__bubble--bottom/);
  const id = h.match(/aria-describedby="([^"]+)"/)?.[1];
  assert.ok(id && h.includes(`id="${id}"`));
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `pnpm --filter @ovo/ui test`
Expected: **FAIL** — módulos `../src/core/Badge` etc. não encontrados.

- [ ] **Step 3: Criar `packages/ui/src/core/Badge.tsx`**

```tsx
import type { ComponentPropsWithoutRef } from 'react';
import { cx } from '../cx';
import { Icon, type IconName } from './Icon';

export type BadgeTone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger' | 'inverse' | 'olive' | 'olive-soft';

export type BadgeProps = ComponentPropsWithoutRef<'span'> & {
  tone?: BadgeTone;
  dot?: boolean;
  icon?: IconName;
  size?: 'sm' | 'md';
};

export function Badge({ children, tone = 'neutral', dot, icon, size = 'md', className, ...rest }: BadgeProps) {
  return (
    <span className={cx('ovo-badge', `ovo-badge--${tone}`, size === 'sm' && 'ovo-badge--sm', className)} {...rest}>
      {dot && <span className="ovo-badge__dot" />}
      {icon && <Icon name={icon} size={size === 'sm' ? 12 : 13} />}
      {children}
    </span>
  );
}
```

- [ ] **Step 4: Criar `packages/ui/src/core/Card.tsx`**

```tsx
import type { ComponentPropsWithoutRef, CSSProperties, ReactNode } from 'react';
import { cx } from '../cx';

export type CardSurface = 'card' | 'raised' | 'highlight' | 'inverse' | 'olive' | 'olive-soft' | 'accent';

export type CardProps = Omit<ComponentPropsWithoutRef<'section'>, 'title'> & {
  title?: ReactNode;
  subtitle?: ReactNode;
  action?: ReactNode;
  surface?: CardSurface;
  /** Número = px; string = valor CSS. */
  padding?: number | string;
  compact?: boolean;
  interactive?: boolean;
  bodyClassName?: string;
};

export function Card({
  children,
  title,
  subtitle,
  action,
  surface = 'card',
  padding,
  compact,
  interactive,
  className,
  bodyClassName,
  style,
  ...rest
}: CardProps) {
  const folga = padding == null ? undefined : typeof padding === 'number' ? `${padding}px` : padding;
  const estilo = folga ? ({ ...style, '--card-pad': folga } as CSSProperties) : style;
  const temCabecalho = Boolean(title || subtitle || action);
  return (
    <section
      className={cx('ovo-card', `ovo-card--${surface}`, compact && 'ovo-card--compact', interactive && 'ovo-card--interactive', className)}
      style={estilo}
      {...rest}
    >
      {temCabecalho && (
        <header className={cx('ovo-card__head', Boolean(subtitle) && 'ovo-card__head--sub')}>
          <div className="ovo-card__heading">
            {title && <h3 className="ovo-card__title">{title}</h3>}
            {subtitle && <p className="ovo-card__sub">{subtitle}</p>}
          </div>
          {action}
        </header>
      )}
      <div className={cx('ovo-card__body', bodyClassName)}>{children}</div>
    </section>
  );
}
```

- [ ] **Step 5: Criar `packages/ui/src/core/Avatar.tsx`**

```tsx
import type { ComponentPropsWithoutRef } from 'react';
import { cx } from '../cx';

export type AvatarProps = ComponentPropsWithoutRef<'span'> & {
  name?: string;
  src?: string;
  size?: 'xs' | 'sm' | 'md' | 'lg';
  tone?: 'brown' | 'gold' | 'olive' | 'cream';
};

export function Avatar({ name = '', src, size = 'md', tone = 'brown', className, ...rest }: AvatarProps) {
  const iniciais = name
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((palavra) => palavra.charAt(0).toUpperCase())
    .join('');
  return (
    <span title={name || undefined} className={cx('ovo-avatar', `ovo-avatar--${size}`, `ovo-avatar--${tone}`, className)} {...rest}>
      {src ? <img src={src} alt={name} className="ovo-avatar__img" /> : iniciais}
    </span>
  );
}
```

- [ ] **Step 6: Criar `packages/ui/src/core/IconButton.tsx`**

```tsx
import type { ComponentPropsWithoutRef, ElementType } from 'react';
import { cx } from '../cx';
import { Icon, type IconName } from './Icon';

export type IconButtonProps = Omit<ComponentPropsWithoutRef<'button'>, 'children' | 'type'> & {
  icon: IconName;
  /** Obrigatório: é o nome acessível do botão. */
  label: string;
  variant?: 'ghost' | 'outline' | 'accent' | 'inverse';
  size?: 'sm' | 'md' | 'lg';
  active?: boolean;
  href?: string;
  as?: ElementType;
};

export function IconButton({ icon, label, variant = 'ghost', size = 'md', active, disabled, href, as, className, ...rest }: IconButtonProps) {
  const Tag: ElementType = as ?? (href && !disabled ? 'a' : 'button');
  const proprios = Tag === 'button' ? { type: 'button' as const, disabled } : { href };
  return (
    <Tag
      aria-label={label}
      title={label}
      className={cx('ovo-iconbtn', `ovo-iconbtn--${variant}`, `ovo-iconbtn--${size}`, active && 'ovo-iconbtn--active', className)}
      {...proprios}
      {...rest}
    >
      <Icon name={icon} size={size === 'sm' ? 16 : 18} />
    </Tag>
  );
}
```

- [ ] **Step 7: Criar `packages/ui/src/core/Tag.tsx`**

```tsx
'use client';

import type { ComponentPropsWithoutRef, KeyboardEvent, SyntheticEvent } from 'react';
import { cx } from '../cx';
import { Icon, type IconName } from './Icon';

export type TagProps = Omit<ComponentPropsWithoutRef<'span'>, 'onClick'> & {
  selected?: boolean;
  icon?: IconName;
  onClick?: (evento: SyntheticEvent<HTMLElement>) => void;
  onRemove?: (evento: SyntheticEvent<HTMLButtonElement>) => void;
};

export function Tag({ children, selected, icon, onClick, onRemove, className, ...rest }: TagProps) {
  const interativo = Boolean(onClick);
  const aoTeclar = (e: KeyboardEvent<HTMLElement>) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      onClick?.(e);
    }
  };
  return (
    <span
      role={interativo ? 'button' : undefined}
      tabIndex={interativo ? 0 : undefined}
      aria-pressed={interativo ? Boolean(selected) : undefined}
      onClick={onClick}
      onKeyDown={interativo ? aoTeclar : undefined}
      className={cx('ovo-tag', selected && 'ovo-tag--selected', interativo && 'ovo-tag--interactive', Boolean(onRemove) && 'ovo-tag--removable', className)}
      {...rest}
    >
      {icon && <Icon name={icon} size={14} />}
      {children}
      {onRemove && (
        <button
          type="button"
          aria-label="Remover"
          className="ovo-tag__remove"
          onClick={(e) => {
            e.stopPropagation();
            onRemove(e);
          }}
        >
          <Icon name="x" size={12} />
        </button>
      )}
    </span>
  );
}
```

- [ ] **Step 8: Criar `packages/ui/src/core/Tooltip.tsx`**

```tsx
import { useId, type ReactNode } from 'react';
import { cx } from '../cx';

export type TooltipProps = {
  children: ReactNode;
  label: ReactNode;
  side?: 'top' | 'bottom' | 'left' | 'right';
  className?: string;
};

export function Tooltip({ children, label, side = 'top', className }: TooltipProps) {
  const id = useId();
  return (
    <span className={cx('ovo-tooltip', className)} aria-describedby={id}>
      {children}
      <span role="tooltip" id={id} className={cx('ovo-tooltip__bubble', `ovo-tooltip__bubble--${side}`)}>
        {label}
      </span>
    </span>
  );
}
```

- [ ] **Step 9: Exportar no `index.ts`**

Append to `packages/ui/src/index.ts`:

```ts
export { Badge } from './core/Badge';
export type { BadgeProps, BadgeTone } from './core/Badge';
export { Card } from './core/Card';
export type { CardProps, CardSurface } from './core/Card';
export { Avatar } from './core/Avatar';
export type { AvatarProps } from './core/Avatar';
export { IconButton } from './core/IconButton';
export type { IconButtonProps } from './core/IconButton';
export { Tag } from './core/Tag';
export type { TagProps } from './core/Tag';
export { Tooltip } from './core/Tooltip';
export type { TooltipProps } from './core/Tooltip';
```

- [ ] **Step 10: Acrescentar o CSS ao `components.css`**

Append:

```css
/* ── Badge ─────────────────────────────────────────────────────────── */
.ovo-badge {
  display: inline-flex; align-items: center; gap: 6px; height: 24px; padding: 0 10px;
  border-radius: var(--radius-pill); border: 1px solid var(--badge-borda);
  background: var(--badge-fundo); color: var(--badge-texto);
  font: var(--fw-medium) var(--fs-xs) / 1 var(--font-sans);
  letter-spacing: var(--ls-wide); white-space: nowrap;
}
.ovo-badge--sm { height: 20px; padding: 0 8px; gap: 4px; font-size: var(--fs-2xs); }
.ovo-badge__dot { width: 6px; height: 6px; border-radius: 50%; background: currentColor; flex: none; }
.ovo-badge--neutral { --badge-fundo: var(--cream-300); --badge-texto: var(--text-body); --badge-borda: var(--border-default); }
.ovo-badge--accent { --badge-fundo: var(--surface-accent-soft); --badge-texto: var(--gold-700); --badge-borda: var(--gold-300); }
.ovo-badge--success { --badge-fundo: var(--surface-success-soft); --badge-texto: var(--green-700); --badge-borda: var(--green-300); }
.ovo-badge--warning { --badge-fundo: var(--surface-highlight); --badge-texto: var(--brown-700); --badge-borda: var(--cream-500); }
.ovo-badge--danger { --badge-fundo: var(--surface-danger-soft); --badge-texto: var(--red-700); --badge-borda: var(--red-300); }
.ovo-badge--inverse { --badge-fundo: var(--surface-inverse); --badge-texto: var(--text-on-inverse); --badge-borda: var(--surface-inverse); }
.ovo-badge--olive { --badge-fundo: var(--surface-olive); --badge-texto: var(--text-on-olive); --badge-borda: var(--olive-700); }
.ovo-badge--olive-soft { --badge-fundo: var(--surface-olive-soft); --badge-texto: var(--text-olive); --badge-borda: var(--border-olive); }

/* ── Card ──────────────────────────────────────────────────────────── */
.ovo-card {
  display: flex; flex-direction: column; min-width: 0;
  padding: var(--card-pad, var(--card-padding));
  background: var(--card-fundo); border: 1px solid var(--card-borda);
  border-radius: var(--radius-card); box-shadow: var(--card-sombra, none); color: var(--card-texto, inherit);
  transition: box-shadow var(--dur-normal) var(--ease-standard), transform var(--dur-normal) var(--ease-standard);
}
.ovo-card--compact { --card-pad: var(--card-padding-compact); }
.ovo-card--card { --card-fundo: var(--surface-card); --card-borda: var(--border-subtle); --card-sub: var(--text-muted); }
.ovo-card--raised { --card-fundo: var(--surface-raised); --card-borda: var(--border-subtle); --card-sombra: var(--shadow-sm); --card-sub: var(--text-muted); }
.ovo-card--highlight { --card-fundo: var(--surface-highlight); --card-borda: var(--cream-500); --card-sub: var(--text-body); }
.ovo-card--inverse { --card-fundo: var(--surface-inverse); --card-borda: var(--surface-inverse); --card-texto: var(--text-on-inverse); --card-sub: var(--text-on-inverse-muted); }
.ovo-card--olive { --card-fundo: var(--surface-olive); --card-borda: var(--olive-700); --card-texto: var(--text-on-olive); --card-sub: var(--text-on-olive-muted); }
.ovo-card--olive-soft { --card-fundo: var(--surface-olive-soft); --card-borda: var(--border-olive); --card-sub: var(--text-olive); }
.ovo-card--accent { --card-fundo: var(--surface-accent); --card-borda: var(--gold-500); --card-texto: var(--text-on-accent); --card-sub: var(--text-on-accent); }
.ovo-card--interactive { cursor: pointer; }
.ovo-card--interactive:hover { box-shadow: var(--shadow-md); transform: translateY(-1px); }
.ovo-card__head { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; margin-bottom: 14px; }
.ovo-card__head--sub { margin-bottom: 10px; }
.ovo-card__heading { min-width: 0; }
.ovo-card__title { font: var(--fw-semibold) var(--fs-lg) / 1.25 var(--font-display); color: inherit; letter-spacing: var(--ls-snug); }
.ovo-card__sub { font: var(--type-caption); color: var(--card-sub); margin-top: 3px; }
.ovo-card__body { min-width: 0; }

/* ── Avatar ────────────────────────────────────────────────────────── */
.ovo-avatar {
  width: var(--av); height: var(--av); border-radius: 50%; display: grid; place-items: center;
  overflow: hidden; flex: none; border: 1px solid var(--border-subtle);
  background: var(--av-fundo); color: var(--av-texto);
  font: var(--fw-semibold) calc(var(--av) * 0.36) / 1 var(--font-sans); letter-spacing: 0.02em;
}
.ovo-avatar--xs { --av: 24px; }
.ovo-avatar--sm { --av: 32px; }
.ovo-avatar--md { --av: 40px; }
.ovo-avatar--lg { --av: 56px; }
.ovo-avatar--brown { --av-fundo: var(--brown-500); --av-texto: var(--cream-100); }
.ovo-avatar--gold { --av-fundo: var(--gold-300); --av-texto: var(--brown-700); }
.ovo-avatar--olive { --av-fundo: var(--olive-500); --av-texto: var(--cream-100); }
.ovo-avatar--cream { --av-fundo: var(--cream-400); --av-texto: var(--brown-700); }
.ovo-avatar__img { width: 100%; height: 100%; object-fit: cover; }

/* ── IconButton ────────────────────────────────────────────────────── */
.ovo-iconbtn {
  width: var(--ib); height: var(--ib); display: inline-flex; align-items: center; justify-content: center;
  border: 1px solid transparent; border-radius: var(--radius-control); cursor: pointer; text-decoration: none;
  background: transparent; color: var(--text-body); transition: var(--transition-control);
}
.ovo-iconbtn--sm { --ib: 32px; }
.ovo-iconbtn--md { --ib: 40px; }
.ovo-iconbtn--lg { --ib: 44px; }
.ovo-iconbtn--ghost:hover, .ovo-iconbtn--active { background: var(--action-ghost-hover); }
.ovo-iconbtn--outline { background: var(--surface-raised); border-color: var(--border-control); }
.ovo-iconbtn--outline:hover { background: var(--action-secondary-hover); }
.ovo-iconbtn--accent { background: var(--action-primary); border-color: var(--gold-500); color: var(--text-on-accent); }
.ovo-iconbtn--accent:hover { background: var(--action-primary-hover); }
.ovo-iconbtn--inverse { background: var(--surface-inverse); border-color: var(--surface-inverse); color: var(--text-on-inverse); }
.ovo-iconbtn--inverse:hover { background: var(--surface-inverse-soft); }
.ovo-iconbtn:disabled { background: transparent; color: var(--action-disabled-text); cursor: not-allowed; }

/* ── Tag ───────────────────────────────────────────────────────────── */
.ovo-tag {
  display: inline-flex; align-items: center; gap: 6px; height: 30px; padding: 0 12px;
  border-radius: var(--radius-pill); border: 1px solid var(--border-control);
  background: var(--surface-raised); color: var(--text-body);
  font: var(--fw-medium) var(--fs-sm) / 1 var(--font-sans); transition: var(--transition-control);
}
.ovo-tag--removable { padding-right: 6px; }
.ovo-tag--interactive { cursor: pointer; }
.ovo-tag--interactive:hover { background: var(--action-secondary-hover); }
.ovo-tag--selected, .ovo-tag--selected:hover { background: var(--surface-inverse); border-color: var(--surface-inverse); color: var(--text-on-inverse); }
.ovo-tag__remove {
  width: 20px; height: 20px; display: grid; place-items: center; padding: 0;
  border: 0; background: transparent; color: inherit; border-radius: 50%; cursor: pointer;
}

/* ── Tooltip (só CSS: hover e foco) ────────────────────────────────── */
.ovo-tooltip { position: relative; display: inline-flex; }
.ovo-tooltip__bubble {
  position: absolute; z-index: 40; pointer-events: none; opacity: 0; white-space: nowrap;
  background: var(--surface-inverse); color: var(--text-on-inverse);
  font: var(--type-caption); padding: 6px 9px; border-radius: var(--radius-sm); box-shadow: var(--shadow-md);
  transition: opacity var(--dur-fast) var(--ease-standard);
}
.ovo-tooltip:hover .ovo-tooltip__bubble,
.ovo-tooltip:focus-within .ovo-tooltip__bubble { opacity: 1; }
.ovo-tooltip__bubble--top { bottom: 100%; left: 50%; transform: translateX(-50%); margin-bottom: 8px; }
.ovo-tooltip__bubble--bottom { top: 100%; left: 50%; transform: translateX(-50%); margin-top: 8px; }
.ovo-tooltip__bubble--left { right: 100%; top: 50%; transform: translateY(-50%); margin-right: 8px; }
.ovo-tooltip__bubble--right { left: 100%; top: 50%; transform: translateY(-50%); margin-left: 8px; }
```

- [ ] **Step 11: Rodar testes e tipos**

Run:
```bash
pnpm --filter @ovo/ui test
pnpm --filter @ovo/ui typecheck
```
Expected: **PASS**, typecheck limpo.

- [ ] **Step 12: Commit**

```bash
git add packages/ui
git commit -m "feat(ui): componentes core (Badge, Card, Avatar, IconButton, Tag, Tooltip)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Componentes de formulário

**Files:**
- Create: `packages/ui/src/forms/{Input,Textarea,Select,Checkbox,Radio,Switch,SearchField}.tsx`
- Create: `packages/ui/tests/forms.test.tsx`
- Modify: `packages/ui/src/index.ts`, `packages/ui/src/components.css` (append)

**Interfaces:**
- Consumes: `cx`, `Icon`, `IconName`.
- Produces: `Input({ label?, hint?, error?, icon?, suffix?, size?: 'sm'|'md'|'lg', wrapperClassName?, ...inputProps })`; `Textarea({ label?, hint?, error?, wrapperClassName?, ...textareaProps })`; `Select({ label?, hint?, error?, options: Array<string|{value:string;label:string}>, size?, wrapperClassName?, ...selectProps })`; `Checkbox({ label?, description?, indeterminate?, ...inputProps })`; `Radio({ label?, description?, ...inputProps })`; `Switch({ label?, description?, size?: 'sm'|'md', ...inputProps })`; `SearchField({ onClear?, shortcut?, size?: 'sm'|'md', wrapperClassName?, ...inputProps })`. Todos repassam `name`, `value`, `defaultValue`, `checked`, `defaultChecked`, `onChange` ao elemento nativo (funcionam em formulário de servidor).

- [ ] **Step 1: Escrever `packages/ui/tests/forms.test.tsx`**

```tsx
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderToStaticMarkup as html } from 'react-dom/server';
import { Checkbox } from '../src/forms/Checkbox';
import { Input } from '../src/forms/Input';
import { Radio } from '../src/forms/Radio';
import { SearchField } from '../src/forms/SearchField';
import { Select } from '../src/forms/Select';
import { Switch } from '../src/forms/Switch';
import { Textarea } from '../src/forms/Textarea';

test('Input: o rótulo aponta para o campo (for = id)', () => {
  const h = html(<Input label="E-mail" name="email" />);
  const para = h.match(/<label[^>]*for="([^"]+)"/)?.[1];
  assert.ok(para, 'label sem for');
  assert.match(h, new RegExp(`<input[^>]*id="${para}"`));
});

test('Input: dois campos na mesma página têm ids diferentes', () => {
  const h = html(<><Input label="A" /><Input label="B" /></>);
  const ids = [...h.matchAll(/<input[^>]*id="([^"]+)"/g)].map((m) => m[1]);
  assert.equal(new Set(ids).size, 2);
});

test('Input: erro vira aria-invalid + aria-describedby apontando para a mensagem', () => {
  const h = html(<Input label="CEP" error="Informe um CEP válido" />);
  assert.match(h, /aria-invalid="true"/);
  const alvo = h.match(/aria-describedby="([^"]+)"/)?.[1];
  assert.ok(alvo);
  assert.match(h, new RegExp(`id="${alvo}"[^>]*>Informe um CEP válido<`));
  assert.match(h, /ovo-field--error/);
});

test('Input: dica sem erro também é descrita, sem aria-invalid', () => {
  const h = html(<Input label="Telefone" hint="Com DDD" />);
  assert.match(h, /aria-describedby=/);
  assert.doesNotMatch(h, /aria-invalid/);
});

test('Input: repassa name, defaultValue e required ao <input> nativo', () => {
  const h = html(<Input label="Nome" name="nome" defaultValue="Ana" required />);
  assert.match(h, /name="nome"/);
  assert.match(h, /value="Ana"/);
  assert.match(h, /required=""/);
});

test('Textarea: rótulo, erro e linhas', () => {
  const h = html(<Textarea label="Observação" rows={4} error="Muito longo" />);
  assert.match(h, /<textarea[^>]*rows="4"/);
  assert.match(h, /aria-invalid="true"/);
  assert.match(h, /<label[^>]*for=/);
});

test('Select: aceita opções string e objeto', () => {
  const h = html(<Select label="Frequência" name="f" options={['semanal', { value: 'quinzenal', label: 'Quinzenal' }]} />);
  assert.match(h, /<option value="semanal">semanal<\/option>/);
  assert.match(h, /<option value="quinzenal">Quinzenal<\/option>/);
});

test('Select: sem opções renderiza um <select> vazio sem quebrar', () => {
  assert.match(html(<Select label="Bairro" options={[]} />), /<select[^>]*><\/select>/);
});

test('Checkbox: input nativo + indeterminado marcado como "mixed"', () => {
  const h = html(<Checkbox label="Todos" indeterminate />);
  assert.match(h, /type="checkbox"/);
  assert.match(h, /aria-checked="mixed"/);
  assert.match(h, /ovo-check--indeterminate/);
});

test('Radio: nativo, repassa name e value', () => {
  const h = html(<Radio label="Pix" name="forma" value="pix" defaultChecked />);
  assert.match(h, /type="radio"/);
  assert.match(h, /name="forma"/);
  assert.match(h, /value="pix"/);
  assert.match(h, /checked=""/);
});

test('Switch: role="switch" e descrição', () => {
  const h = html(<Switch label="Avisar por WhatsApp" description="Um dia antes" />);
  assert.match(h, /role="switch"/);
  assert.match(h, /Um dia antes/);
});

test('SearchField: botão limpar só aparece com valor e onClear', () => {
  assert.doesNotMatch(html(<SearchField value="" onChange={() => {}} onClear={() => {}} />), /aria-label="Limpar"/);
  assert.match(html(<SearchField value="ana" onChange={() => {}} onClear={() => {}} />), /aria-label="Limpar"/);
});

test('SearchField: sempre tem nome acessível (placeholder vira aria-label)', () => {
  assert.match(html(<SearchField placeholder="Buscar assinante" />), /aria-label="Buscar assinante"/);
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `pnpm --filter @ovo/ui test`
Expected: **FAIL** — módulos de `forms/` inexistentes.

- [ ] **Step 3: Criar `packages/ui/src/forms/Input.tsx`**

```tsx
import { useId, type ComponentPropsWithoutRef, type ReactNode } from 'react';
import { cx } from '../cx';
import { Icon, type IconName } from '../core/Icon';

export type InputProps = Omit<ComponentPropsWithoutRef<'input'>, 'size'> & {
  label?: ReactNode;
  hint?: ReactNode;
  error?: ReactNode;
  icon?: IconName;
  suffix?: ReactNode;
  size?: 'sm' | 'md' | 'lg';
  wrapperClassName?: string;
};

export function Input({ label, hint, error, icon, suffix, size = 'md', id, disabled, className, wrapperClassName, ...rest }: InputProps) {
  const automatico = useId();
  const inputId = id ?? automatico;
  const mensagemId = `${inputId}-msg`;
  const mensagem = error || hint;
  return (
    <div className={cx('ovo-field', `ovo-field--${size}`, Boolean(error) && 'ovo-field--error', Boolean(disabled) && 'ovo-field--disabled', wrapperClassName)}>
      {label && (
        <label htmlFor={inputId} className="ovo-field__label">
          {label}
        </label>
      )}
      <div className="ovo-field__box">
        {icon && <Icon name={icon} size={16} />}
        <input
          id={inputId}
          disabled={disabled}
          aria-invalid={error ? true : undefined}
          aria-describedby={mensagem ? mensagemId : undefined}
          className={cx('ovo-field__control', className)}
          {...rest}
        />
        {suffix && <span className="ovo-field__suffix">{suffix}</span>}
      </div>
      {mensagem && (
        <span id={mensagemId} className="ovo-field__msg">
          {mensagem}
        </span>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Criar `packages/ui/src/forms/Textarea.tsx`**

```tsx
import { useId, type ComponentPropsWithoutRef, type ReactNode } from 'react';
import { cx } from '../cx';

export type TextareaProps = ComponentPropsWithoutRef<'textarea'> & {
  label?: ReactNode;
  hint?: ReactNode;
  error?: ReactNode;
  wrapperClassName?: string;
};

export function Textarea({ label, hint, error, id, disabled, className, wrapperClassName, rows = 3, ...rest }: TextareaProps) {
  const automatico = useId();
  const campoId = id ?? automatico;
  const mensagemId = `${campoId}-msg`;
  const mensagem = error || hint;
  return (
    <div className={cx('ovo-field', 'ovo-field--md', Boolean(error) && 'ovo-field--error', Boolean(disabled) && 'ovo-field--disabled', wrapperClassName)}>
      {label && (
        <label htmlFor={campoId} className="ovo-field__label">
          {label}
        </label>
      )}
      <div className="ovo-field__box ovo-field__box--area">
        <textarea
          id={campoId}
          rows={rows}
          disabled={disabled}
          aria-invalid={error ? true : undefined}
          aria-describedby={mensagem ? mensagemId : undefined}
          className={cx('ovo-field__control ovo-field__control--area', className)}
          {...rest}
        />
      </div>
      {mensagem && (
        <span id={mensagemId} className="ovo-field__msg">
          {mensagem}
        </span>
      )}
    </div>
  );
}
```

- [ ] **Step 5: Criar `packages/ui/src/forms/Select.tsx`**

```tsx
import { useId, type ComponentPropsWithoutRef, type ReactNode } from 'react';
import { cx } from '../cx';
import { Icon } from '../core/Icon';

export type SelectOption = string | { value: string; label: string };

export type SelectProps = Omit<ComponentPropsWithoutRef<'select'>, 'size' | 'children'> & {
  label?: ReactNode;
  hint?: ReactNode;
  error?: ReactNode;
  options: SelectOption[];
  size?: 'sm' | 'md' | 'lg';
  wrapperClassName?: string;
};

export function Select({ label, hint, error, options, size = 'md', id, disabled, className, wrapperClassName, ...rest }: SelectProps) {
  const automatico = useId();
  const campoId = id ?? automatico;
  const mensagemId = `${campoId}-msg`;
  const mensagem = error || hint;
  return (
    <div className={cx('ovo-field', `ovo-field--${size}`, Boolean(error) && 'ovo-field--error', Boolean(disabled) && 'ovo-field--disabled', wrapperClassName)}>
      {label && (
        <label htmlFor={campoId} className="ovo-field__label">
          {label}
        </label>
      )}
      <div className="ovo-field__box ovo-field__box--select">
        <select
          id={campoId}
          disabled={disabled}
          aria-invalid={error ? true : undefined}
          aria-describedby={mensagem ? mensagemId : undefined}
          className={cx('ovo-field__control ovo-field__control--select', className)}
          {...rest}
        >
          {options.map((o) =>
            typeof o === 'string' ? (
              <option key={o} value={o}>
                {o}
              </option>
            ) : (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ),
          )}
        </select>
        <span className="ovo-field__chevron">
          <Icon name="chevron-down" size={16} />
        </span>
      </div>
      {mensagem && (
        <span id={mensagemId} className="ovo-field__msg">
          {mensagem}
        </span>
      )}
    </div>
  );
}
```

- [ ] **Step 6: Criar `packages/ui/src/forms/Checkbox.tsx`, `Radio.tsx` e `Switch.tsx`**

`Checkbox.tsx`:

```tsx
import type { ComponentPropsWithoutRef, ReactNode } from 'react';
import { cx } from '../cx';
import { Icon } from '../core/Icon';

export type CheckboxProps = Omit<ComponentPropsWithoutRef<'input'>, 'type' | 'size'> & {
  label?: ReactNode;
  description?: ReactNode;
  indeterminate?: boolean;
};

export function Checkbox({ label, description, indeterminate, disabled, className, ...rest }: CheckboxProps) {
  return (
    <label
      className={cx('ovo-check', Boolean(description) && 'ovo-check--described', Boolean(indeterminate) && 'ovo-check--indeterminate', Boolean(disabled) && 'ovo-check--disabled', className)}
    >
      <input type="checkbox" className="ovo-check__input" disabled={disabled} aria-checked={indeterminate ? 'mixed' : undefined} {...rest} />
      <span className="ovo-check__box" aria-hidden="true">
        <Icon name="check" size={13} strokeWidth={2.6} className="ovo-check__tick" />
        <Icon name="minus" size={13} strokeWidth={2.4} className="ovo-check__minus" />
      </span>
      {(label || description) && (
        <span className="ovo-check__text">
          {label && <span className="ovo-check__label">{label}</span>}
          {description && <span className="ovo-check__desc">{description}</span>}
        </span>
      )}
    </label>
  );
}
```

`Radio.tsx`:

```tsx
import type { ComponentPropsWithoutRef, ReactNode } from 'react';
import { cx } from '../cx';

export type RadioProps = Omit<ComponentPropsWithoutRef<'input'>, 'type' | 'size'> & {
  label?: ReactNode;
  description?: ReactNode;
};

export function Radio({ label, description, disabled, className, ...rest }: RadioProps) {
  return (
    <label className={cx('ovo-check', 'ovo-check--radio', Boolean(description) && 'ovo-check--described', Boolean(disabled) && 'ovo-check--disabled', className)}>
      <input type="radio" className="ovo-check__input" disabled={disabled} {...rest} />
      <span className="ovo-check__box" aria-hidden="true">
        <span className="ovo-check__dot" />
      </span>
      {(label || description) && (
        <span className="ovo-check__text">
          {label && <span className="ovo-check__label">{label}</span>}
          {description && <span className="ovo-check__desc">{description}</span>}
        </span>
      )}
    </label>
  );
}
```

`Switch.tsx`:

```tsx
import type { ComponentPropsWithoutRef, ReactNode } from 'react';
import { cx } from '../cx';

export type SwitchProps = Omit<ComponentPropsWithoutRef<'input'>, 'type' | 'size'> & {
  label?: ReactNode;
  description?: ReactNode;
  size?: 'sm' | 'md';
};

export function Switch({ label, description, size = 'md', disabled, className, ...rest }: SwitchProps) {
  return (
    <label className={cx('ovo-check', 'ovo-switch', `ovo-switch--${size}`, Boolean(description) && 'ovo-check--described', Boolean(disabled) && 'ovo-check--disabled', className)}>
      <input type="checkbox" role="switch" className="ovo-check__input" disabled={disabled} {...rest} />
      <span className="ovo-switch__track" aria-hidden="true">
        <span className="ovo-switch__knob" />
      </span>
      {(label || description) && (
        <span className="ovo-check__text">
          {label && <span className="ovo-check__label">{label}</span>}
          {description && <span className="ovo-check__desc">{description}</span>}
        </span>
      )}
    </label>
  );
}
```

- [ ] **Step 7: Criar `packages/ui/src/forms/SearchField.tsx`**

```tsx
import type { ComponentPropsWithoutRef } from 'react';
import { cx } from '../cx';
import { Icon } from '../core/Icon';

export type SearchFieldProps = Omit<ComponentPropsWithoutRef<'input'>, 'type' | 'size'> & {
  onClear?: () => void;
  shortcut?: string;
  size?: 'sm' | 'md';
  wrapperClassName?: string;
};

export function SearchField({ value, onClear, shortcut, size = 'md', placeholder = 'Buscar…', className, wrapperClassName, ...rest }: SearchFieldProps) {
  const temValor = value !== undefined && value !== null && String(value).length > 0;
  return (
    <div className={cx('ovo-search', `ovo-search--${size}`, wrapperClassName)}>
      <Icon name="search" size={16} />
      <input
        type="search"
        value={value}
        placeholder={placeholder}
        aria-label={rest['aria-label'] ?? placeholder}
        className={cx('ovo-search__input', className)}
        {...rest}
      />
      {temValor && onClear ? (
        <button type="button" aria-label="Limpar" className="ovo-search__clear" onClick={onClear}>
          <Icon name="x" size={14} />
        </button>
      ) : shortcut ? (
        <kbd className="ovo-search__kbd">{shortcut}</kbd>
      ) : null}
    </div>
  );
}
```

- [ ] **Step 8: Exportar no `index.ts`**

Append:

```ts
export { Input } from './forms/Input';
export type { InputProps } from './forms/Input';
export { Textarea } from './forms/Textarea';
export type { TextareaProps } from './forms/Textarea';
export { Select } from './forms/Select';
export type { SelectOption, SelectProps } from './forms/Select';
export { Checkbox } from './forms/Checkbox';
export type { CheckboxProps } from './forms/Checkbox';
export { Radio } from './forms/Radio';
export type { RadioProps } from './forms/Radio';
export { Switch } from './forms/Switch';
export type { SwitchProps } from './forms/Switch';
export { SearchField } from './forms/SearchField';
export type { SearchFieldProps } from './forms/SearchField';
```

- [ ] **Step 9: Acrescentar o CSS ao `components.css`**

Append:

```css
/* ── Campos (Input, Textarea, Select) ──────────────────────────────── */
.ovo-field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.ovo-field--sm { --field-h: var(--control-height-sm); }
.ovo-field--md { --field-h: var(--control-height-md); }
.ovo-field--lg { --field-h: var(--control-height-lg); }
.ovo-field__label { font: var(--type-label); color: var(--text-body); }
.ovo-field__box {
  position: relative; display: flex; align-items: center; gap: 8px; height: var(--field-h); padding: 0 12px;
  background: var(--surface-raised); border: 1px solid var(--border-control); border-radius: var(--radius-control);
  color: var(--text-muted); transition: var(--transition-control);
}
.ovo-field__box:focus-within { border-color: var(--border-focus); box-shadow: var(--ring-focus); }
.ovo-field--error .ovo-field__box { border-color: var(--clay-500); }
.ovo-field--error .ovo-field__box:focus-within { box-shadow: var(--ring-danger); }
.ovo-field--disabled .ovo-field__box { background: var(--surface-sunken); }
.ovo-field__control {
  flex: 1; min-width: 0; height: 100%; border: 0; outline: 0; background: transparent;
  font: var(--type-body); color: var(--text-body);
}
.ovo-root .ovo-field__control:focus-visible { outline: 0; }
.ovo-field__control::placeholder { color: var(--text-muted); }
.ovo-field__control:disabled { cursor: not-allowed; color: var(--text-muted); }
.ovo-field__suffix { font: var(--type-caption); color: var(--text-muted); white-space: nowrap; }
.ovo-field__msg { font: var(--type-caption); color: var(--text-muted); }
.ovo-field--error .ovo-field__msg { color: var(--text-danger); }
.ovo-field__box--area { height: auto; align-items: stretch; padding: 0; }
.ovo-field__control--area { padding: 10px 12px; resize: vertical; min-height: 72px; font: var(--type-body); }
.ovo-field__control--select { appearance: none; padding-right: 34px; cursor: pointer; }
.ovo-field__chevron { position: absolute; right: 11px; pointer-events: none; color: var(--text-muted); display: grid; }

/* ── Checkbox, Radio, Switch ───────────────────────────────────────── */
.ovo-check { position: relative; display: inline-flex; gap: 10px; align-items: center; min-height: 24px; cursor: pointer; }
.ovo-check--described { align-items: flex-start; }
.ovo-check--disabled { cursor: not-allowed; }
.ovo-check__input { position: absolute; opacity: 0; width: 1px; height: 1px; margin: 0; }
.ovo-check__box {
  width: 20px; height: 20px; flex: none; display: grid; place-items: center;
  background: var(--surface-raised); border: 1px solid var(--border-control); border-radius: var(--radius-xs);
  color: var(--text-on-accent); transition: var(--transition-control);
}
.ovo-check--described .ovo-check__box { margin-top: 1px; }
.ovo-check__tick, .ovo-check__minus, .ovo-check__dot { display: none; }
.ovo-check__input:checked + .ovo-check__box { background: var(--action-primary); border-color: var(--gold-500); }
.ovo-check__input:checked + .ovo-check__box .ovo-check__tick { display: block; }
.ovo-check--indeterminate .ovo-check__input + .ovo-check__box { background: var(--action-primary); border-color: var(--gold-500); }
.ovo-check--indeterminate .ovo-check__input + .ovo-check__box .ovo-check__tick { display: none; }
.ovo-check--indeterminate .ovo-check__input + .ovo-check__box .ovo-check__minus { display: block; }
.ovo-check--radio .ovo-check__box { border-radius: 50%; }
.ovo-check--radio .ovo-check__input:checked + .ovo-check__box { background: var(--surface-raised); border-color: var(--gold-700); }
.ovo-check--radio .ovo-check__input:checked + .ovo-check__box .ovo-check__dot {
  display: block; width: 10px; height: 10px; border-radius: 50%; background: var(--gold-700);
}
.ovo-check__input:focus-visible + .ovo-check__box,
.ovo-check__input:focus-visible + .ovo-switch__track { box-shadow: var(--ring-focus); }
.ovo-check__input:disabled + .ovo-check__box { background: var(--surface-sunken); }
.ovo-check__text { min-width: 0; }
.ovo-check__label { display: block; font: var(--type-body-sm); color: var(--text-body); }
.ovo-check--disabled .ovo-check__label { color: var(--action-disabled-text); }
.ovo-check__desc { display: block; font: var(--type-caption); color: var(--text-muted); margin-top: 2px; }
.ovo-switch--md { --sw-w: 44px; --sw-h: 24px; }
.ovo-switch--sm { --sw-w: 36px; --sw-h: 20px; }
.ovo-switch__track {
  --sw-k: calc(var(--sw-h) - 6px);
  position: relative; flex: none; width: var(--sw-w); height: var(--sw-h); border-radius: var(--radius-pill);
  background: var(--cream-400); border: 1px solid var(--border-control); transition: var(--transition-control);
}
.ovo-switch__knob {
  position: absolute; top: 2px; left: 2px; width: var(--sw-k); height: var(--sw-k); border-radius: 50%;
  background: var(--cream-50); box-shadow: var(--shadow-xs);
  transition: left var(--dur-fast) var(--ease-standard);
}
.ovo-check__input:checked + .ovo-switch__track { background: var(--action-primary); border-color: var(--gold-500); }
.ovo-check__input:checked + .ovo-switch__track .ovo-switch__knob { left: calc(var(--sw-w) - var(--sw-k) - 4px); }
.ovo-check__input:disabled + .ovo-switch__track { background: var(--surface-sunken); }

/* ── SearchField ───────────────────────────────────────────────────── */
.ovo-search {
  display: flex; align-items: center; gap: 8px; height: var(--search-h); padding: 0 10px 0 12px; min-width: 0;
  background: var(--surface-raised); border: 1px solid var(--border-control); border-radius: var(--radius-pill);
  color: var(--text-muted); transition: var(--transition-control);
}
.ovo-search--sm { --search-h: var(--control-height-sm); }
.ovo-search--md { --search-h: var(--control-height-md); }
.ovo-search:focus-within { border-color: var(--border-focus); box-shadow: var(--ring-focus); }
.ovo-search__input { flex: 1; min-width: 0; border: 0; outline: 0; background: transparent; font: var(--type-body-sm); color: var(--text-body); }
.ovo-root .ovo-search__input:focus-visible { outline: 0; }
.ovo-search__input::placeholder { color: var(--text-muted); }
.ovo-search__input::-webkit-search-cancel-button { display: none; }
.ovo-search__clear { display: grid; place-items: center; padding: 2px; border: 0; background: transparent; color: var(--text-muted); cursor: pointer; }
.ovo-search__kbd {
  font: var(--fw-medium) var(--fs-2xs) / 1 var(--font-mono); color: var(--text-muted); background: var(--cream-200);
  border: 1px solid var(--border-subtle); border-radius: var(--radius-xs); padding: 3px 5px;
}
```

- [ ] **Step 10: Rodar testes e tipos**

Run:
```bash
pnpm --filter @ovo/ui test
pnpm --filter @ovo/ui typecheck
```
Expected: **PASS**, typecheck limpo.

- [ ] **Step 11: Commit**

```bash
git add packages/ui
git commit -m "feat(ui): componentes de formulário (Input, Textarea, Select, Checkbox, Radio, Switch, SearchField)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Componentes de dados

**Files:**
- Create: `packages/ui/src/data/{ProgressBar,Trend,StatCard,BarChart,DataTable}.tsx`
- Create: `packages/ui/tests/data.test.tsx`
- Modify: `packages/ui/src/index.ts`, `packages/ui/src/components.css` (append)

**Interfaces:**
- Consumes: `cx`, `Icon`, `IconName`.
- Produces: `ProgressBar({ value?, max?, tone?: 'accent'|'success'|'danger'|'neutral'|'olive', label?, valueLabel?, height? })`; `Trend({ value: number, invert?, suffix?, showIcon?, size?: 'sm'|'md' })`; `StatCard({ label, value, unit?, trend?, trendInvert?, trendSuffix?, caption?, icon?: IconName, surface?: 'card'|'raised'|'highlight'|'inverse'|'olive'|'olive-soft' })`; `BarChart({ data: Array<{label:string;value:number;highlight?:boolean;muted?:boolean}>, height?, tone?, showValues?, formatValue? })`; `DataTable<T extends Record<string, unknown>>({ columns: DataTableColumn<T>[], rows: T[], emptyLabel?, caption?, cards? })` com `DataTableColumn<T> = { key: string; label: string; align?: 'left'|'right'|'center'; width?: number|string; numeric?: boolean; render?: (linha: T) => ReactNode }`.

- [ ] **Step 1: Escrever `packages/ui/tests/data.test.tsx`**

```tsx
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderToStaticMarkup as html } from 'react-dom/server';
import { BarChart } from '../src/data/BarChart';
import { DataTable } from '../src/data/DataTable';
import { ProgressBar } from '../src/data/ProgressBar';
import { StatCard } from '../src/data/StatCard';
import { Trend } from '../src/data/Trend';

const largura = (h: string) => h.match(/width:([^;"]+)/)?.[1];

test('ProgressBar: valor normal vira porcentagem', () => {
  assert.equal(largura(html(<ProgressBar value={25} max={50} />)), '50%');
});

test('ProgressBar: valor acima do máximo, negativo, NaN e max=0 nunca geram NaN/Infinity', () => {
  assert.equal(largura(html(<ProgressBar value={150} max={100} />)), '100%');
  assert.equal(largura(html(<ProgressBar value={-5} max={100} />)), '0%');
  assert.equal(largura(html(<ProgressBar value={Number.NaN} max={100} />)), '0%');
  assert.equal(largura(html(<ProgressBar value={10} max={0} />)), '0%');
  assert.equal(largura(html(<ProgressBar value={0} max={0} />)), '0%');
  assert.doesNotMatch(html(<ProgressBar value={Number.NaN} />), /NaN|Infinity/);
});

test('ProgressBar: role="progressbar" com limites e rótulo', () => {
  const h = html(<ProgressBar value={3} max={4} label="Entregas do mês" valueLabel="3/4" />);
  assert.match(h, /role="progressbar"/);
  assert.match(h, /aria-valuenow="3"/);
  assert.match(h, /aria-valuemax="4"/);
  assert.match(h, /aria-label="Entregas do mês"/);
});

test('Trend: formato pt-BR com sinal explícito', () => {
  assert.match(html(<Trend value={1.5} />), /\+1,5%/);
  assert.match(html(<Trend value={-2} />), /-2%/);
  assert.match(html(<Trend value={0} />), />0%</);
});

test('Trend: bom/ruim respeita invert; NaN vira travessão', () => {
  assert.match(html(<Trend value={5} />), /ovo-trend--good/);
  assert.match(html(<Trend value={5} invert />), /ovo-trend--bad/);
  assert.match(html(<Trend value={0} />), /ovo-trend--neutral/);
  const h = html(<Trend value={Number.NaN} />);
  assert.match(h, /—/);
  assert.doesNotMatch(h, /NaN/);
});

test('StatCard: rótulo, valor, unidade, delta e legenda', () => {
  const h = html(<StatCard label="Assinaturas ativas" value="842" unit="clientes" trend={12} caption="vs. semana anterior" icon="users" />);
  assert.match(h, /Assinaturas ativas/);
  assert.match(h, /842/);
  assert.match(h, /clientes/);
  assert.match(h, /\+12%/);
  assert.match(h, /vs\. semana anterior/);
});

test('StatCard: sem delta e sem legenda não renderiza rodapé', () => {
  assert.doesNotMatch(html(<StatCard label="X" value="1" />), /ovo-statcard__foot/);
});

test('BarChart: lista vazia não quebra e não gera NaN', () => {
  const h = html(<BarChart data={[]} />);
  assert.match(h, /ovo-bars/);
  assert.doesNotMatch(h, /NaN|Infinity/);
});

test('BarChart: barra de valor zero ainda tem altura mínima visível', () => {
  assert.match(html(<BarChart data={[{ label: 'Seg', value: 0 }, { label: 'Ter', value: 10 }]} />), /height:4px/);
});

type Linha = { id: number; cliente: string; total: number };
const colunas = [
  { key: 'cliente', label: 'Cliente' },
  { key: 'total', label: 'Total', numeric: true, align: 'right' as const, render: (l: Linha) => `R$ ${l.total}` },
];

test('DataTable: cabeçalho com escopo, células com data-label e coluna numérica', () => {
  const h = html(<DataTable<Linha> columns={colunas} rows={[{ id: 1, cliente: 'Ana', total: 82 }]} />);
  assert.match(h, /<th[^>]*scope="col"/);
  assert.match(h, /data-label="Cliente"/);
  assert.match(h, /R\$ 82/);
  assert.match(h, /ovo-table__cell--numeric/);
  assert.match(h, /ovo-table__cell--right/);
});

test('DataTable: sem linhas mostra a mensagem vazia ocupando todas as colunas', () => {
  const h = html(<DataTable<Linha> columns={colunas} rows={[]} emptyLabel="Nenhum cliente neste filtro" />);
  assert.match(h, /colSpan="2"|colspan="2"/);
  assert.match(h, /Nenhum cliente neste filtro/);
});

test('DataTable: linha sem id não gera aviso de chave e continua renderizando', () => {
  const h = html(<DataTable columns={[{ key: 'nome', label: 'Nome' }]} rows={[{ nome: 'A' }, { nome: 'B' }]} />);
  assert.match(h, />A</);
  assert.match(h, />B</);
});

test('DataTable: modo cartões é o padrão e pode ser desligado', () => {
  assert.match(html(<DataTable columns={colunas} rows={[]} />), /ovo-table--cards/);
  assert.doesNotMatch(html(<DataTable columns={colunas} rows={[]} cards={false} />), /ovo-table--cards/);
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `pnpm --filter @ovo/ui test`
Expected: **FAIL** — módulos de `data/` inexistentes.

- [ ] **Step 3: Criar `packages/ui/src/data/ProgressBar.tsx`**

```tsx
import type { ReactNode } from 'react';
import { cx } from '../cx';

export type ProgressBarProps = {
  value?: number;
  max?: number;
  tone?: 'accent' | 'success' | 'danger' | 'neutral' | 'olive';
  label?: ReactNode;
  valueLabel?: ReactNode;
  height?: number;
  className?: string;
};

export function ProgressBar({ value = 0, max = 100, tone = 'accent', label, valueLabel, height = 8, className }: ProgressBarProps) {
  const valido = Number.isFinite(value) && Number.isFinite(max) && max > 0;
  const porcento = valido ? Math.max(0, Math.min(100, (value / max) * 100)) : 0;
  return (
    <div className={cx('ovo-progress', className)}>
      {(label || valueLabel) && (
        <div className="ovo-progress__legend">
          <span>{label}</span>
          <span className="ovo-num ovo-progress__value">{valueLabel}</span>
        </div>
      )}
      <div
        role="progressbar"
        aria-valuenow={Number.isFinite(value) ? value : undefined}
        aria-valuemin={0}
        aria-valuemax={Number.isFinite(max) ? max : undefined}
        aria-label={typeof label === 'string' ? label : undefined}
        className="ovo-progress__track"
        style={{ height }}
      >
        <div className={cx('ovo-progress__fill', `ovo-progress__fill--${tone}`)} style={{ width: `${porcento}%` }} />
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Criar `packages/ui/src/data/Trend.tsx`**

```tsx
import { cx } from '../cx';
import { Icon } from '../core/Icon';

const formato = new Intl.NumberFormat('pt-BR');

export type TrendProps = {
  value: number;
  /** Quando menor é melhor (ex.: devoluções). */
  invert?: boolean;
  suffix?: string;
  showIcon?: boolean;
  size?: 'sm' | 'md';
  className?: string;
};

export function Trend({ value, invert, suffix = '%', showIcon = true, size = 'md', className }: TrendProps) {
  if (!Number.isFinite(value)) {
    return <span className={cx('ovo-trend', 'ovo-trend--neutral', `ovo-trend--${size}`, className)}>—</span>;
  }
  const subiu = value > 0;
  const bom = invert ? !subiu : subiu;
  const tom = value === 0 ? 'neutral' : bom ? 'good' : 'bad';
  const texto = `${subiu ? '+' : ''}${formato.format(value === 0 ? 0 : value)}${suffix}`;
  return (
    <span className={cx('ovo-trend', `ovo-trend--${tom}`, `ovo-trend--${size}`, className)}>
      {showIcon && value !== 0 && <Icon name={subiu ? 'trending-up' : 'trending-down'} size={size === 'sm' ? 13 : 15} />}
      {texto}
    </span>
  );
}
```

- [ ] **Step 5: Criar `packages/ui/src/data/StatCard.tsx`**

```tsx
import type { ReactNode } from 'react';
import { cx } from '../cx';
import { Icon, type IconName } from '../core/Icon';
import { Trend } from './Trend';

export type StatCardSurface = 'card' | 'raised' | 'highlight' | 'inverse' | 'olive' | 'olive-soft';

export type StatCardProps = {
  label: ReactNode;
  value: ReactNode;
  unit?: ReactNode;
  trend?: number;
  trendInvert?: boolean;
  trendSuffix?: string;
  caption?: ReactNode;
  icon?: IconName;
  surface?: StatCardSurface;
  className?: string;
};

export function StatCard({ label, value, unit, trend, trendInvert, trendSuffix, caption, icon, surface = 'card', className }: StatCardProps) {
  return (
    <div className={cx('ovo-statcard', `ovo-statcard--${surface}`, className)}>
      <div className="ovo-statcard__top">
        <span className="ovo-overline ovo-statcard__label">{label}</span>
        {icon && <Icon name={icon} size={17} />}
      </div>
      <div className="ovo-statcard__main">
        <span className="ovo-statcard__value">{value}</span>
        {unit && <span className="ovo-statcard__unit">{unit}</span>}
      </div>
      {(trend != null || caption) && (
        <div className="ovo-statcard__foot">
          {trend != null && (
            <span className="ovo-statcard__trend">
              <Trend value={trend} invert={trendInvert} suffix={trendSuffix} size="sm" />
            </span>
          )}
          {caption && <span className="ovo-statcard__caption">{caption}</span>}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 6: Criar `packages/ui/src/data/BarChart.tsx`**

```tsx
import { cx } from '../cx';

export type BarChartItem = { label: string; value: number; highlight?: boolean; muted?: boolean };

export type BarChartProps = {
  data: BarChartItem[];
  height?: number;
  tone?: 'accent' | 'neutral' | 'success';
  showValues?: boolean;
  formatValue?: (valor: number) => string;
  className?: string;
};

export function BarChart({ data, height = 180, tone = 'accent', showValues = true, formatValue, className }: BarChartProps) {
  const maximo = Math.max(...data.map((d) => (Number.isFinite(d.value) ? d.value : 0)), 1);
  return (
    <div className={cx('ovo-bars', className)}>
      <div className="ovo-bars__plot" style={{ height }}>
        {data.map((d, i) => {
          const valor = Number.isFinite(d.value) ? d.value : 0;
          const alturaBarra = Math.max(4, (valor / maximo) * (height - 26));
          return (
            <div key={`${d.label}-${i}`} className="ovo-bars__col">
              {showValues && <span className="ovo-bars__value ovo-num">{formatValue ? formatValue(valor) : valor}</span>}
              <div
                title={`${d.label}: ${valor}`}
                className={cx('ovo-bars__bar', `ovo-bars__bar--${tone}`, d.highlight && 'ovo-bars__bar--highlight', d.muted && 'ovo-bars__bar--muted')}
                style={{ height: alturaBarra }}
              />
            </div>
          );
        })}
      </div>
      <div className="ovo-bars__axis">
        {data.map((d, i) => (
          <span key={`${d.label}-${i}`} className="ovo-bars__tick">
            {d.label}
          </span>
        ))}
      </div>
    </div>
  );
}
```

- [ ] **Step 7: Criar `packages/ui/src/data/DataTable.tsx`**

```tsx
import type { ReactNode } from 'react';
import { cx } from '../cx';

export type DataTableColumn<T> = {
  key: string;
  label: string;
  align?: 'left' | 'right' | 'center';
  width?: number | string;
  /** Fonte monoespaçada com algarismos tabulares. */
  numeric?: boolean;
  render?: (linha: T) => ReactNode;
};

export type DataTableProps<T extends Record<string, unknown>> = {
  columns: DataTableColumn<T>[];
  rows: T[];
  emptyLabel?: string;
  caption?: string;
  /** No celular, cada linha vira um cartão (rótulo | valor). Padrão: ligado. */
  cards?: boolean;
  className?: string;
};

export function DataTable<T extends Record<string, unknown>>({ columns, rows, emptyLabel = 'Nenhum registro', caption, cards = true, className }: DataTableProps<T>) {
  return (
    <div className={cx('ovo-table', 'ovo-scroll', cards && 'ovo-table--cards', className)}>
      <table className="ovo-table__table">
        {caption && <caption className="ovo-table__caption">{caption}</caption>}
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.key} scope="col" className={cx('ovo-table__th', c.align && `ovo-table__cell--${c.align}`)} style={c.width != null ? { width: c.width } : undefined}>
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 ? (
            <tr>
              <td className="ovo-table__empty" colSpan={columns.length}>
                {emptyLabel}
              </td>
            </tr>
          ) : (
            rows.map((linha, i) => {
              const id = linha['id'];
              return (
                <tr key={typeof id === 'string' || typeof id === 'number' ? id : i} className="ovo-table__row">
                  {columns.map((c) => (
                    <td key={c.key} data-label={c.label} className={cx('ovo-table__td', c.numeric && 'ovo-table__cell--numeric', c.align && `ovo-table__cell--${c.align}`)}>
                      {c.render ? c.render(linha) : (linha[c.key] as ReactNode)}
                    </td>
                  ))}
                </tr>
              );
            })
          )}
        </tbody>
      </table>
    </div>
  );
}
```

- [ ] **Step 8: Exportar no `index.ts`**

Append:

```ts
export { ProgressBar } from './data/ProgressBar';
export type { ProgressBarProps } from './data/ProgressBar';
export { Trend } from './data/Trend';
export type { TrendProps } from './data/Trend';
export { StatCard } from './data/StatCard';
export type { StatCardProps, StatCardSurface } from './data/StatCard';
export { BarChart } from './data/BarChart';
export type { BarChartItem, BarChartProps } from './data/BarChart';
export { DataTable } from './data/DataTable';
export type { DataTableColumn, DataTableProps } from './data/DataTable';
```

- [ ] **Step 9: Acrescentar o CSS ao `components.css`**

Append:

```css
/* ── ProgressBar ───────────────────────────────────────────────────── */
.ovo-progress { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.ovo-progress__legend { display: flex; justify-content: space-between; gap: 8px; font: var(--type-caption); color: var(--text-muted); }
.ovo-progress__value { color: var(--text-body); }
.ovo-progress__track { background: var(--data-track); border-radius: var(--radius-pill); overflow: hidden; }
.ovo-progress__fill { height: 100%; border-radius: var(--radius-pill); transition: width var(--dur-slow) var(--ease-out); }
.ovo-progress__fill--accent { background: var(--gold-400); }
.ovo-progress__fill--success { background: var(--data-positive); }
.ovo-progress__fill--danger { background: var(--data-negative); }
.ovo-progress__fill--neutral { background: var(--brown-500); }
.ovo-progress__fill--olive { background: var(--olive-500); }

/* ── Trend ─────────────────────────────────────────────────────────── */
.ovo-trend { display: inline-flex; align-items: center; gap: 4px; font-family: var(--font-mono); font-weight: var(--fw-semibold); font-variant-numeric: tabular-nums; line-height: 1; }
.ovo-trend--md { font-size: var(--fs-sm); }
.ovo-trend--sm { font-size: var(--fs-xs); }
.ovo-trend--good { color: var(--text-success); }
.ovo-trend--bad { color: var(--text-danger); }
.ovo-trend--neutral { color: var(--text-muted); }

/* ── StatCard ──────────────────────────────────────────────────────── */
.ovo-statcard {
  display: flex; flex-direction: column; gap: 10px; min-width: 0; padding: var(--card-padding);
  background: var(--stat-fundo); border: 1px solid var(--stat-borda); border-radius: var(--radius-card);
  color: var(--stat-tinta);
}
.ovo-statcard--card { --stat-fundo: var(--surface-card); --stat-borda: var(--border-subtle); --stat-tinta: var(--text-strong); --stat-suave: var(--text-muted); }
.ovo-statcard--raised { --stat-fundo: var(--surface-raised); --stat-borda: var(--border-subtle); --stat-tinta: var(--text-strong); --stat-suave: var(--text-muted); }
.ovo-statcard--highlight { --stat-fundo: var(--surface-highlight); --stat-borda: var(--cream-500); --stat-tinta: var(--text-strong); --stat-suave: var(--text-body); }
.ovo-statcard--inverse { --stat-fundo: var(--surface-inverse); --stat-borda: var(--surface-inverse); --stat-tinta: var(--text-on-inverse); --stat-suave: var(--text-on-inverse-muted); }
.ovo-statcard--olive { --stat-fundo: var(--surface-olive); --stat-borda: var(--olive-700); --stat-tinta: var(--text-on-inverse); --stat-suave: var(--text-on-olive-muted); }
.ovo-statcard--olive-soft { --stat-fundo: var(--surface-olive-soft); --stat-borda: var(--border-olive); --stat-tinta: var(--text-strong); --stat-suave: var(--text-olive); }
.ovo-statcard__top { display: flex; align-items: center; justify-content: space-between; gap: 8px; color: var(--stat-suave); }
.ovo-statcard__label { color: inherit; }
.ovo-statcard__main { display: flex; align-items: baseline; gap: 6px; flex-wrap: wrap; }
.ovo-statcard__value { font: var(--type-metric); color: var(--stat-tinta); font-variant-numeric: tabular-nums; }
.ovo-statcard__unit { font: var(--type-body-sm); color: var(--stat-suave); }
.ovo-statcard__foot { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.ovo-statcard__caption { font: var(--type-caption); color: var(--stat-suave); }
.ovo-statcard--olive .ovo-statcard__trend { display: inline-flex; background: var(--surface-olive-soft); border-radius: var(--radius-pill); padding: 3px 8px; }
.ovo-statcard--olive .ovo-trend--bad { color: var(--red-700); }

/* ── BarChart ──────────────────────────────────────────────────────── */
.ovo-bars { display: flex; flex-direction: column; gap: 10px; min-width: 0; }
.ovo-bars__plot { display: flex; align-items: flex-end; gap: 10px; border-bottom: 1px solid var(--data-grid); padding-bottom: 1px; }
.ovo-bars__col { flex: 1; min-width: 0; display: flex; flex-direction: column; align-items: center; justify-content: flex-end; gap: 6px; }
.ovo-bars__value { font-size: var(--fs-2xs); font-weight: var(--fw-medium); color: var(--text-muted); }
.ovo-bars__bar { width: 100%; max-width: 46px; border-radius: 6px 6px 2px 2px; transition: height var(--dur-slow) var(--ease-out); }
.ovo-bars__bar--accent { background: var(--data-1); }
.ovo-bars__bar--neutral { background: var(--data-2); }
.ovo-bars__bar--success { background: var(--data-positive); }
.ovo-bars__bar--highlight { background: var(--data-5); }
.ovo-bars__bar--muted { opacity: 0.45; }
.ovo-bars__axis { display: flex; gap: 10px; }
.ovo-bars__tick { flex: 1; text-align: center; font: var(--type-caption); color: var(--text-muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

/* ── DataTable ─────────────────────────────────────────────────────── */
.ovo-table { overflow-x: auto; border: 1px solid var(--border-subtle); border-radius: var(--radius-card); background: var(--surface-raised); }
.ovo-table__table { width: 100%; min-width: 640px; }
.ovo-table__caption { padding: 12px 14px; text-align: left; font: var(--type-caption); color: var(--text-muted); }
.ovo-table__th {
  height: 40px; padding: 0 14px; text-align: left; white-space: nowrap;
  font: var(--type-overline); letter-spacing: var(--ls-caps); text-transform: uppercase;
  color: var(--text-on-sunken); background: var(--surface-sunken);
}
.ovo-table__row { border-top: 1px solid var(--border-subtle); transition: background-color var(--dur-fast) var(--ease-standard); }
.ovo-table__row:hover { background: var(--cream-100); }
.ovo-table__td { padding: 12px 14px; vertical-align: middle; font: var(--type-body-sm); color: var(--text-body); }
.ovo-table__cell--right { text-align: right; }
.ovo-table__cell--center { text-align: center; }
.ovo-table__cell--numeric { font: var(--type-numeric); font-variant-numeric: tabular-nums; }
.ovo-table__empty { padding: 32px 14px; text-align: center; font: var(--type-body-sm); color: var(--text-muted); }
@media (max-width: 640px) {
  .ovo-table--cards .ovo-table__table { min-width: 0; }
  .ovo-table--cards thead { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }
  .ovo-table--cards .ovo-table__row { display: block; padding: var(--space-4) 0; }
  .ovo-table--cards .ovo-table__td { display: flex; justify-content: space-between; gap: var(--space-5); padding: var(--space-2) 14px; text-align: right; }
  .ovo-table--cards .ovo-table__td::before {
    content: attr(data-label); text-align: left; font: var(--type-overline);
    letter-spacing: var(--ls-caps); text-transform: uppercase; color: var(--text-on-sunken);
  }
  .ovo-table--cards .ovo-table__empty { display: block; }
  .ovo-table--cards .ovo-table__empty::before { content: none; }
}
```

- [ ] **Step 10: Rodar testes e tipos**

Run:
```bash
pnpm --filter @ovo/ui test
pnpm --filter @ovo/ui typecheck
```
Expected: **PASS**, typecheck limpo.

- [ ] **Step 11: Commit**

```bash
git add packages/ui
git commit -m "feat(ui): componentes de dados (ProgressBar, Trend, StatCard, BarChart, DataTable)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Componentes de navegação

**Files:**
- Create: `packages/ui/src/navigation/{Sidebar,Tabs,TopBar,BottomNav,Pagination}.tsx`
- Create: `packages/ui/tests/navigation.test.tsx`
- Modify: `packages/ui/src/index.ts`, `packages/ui/src/components.css` (append)

**Interfaces:**
- Consumes: `cx`, `Icon`, `IconName`, `IconButton`.
- Produces: `Sidebar({ items: SidebarItem[], activeId?, collapsed?, brand?, footer?, LinkComponent? })` com `SidebarItem = { id; label; icon: IconName; href; badge?: number|string } | { section: string }`; `Tabs({ items: Array<{id;label;count?;href?}>, activeId?, onChange?, variant?: 'underline'|'pill', LinkComponent? })`; `TopBar({ title?, subtitle?, breadcrumb?, search?, actions?, left? })`; `BottomNav({ items: Array<{id;label;icon;href;badge?:boolean}>, activeId?, LinkComponent? })`; `Pagination({ page?, pageCount?, total?, pageSize?, hrefFor?: (p:number)=>string, onChange?: (p:number)=>void })`. Navegação é por `href`; item ativo recebe `aria-current="page"`.

- [ ] **Step 1: Escrever `packages/ui/tests/navigation.test.tsx`**

```tsx
import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { ReactNode } from 'react';
import { renderToStaticMarkup as html } from 'react-dom/server';
import { BottomNav } from '../src/navigation/BottomNav';
import { Pagination } from '../src/navigation/Pagination';
import { Sidebar } from '../src/navigation/Sidebar';
import { Tabs } from '../src/navigation/Tabs';
import { TopBar } from '../src/navigation/TopBar';

const itens = [
  { section: 'Operação' },
  { id: 'clientes', label: 'Clientes', icon: 'users' as const, href: '/clientes', badge: 12 },
  { id: 'entregas', label: 'Entregas', icon: 'truck' as const, href: '/entregas' },
];

test('Sidebar: item ativo tem aria-current="page"; os outros não', () => {
  const h = html(<Sidebar items={itens} activeId="clientes" />);
  assert.equal((h.match(/aria-current="page"/g) ?? []).length, 1);
  assert.match(h, /<a[^>]*href="\/clientes"[^>]*aria-current="page"|<a[^>]*aria-current="page"[^>]*href="\/clientes"/);
});

test('Sidebar: título de seção e selo numérico', () => {
  const h = html(<Sidebar items={itens} />);
  assert.match(h, />Operação</);
  assert.match(h, />12</);
});

test('Sidebar: usa LinkComponent quando informado (ex.: next/link)', () => {
  const Meu = ({ href, children, ...r }: { href: string; children?: ReactNode; className?: string }) => (
    <a data-meu="sim" href={href} {...r}>{children}</a>
  );
  assert.match(html(<Sidebar items={itens} LinkComponent={Meu} />), /data-meu="sim"/);
});

test('Sidebar: recolhida esconde os rótulos visíveis mas mantém o nome acessível', () => {
  const h = html(<Sidebar items={itens} collapsed />);
  assert.match(h, /ovo-sidebar--collapsed/);
  assert.match(h, /aria-label="Clientes"/);
});

test('Tabs com href viram navegação com aria-current; sem href viram tablist', () => {
  const links = html(<Tabs items={[{ id: 'a', label: 'Ativas', href: '?s=a', count: 3 }, { id: 'b', label: 'Pausadas', href: '?s=b' }]} activeId="a" />);
  assert.match(links, /<nav/);
  assert.match(links, /aria-current="page"/);
  const abas = html(<Tabs items={[{ id: 'a', label: 'Ativas' }, { id: 'b', label: 'Pausadas' }]} activeId="b" />);
  assert.match(abas, /role="tablist"/);
  assert.match(abas, /role="tab"[^>]*aria-selected="true"[^>]*>Pausadas|aria-selected="true"[^>]*role="tab"/);
});

test('TopBar: título é o h1 da página', () => {
  assert.match(html(<TopBar title="Clientes" subtitle="128 ativos" />), /<h1[^>]*>Clientes<\/h1>/);
});

test('BottomNav: item ativo com aria-current e área de toque', () => {
  const h = html(<BottomNav items={[{ id: 'i', label: 'Início', icon: 'layout-grid', href: '/' }, { id: 'c', label: 'Clientes', icon: 'users', href: '/clientes' }]} activeId="c" />);
  assert.equal((h.match(/aria-current="page"/g) ?? []).length, 1);
  assert.match(h, /<nav[^>]*aria-label="Navegação"/);
});

test('Pagination: sem registros mostra 0–0 de 0 e não inventa páginas', () => {
  const h = html(<Pagination page={1} pageCount={0} total={0} pageSize={10} />);
  assert.match(h, />0–0</);
  assert.match(h, /de <span[^>]*>0</);
  assert.doesNotMatch(h, /ovo-pagination__num/);
});

test('Pagination: uma página só desativa anterior e próxima', () => {
  const h = html(<Pagination page={1} pageCount={1} total={4} pageSize={10} />);
  assert.equal((h.match(/disabled=""/g) ?? []).length, 2);
});

test('Pagination: página acima do total não quebra', () => {
  assert.doesNotMatch(html(<Pagination page={9} pageCount={3} total={25} pageSize={10} />), /NaN|undefined/);
});

test('Pagination: no meio mostra 3 números com a atual marcada; com hrefFor usa links', () => {
  const h = html(<Pagination page={3} pageCount={8} total={80} pageSize={10} hrefFor={(p) => `?p=${p}`} />);
  assert.match(h, /href="\?p=2"/);
  assert.match(h, /href="\?p=4"/);
  assert.equal((h.match(/aria-current="page"/g) ?? []).length, 1);
  assert.match(h, />21–30</);
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `pnpm --filter @ovo/ui test`
Expected: **FAIL** — módulos de `navigation/` inexistentes.

- [ ] **Step 3: Criar `packages/ui/src/navigation/Sidebar.tsx`**

```tsx
import type { ElementType, ReactNode } from 'react';
import { cx } from '../cx';
import { Icon, type IconName } from '../core/Icon';

export type SidebarItem =
  | { id: string; label: string; icon: IconName; href: string; badge?: number | string }
  | { section: string };

export type SidebarProps = {
  items: SidebarItem[];
  activeId?: string;
  collapsed?: boolean;
  brand?: ReactNode;
  footer?: ReactNode;
  /** Padrão 'a'. No Next, passe o Link de next/link. */
  LinkComponent?: ElementType;
  className?: string;
};

export function Sidebar({ items, activeId, collapsed, brand, footer, LinkComponent, className }: SidebarProps) {
  const Link: ElementType = LinkComponent ?? 'a';
  return (
    <nav aria-label="Navegação principal" className={cx('ovo-sidebar', collapsed && 'ovo-sidebar--collapsed', className)}>
      {brand && <div className="ovo-sidebar__brand">{brand}</div>}
      <div className="ovo-sidebar__list ovo-scroll">
        {items.map((item) => {
          if ('section' in item) {
            return (
              <span key={`s-${item.section}`} className="ovo-sidebar__section">
                {collapsed ? '·' : item.section}
              </span>
            );
          }
          const ativo = item.id === activeId;
          return (
            <Link
              key={item.id}
              href={item.href}
              aria-label={item.label}
              aria-current={ativo ? 'page' : undefined}
              className={cx('ovo-sidebar__item', ativo && 'ovo-sidebar__item--active')}
            >
              <Icon name={item.icon} size={19} strokeWidth={ativo ? 2 : 1.75} />
              {!collapsed && <span className="ovo-sidebar__label">{item.label}</span>}
              {!collapsed && item.badge != null && <span className="ovo-sidebar__badge">{item.badge}</span>}
            </Link>
          );
        })}
      </div>
      {footer && <div className="ovo-sidebar__footer">{footer}</div>}
    </nav>
  );
}
```

- [ ] **Step 4: Criar `packages/ui/src/navigation/Tabs.tsx`**

```tsx
import type { ElementType } from 'react';
import { cx } from '../cx';

export type TabItem = { id: string; label: string; count?: number; href?: string };

export type TabsProps = {
  items: TabItem[];
  activeId?: string;
  /** Usado quando os itens não têm href (aba local). */
  onChange?: (id: string) => void;
  variant?: 'underline' | 'pill';
  LinkComponent?: ElementType;
  className?: string;
};

export function Tabs({ items, activeId, onChange, variant = 'underline', LinkComponent, className }: TabsProps) {
  const Link: ElementType = LinkComponent ?? 'a';
  const comLinks = items.some((i) => i.href);
  const classes = cx('ovo-tabs', `ovo-tabs--${variant}`, 'ovo-scroll', className);
  const conteudo = (i: TabItem) => (
    <>
      {i.label}
      {i.count != null && <span className="ovo-tabs__count">{i.count}</span>}
    </>
  );
  if (comLinks) {
    return (
      <nav aria-label="Filtros" className={classes}>
        {items.map((i) => (
          <Link key={i.id} href={i.href ?? '#'} aria-current={i.id === activeId ? 'page' : undefined} className={cx('ovo-tabs__tab', i.id === activeId && 'ovo-tabs__tab--active')}>
            {conteudo(i)}
          </Link>
        ))}
      </nav>
    );
  }
  return (
    <div role="tablist" className={classes}>
      {items.map((i) => (
        <button
          key={i.id}
          type="button"
          role="tab"
          aria-selected={i.id === activeId}
          onClick={onChange ? () => onChange(i.id) : undefined}
          className={cx('ovo-tabs__tab', i.id === activeId && 'ovo-tabs__tab--active')}
        >
          {conteudo(i)}
        </button>
      ))}
    </div>
  );
}
```

- [ ] **Step 5: Criar `packages/ui/src/navigation/TopBar.tsx` e `BottomNav.tsx`**

`TopBar.tsx`:

```tsx
import type { ReactNode } from 'react';
import { cx } from '../cx';

export type TopBarProps = {
  title?: ReactNode;
  subtitle?: ReactNode;
  breadcrumb?: ReactNode;
  search?: ReactNode;
  actions?: ReactNode;
  left?: ReactNode;
  className?: string;
};

export function TopBar({ title, subtitle, breadcrumb, search, actions, left, className }: TopBarProps) {
  return (
    <header className={cx('ovo-topbar', className)}>
      {left}
      <div className="ovo-topbar__titles">
        {breadcrumb && <div className="ovo-topbar__crumb">{breadcrumb}</div>}
        {title && <h1 className="ovo-topbar__title">{title}</h1>}
        {subtitle && <p className="ovo-topbar__sub">{subtitle}</p>}
      </div>
      {search && <div className="ovo-topbar__search">{search}</div>}
      {actions && <div className="ovo-topbar__actions">{actions}</div>}
    </header>
  );
}
```

`BottomNav.tsx`:

```tsx
import type { ElementType } from 'react';
import { cx } from '../cx';
import { Icon, type IconName } from '../core/Icon';

export type BottomNavItem = { id: string; label: string; icon: IconName; href: string; badge?: boolean };

export type BottomNavProps = {
  items: BottomNavItem[];
  activeId?: string;
  LinkComponent?: ElementType;
  className?: string;
};

export function BottomNav({ items, activeId, LinkComponent, className }: BottomNavProps) {
  const Link: ElementType = LinkComponent ?? 'a';
  return (
    <nav aria-label="Navegação" className={cx('ovo-bottomnav', className)}>
      {items.map((item) => {
        const ativo = item.id === activeId;
        return (
          <Link key={item.id} href={item.href} aria-current={ativo ? 'page' : undefined} className={cx('ovo-bottomnav__item', ativo && 'ovo-bottomnav__item--active')}>
            <span className="ovo-bottomnav__icon">
              <Icon name={item.icon} size={21} strokeWidth={ativo ? 2.1 : 1.75} />
              {item.badge && <span className="ovo-bottomnav__dot" aria-hidden="true" />}
            </span>
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
```

- [ ] **Step 6: Criar `packages/ui/src/navigation/Pagination.tsx`**

```tsx
import { cx } from '../cx';
import { IconButton } from '../core/IconButton';

export type PaginationProps = {
  page?: number;
  pageCount?: number;
  total?: number;
  pageSize?: number;
  /** Navegação por link (recomendado em página de servidor). */
  hrefFor?: (pagina: number) => string;
  /** Alternativa para uso em componente de cliente. */
  onChange?: (pagina: number) => void;
  className?: string;
};

export function Pagination({ page = 1, pageCount = 1, total, pageSize = 10, hrefFor, onChange, className }: PaginationProps) {
  const numeros: number[] = [];
  const inicio = Math.max(1, Math.min(page - 1, pageCount - 2));
  for (let n = inicio; n < inicio + 3 && n <= pageCount; n++) numeros.push(n);

  const de = total == null ? 0 : total === 0 ? 0 : Math.min((page - 1) * pageSize + 1, total);
  const ate = total == null ? 0 : Math.min(page * pageSize, total);
  const anteriorOff = page <= 1;
  const proximaOff = page >= pageCount;

  return (
    <div className={cx('ovo-pagination', className)}>
      {total != null && (
        <span className="ovo-pagination__info">
          Mostrando{' '}
          <span className="ovo-num ovo-pagination__strong">
            {de}–{ate}
          </span>{' '}
          de <span className="ovo-num ovo-pagination__strong">{total}</span>
        </span>
      )}
      <div className="ovo-pagination__nav">
        <IconButton
          icon="chevron-left"
          label="Página anterior"
          variant="outline"
          size="sm"
          disabled={anteriorOff}
          href={hrefFor && !anteriorOff ? hrefFor(page - 1) : undefined}
          onClick={onChange && !anteriorOff ? () => onChange(page - 1) : undefined}
        />
        {numeros.map((n) => {
          const atual = n === page;
          const classe = cx('ovo-pagination__num', atual && 'ovo-pagination__num--active');
          return hrefFor ? (
            <a key={n} href={hrefFor(n)} aria-current={atual ? 'page' : undefined} className={classe}>
              {n}
            </a>
          ) : (
            <button key={n} type="button" aria-current={atual ? 'page' : undefined} onClick={onChange ? () => onChange(n) : undefined} className={classe}>
              {n}
            </button>
          );
        })}
        <IconButton
          icon="chevron-right"
          label="Próxima página"
          variant="outline"
          size="sm"
          disabled={proximaOff}
          href={hrefFor && !proximaOff ? hrefFor(page + 1) : undefined}
          onClick={onChange && !proximaOff ? () => onChange(page + 1) : undefined}
        />
      </div>
    </div>
  );
}
```

- [ ] **Step 7: Exportar no `index.ts`**

Append:

```ts
export { Sidebar } from './navigation/Sidebar';
export type { SidebarItem, SidebarProps } from './navigation/Sidebar';
export { Tabs } from './navigation/Tabs';
export type { TabItem, TabsProps } from './navigation/Tabs';
export { TopBar } from './navigation/TopBar';
export type { TopBarProps } from './navigation/TopBar';
export { BottomNav } from './navigation/BottomNav';
export type { BottomNavItem, BottomNavProps } from './navigation/BottomNav';
export { Pagination } from './navigation/Pagination';
export type { PaginationProps } from './navigation/Pagination';
```

- [ ] **Step 8: Acrescentar o CSS ao `components.css`**

Append:

```css
/* ── Sidebar ───────────────────────────────────────────────────────── */
.ovo-sidebar {
  width: var(--sidebar-width); flex: none; min-height: 0; display: flex; flex-direction: column; gap: var(--space-6);
  padding: var(--space-6) var(--space-5); background: var(--surface-inverse); color: var(--text-on-inverse);
  transition: width var(--dur-normal) var(--ease-standard);
}
.ovo-sidebar--collapsed { width: var(--sidebar-width-collapsed); }
.ovo-sidebar__brand { display: flex; align-items: center; min-height: 32px; }
.ovo-sidebar--collapsed .ovo-sidebar__brand { justify-content: center; }
.ovo-sidebar__list { display: flex; flex-direction: column; gap: 2px; flex: 1; min-height: 0; overflow-y: auto; }
.ovo-sidebar__section {
  font: var(--type-overline); letter-spacing: var(--ls-caps); text-transform: uppercase;
  color: var(--text-on-inverse-muted); padding: 14px 10px 6px;
}
.ovo-sidebar--collapsed .ovo-sidebar__section { padding: 14px 0 6px; text-align: center; }
.ovo-sidebar__item {
  display: flex; align-items: center; gap: 10px; min-height: 40px; padding: 0 10px; text-decoration: none;
  border-radius: var(--radius-control); color: var(--text-on-inverse);
  font: var(--fw-medium) var(--fs-sm) / 1.2 var(--font-sans); transition: var(--transition-control);
}
.ovo-sidebar--collapsed .ovo-sidebar__item { justify-content: center; padding: 0; }
.ovo-sidebar__item:hover { background: var(--surface-inverse-hover); }
.ovo-sidebar__item--active, .ovo-sidebar__item--active:hover { background: var(--gold-400); color: var(--text-on-accent); }
.ovo-sidebar__label { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.ovo-sidebar__badge {
  font: var(--fw-semibold) var(--fs-2xs) / 1 var(--font-mono); padding: 3px 6px; border-radius: var(--radius-pill);
  background: var(--surface-inverse-soft); color: var(--text-on-inverse);
}
.ovo-sidebar__item--active .ovo-sidebar__badge { background: var(--surface-on-accent-chip); color: var(--text-on-accent); }
.ovo-sidebar__footer { border-top: 1px solid var(--border-inverse); padding-top: var(--space-5); }

/* ── Tabs ──────────────────────────────────────────────────────────── */
.ovo-tabs { display: flex; overflow-x: auto; }
.ovo-tabs--underline { gap: var(--space-7); border-bottom: 1px solid var(--border-subtle); }
.ovo-tabs--pill { gap: 4px; padding: 4px; background: var(--surface-sunken); border-radius: var(--radius-pill); }
.ovo-tabs__tab {
  display: inline-flex; align-items: center; gap: 6px; min-height: 34px; white-space: nowrap; cursor: pointer;
  border: 0; background: transparent; text-decoration: none; color: var(--text-muted);
  font: var(--fw-medium) var(--fs-sm) / 1.2 var(--font-sans); transition: var(--transition-control);
}
.ovo-tabs__tab:hover { color: var(--text-body); }
.ovo-tabs--underline .ovo-tabs__tab { padding: 0 0 10px; margin-bottom: -1px; border-bottom: 2px solid transparent; }
.ovo-tabs--underline .ovo-tabs__tab--active { color: var(--text-strong); font-weight: var(--fw-semibold); border-bottom-color: var(--gold-600); }
.ovo-tabs--pill .ovo-tabs__tab { padding: 7px 14px; border-radius: var(--radius-pill); }
.ovo-tabs--pill .ovo-tabs__tab--active { background: var(--surface-raised); color: var(--text-strong); font-weight: var(--fw-semibold); box-shadow: var(--shadow-xs); }
.ovo-tabs__count { font: var(--fw-medium) var(--fs-2xs) / 1 var(--font-mono); color: var(--text-muted); }
.ovo-tabs__tab--active .ovo-tabs__count { color: var(--text-accent); }

/* ── TopBar ────────────────────────────────────────────────────────── */
.ovo-topbar {
  display: flex; align-items: center; flex-wrap: wrap; gap: var(--space-6); min-height: var(--topbar-height);
  padding: 12px var(--gutter-page); background: var(--surface-page); border-bottom: 1px solid var(--border-subtle);
}
.ovo-topbar__titles { min-width: 0; flex: 1 1 220px; }
.ovo-topbar__crumb { margin-bottom: 2px; }
.ovo-topbar__title {
  font: var(--fw-semibold) var(--fs-2xl) / 1.15 var(--font-display); letter-spacing: var(--ls-tight);
  color: var(--text-strong); overflow: hidden; text-overflow: ellipsis;
}
.ovo-topbar__sub { font: var(--type-body-sm); color: var(--text-muted); margin-top: 3px; }
.ovo-topbar__search { flex: 0 1 320px; min-width: 160px; }
.ovo-topbar__actions { display: flex; align-items: center; gap: var(--space-4); }

/* ── BottomNav ─────────────────────────────────────────────────────── */
.ovo-bottomnav {
  display: flex; align-items: stretch; gap: 2px; height: var(--bottomnav-height); padding: 6px 8px;
  padding-bottom: max(6px, env(safe-area-inset-bottom));
  background: var(--surface-raised); border-top: 1px solid var(--border-subtle);
}
.ovo-bottomnav__item {
  flex: 1; min-width: var(--tap-target-min); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px;
  border-radius: var(--radius-control); text-decoration: none; color: var(--text-muted);
  font: var(--fw-medium) var(--fs-2xs) / 1 var(--font-sans); transition: var(--transition-control);
}
.ovo-bottomnav__item--active { color: var(--text-accent); }
.ovo-bottomnav__icon { position: relative; display: grid; place-items: center; }
.ovo-bottomnav__dot { position: absolute; top: -2px; right: -6px; width: 8px; height: 8px; border-radius: var(--radius-pill); background: var(--clay-500); }

/* ── Pagination ────────────────────────────────────────────────────── */
.ovo-pagination { display: flex; align-items: center; justify-content: space-between; gap: var(--space-5); flex-wrap: wrap; }
.ovo-pagination__info { font: var(--type-caption); color: var(--text-muted); }
.ovo-pagination__strong { color: var(--text-body); }
.ovo-pagination__nav { display: flex; align-items: center; gap: 4px; }
.ovo-pagination__num {
  min-width: 32px; height: 32px; display: inline-flex; align-items: center; justify-content: center; cursor: pointer;
  border: 1px solid transparent; border-radius: var(--radius-control); background: transparent; color: var(--text-body);
  text-decoration: none; font: var(--fw-medium) var(--fs-sm) / 1 var(--font-mono); transition: var(--transition-control);
}
.ovo-pagination__num:hover { background: var(--action-ghost-hover); }
.ovo-pagination__num--active, .ovo-pagination__num--active:hover { background: var(--surface-inverse); border-color: var(--surface-inverse); color: var(--text-on-inverse); }
```

- [ ] **Step 9: Rodar testes e tipos**

Run:
```bash
pnpm --filter @ovo/ui test
pnpm --filter @ovo/ui typecheck
```
Expected: **PASS**, typecheck limpo.

- [ ] **Step 10: Commit**

```bash
git add packages/ui
git commit -m "feat(ui): componentes de navegação (Sidebar, Tabs, TopBar, BottomNav, Pagination)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Componentes de feedback

**Files:**
- Create: `packages/ui/src/feedback/{Banner,Dialog,EmptyState,Toast}.tsx`
- Create: `packages/ui/tests/feedback.test.tsx`
- Modify: `packages/ui/src/index.ts`, `packages/ui/src/components.css` (append)

**Interfaces:**
- Consumes: `cx`, `Icon`, `IconName`, `IconButton`.
- Produces: `Banner({ tone?: 'warning'|'success'|'danger'|'accent', title?, children?, action?, onDismiss? })` (`role="alert"` para `danger`, `role="status"` nos demais); `Dialog({ open, title?, description?, children?, footer?, onClose?, width?, sheetOnMobile? })` (`'use client'`; Esc fecha, foco entra no painel e volta ao fechar); `EmptyState({ icon?, title?, description?, action?, compact? })`; `Toast({ tone?: 'success'|'danger'|'info', title?, description?, action?, onClose? })`.

- [ ] **Step 1: Escrever `packages/ui/tests/feedback.test.tsx`**

```tsx
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { renderToStaticMarkup as html } from 'react-dom/server';
import { Banner } from '../src/feedback/Banner';
import { Dialog } from '../src/feedback/Dialog';
import { EmptyState } from '../src/feedback/EmptyState';
import { Toast } from '../src/feedback/Toast';

test('Banner: erro é anunciado com role="alert"; os demais com role="status"', () => {
  assert.match(html(<Banner tone="danger" title="Falha ao salvar" />), /role="alert"/);
  assert.match(html(<Banner tone="success" title="Salvo" />), /role="status"/);
  assert.match(html(<Banner title="Atenção" />), /role="status"/);
});

test('Banner: título, corpo e botão de dispensar com rótulo', () => {
  const h = html(<Banner title="Fatura vencida" onDismiss={() => {}}>Pague até sexta.</Banner>);
  assert.match(h, /Fatura vencida/);
  assert.match(h, /Pague até sexta\./);
  assert.match(h, /aria-label="Dispensar"/);
});

test('Dialog: fechado não renderiza nada', () => {
  assert.equal(html(<Dialog open={false} title="Pausar" />), '');
});

test('Dialog: aberto tem role="dialog", aria-modal e título ligado por aria-labelledby', () => {
  const h = html(<Dialog open title="Pausar assinatura" description="Retorno previsto em 15 dias" onClose={() => {}} footer={<button type="button">Ok</button>}>corpo</Dialog>);
  assert.match(h, /role="dialog"/);
  assert.match(h, /aria-modal="true"/);
  const alvo = h.match(/aria-labelledby="([^"]+)"/)?.[1];
  assert.ok(alvo);
  assert.match(h, new RegExp(`<h2[^>]*id="${alvo}"[^>]*>Pausar assinatura<`));
  assert.match(h, /Retorno previsto em 15 dias/);
  assert.match(h, /aria-label="Fechar"/);
});

test('Dialog: sem onClose não mostra o botão de fechar', () => {
  assert.doesNotMatch(html(<Dialog open title="Aviso" />), /aria-label="Fechar"/);
});

test('Dialog: sheetOnMobile vira classe', () => {
  assert.match(html(<Dialog open title="x" sheetOnMobile />), /ovo-dialog--sheet/);
});

test('EmptyState: título e descrição dizem o que houve; ação opcional', () => {
  const h = html(<EmptyState title="Nenhum pedido neste filtro" description="Ajuste o período ou limpe a busca." action={<a href="?">Limpar filtros</a>} />);
  assert.match(h, /Nenhum pedido neste filtro/);
  assert.match(h, /Ajuste o período/);
  assert.match(h, /Limpar filtros/);
});

test('EmptyState: sem props ainda renderiza o ícone padrão', () => {
  assert.match(html(<EmptyState />), /<svg/);
});

test('Toast: role="status", título e descrição', () => {
  const h = html(<Toast tone="info" title="Coleta registrada" description="Lote 2411" />);
  assert.match(h, /role="status"/);
  assert.match(h, /Coleta registrada/);
  assert.match(h, /Lote 2411/);
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `pnpm --filter @ovo/ui test`
Expected: **FAIL** — módulos de `feedback/` inexistentes.

- [ ] **Step 3: Criar `packages/ui/src/feedback/Banner.tsx`**

```tsx
import type { ReactNode } from 'react';
import { cx } from '../cx';
import { Icon, type IconName } from '../core/Icon';
import { IconButton } from '../core/IconButton';

export type BannerTone = 'warning' | 'success' | 'danger' | 'accent';

const ICONE: Record<BannerTone, IconName> = { warning: 'alert', success: 'check-circle', danger: 'alert', accent: 'bell' };

export type BannerProps = {
  tone?: BannerTone;
  title?: ReactNode;
  children?: ReactNode;
  action?: ReactNode;
  onDismiss?: () => void;
  className?: string;
};

export function Banner({ tone = 'warning', title, children, action, onDismiss, className }: BannerProps) {
  return (
    <div role={tone === 'danger' ? 'alert' : 'status'} className={cx('ovo-banner', `ovo-banner--${tone}`, className)}>
      <Icon name={ICONE[tone]} size={18} className="ovo-banner__icon" />
      <div className="ovo-banner__body">
        {title && <p className="ovo-banner__title">{title}</p>}
        {children && <div className={cx('ovo-banner__text', Boolean(title) && 'ovo-banner__text--after')}>{children}</div>}
      </div>
      {action}
      {onDismiss && <IconButton icon="x" label="Dispensar" size="sm" onClick={onDismiss} />}
    </div>
  );
}
```

- [ ] **Step 4: Criar `packages/ui/src/feedback/Dialog.tsx`**

```tsx
'use client';

import { useEffect, useId, useRef, type ReactNode } from 'react';
import { cx } from '../cx';
import { IconButton } from '../core/IconButton';

export type DialogProps = {
  open: boolean;
  title?: ReactNode;
  description?: ReactNode;
  children?: ReactNode;
  footer?: ReactNode;
  onClose?: () => void;
  width?: number;
  /** No celular, abre como folha colada embaixo. */
  sheetOnMobile?: boolean;
  className?: string;
};

export function Dialog({ open, title, description, children, footer, onClose, width = 520, sheetOnMobile, className }: DialogProps) {
  const tituloId = useId();
  const painel = useRef<HTMLDivElement>(null);
  const fechar = useRef(onClose);

  useEffect(() => {
    fechar.current = onClose;
  });

  useEffect(() => {
    if (!open) return;
    const anterior = document.activeElement as HTMLElement | null;
    painel.current?.focus();
    const aoTeclar = (e: KeyboardEvent) => {
      if (e.key === 'Escape') fechar.current?.();
    };
    document.addEventListener('keydown', aoTeclar);
    return () => {
      document.removeEventListener('keydown', aoTeclar);
      anterior?.focus();
    };
  }, [open]);

  if (!open) return null;

  return (
    <div className={cx('ovo-dialog__scrim', sheetOnMobile && 'ovo-dialog--sheet')} onClick={onClose}>
      <div
        ref={painel}
        role="dialog"
        aria-modal="true"
        aria-labelledby={title ? tituloId : undefined}
        tabIndex={-1}
        className={cx('ovo-dialog', 'ovo-scroll', className)}
        style={{ maxWidth: width }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="ovo-dialog__head">
          <div className="ovo-dialog__titles">
            {title && (
              <h2 id={tituloId} className="ovo-dialog__title">
                {title}
              </h2>
            )}
            {description && <p className="ovo-dialog__desc">{description}</p>}
          </div>
          {onClose && <IconButton icon="x" label="Fechar" size="sm" onClick={onClose} />}
        </div>
        {children && <div className="ovo-dialog__body">{children}</div>}
        {footer && <div className="ovo-dialog__footer">{footer}</div>}
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Criar `packages/ui/src/feedback/EmptyState.tsx` e `Toast.tsx`**

`EmptyState.tsx`:

```tsx
import type { ReactNode } from 'react';
import { cx } from '../cx';
import { Icon, type IconName } from '../core/Icon';

export type EmptyStateProps = {
  icon?: IconName;
  title?: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
  compact?: boolean;
  className?: string;
};

export function EmptyState({ icon = 'egg', title, description, action, compact, className }: EmptyStateProps) {
  return (
    <div className={cx('ovo-empty', compact && 'ovo-empty--compact', className)}>
      <span className="ovo-empty__icon">
        <Icon name={icon} size={22} />
      </span>
      <div className="ovo-empty__text">
        {title && <p className="ovo-empty__title">{title}</p>}
        {description && <p className="ovo-empty__desc">{description}</p>}
      </div>
      {action}
    </div>
  );
}
```

`Toast.tsx`:

```tsx
import type { ReactNode } from 'react';
import { cx } from '../cx';
import { Icon, type IconName } from '../core/Icon';
import { IconButton } from '../core/IconButton';

export type ToastTone = 'success' | 'danger' | 'info';

const ICONE: Record<ToastTone, IconName> = { success: 'check-circle', danger: 'alert', info: 'bell' };

export type ToastProps = {
  tone?: ToastTone;
  title?: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
  onClose?: () => void;
  className?: string;
};

export function Toast({ tone = 'success', title, description, action, onClose, className }: ToastProps) {
  return (
    <div role="status" className={cx('ovo-toast', `ovo-toast--${tone}`, className)}>
      <Icon name={ICONE[tone]} size={18} className="ovo-toast__icon" />
      <div className="ovo-toast__body">
        {title && <p className="ovo-toast__title">{title}</p>}
        {description && <p className="ovo-toast__desc">{description}</p>}
        {action && <div className="ovo-toast__action">{action}</div>}
      </div>
      {onClose && <IconButton icon="x" label="Fechar" size="sm" variant="inverse" onClick={onClose} />}
    </div>
  );
}
```

- [ ] **Step 6: Exportar no `index.ts`**

Append:

```ts
export { Banner } from './feedback/Banner';
export type { BannerProps, BannerTone } from './feedback/Banner';
export { Dialog } from './feedback/Dialog';
export type { DialogProps } from './feedback/Dialog';
export { EmptyState } from './feedback/EmptyState';
export type { EmptyStateProps } from './feedback/EmptyState';
export { Toast } from './feedback/Toast';
export type { ToastProps, ToastTone } from './feedback/Toast';
```

- [ ] **Step 7: Acrescentar o CSS ao `components.css`**

Append:

```css
/* ── Banner ────────────────────────────────────────────────────────── */
.ovo-banner {
  display: flex; align-items: flex-start; gap: var(--space-5); padding: 14px 16px;
  background: var(--banner-fundo); border: 1px solid var(--banner-borda); border-radius: var(--radius-md);
}
.ovo-banner--warning { --banner-fundo: var(--surface-highlight); --banner-borda: var(--cream-500); --banner-cor: var(--brown-700); }
.ovo-banner--success { --banner-fundo: var(--surface-success-soft); --banner-borda: var(--green-300); --banner-cor: var(--green-700); }
.ovo-banner--danger { --banner-fundo: var(--surface-danger-soft); --banner-borda: var(--red-300); --banner-cor: var(--red-700); }
.ovo-banner--accent { --banner-fundo: var(--surface-accent-soft); --banner-borda: var(--gold-300); --banner-cor: var(--gold-700); }
.ovo-banner__icon { color: var(--banner-cor); margin-top: 1px; }
.ovo-banner__body { flex: 1; min-width: 0; }
.ovo-banner__title { font: var(--fw-semibold) var(--fs-sm) / 1.3 var(--font-sans); color: var(--banner-cor); }
.ovo-banner__text { font: var(--type-body-sm); color: var(--text-body); }
.ovo-banner__text--after { margin-top: 3px; }

/* ── Dialog ────────────────────────────────────────────────────────── */
.ovo-dialog__scrim {
  position: fixed; inset: 0; z-index: 100; display: flex; align-items: center; justify-content: center;
  padding: var(--space-8); background: var(--overlay-scrim); backdrop-filter: var(--blur-sheet);
}
.ovo-dialog {
  width: 100%; max-height: 88vh; overflow-y: auto; display: flex; flex-direction: column; gap: var(--space-6);
  padding: var(--space-8); background: var(--surface-raised); border: 1px solid var(--border-subtle);
  border-radius: var(--radius-lg); box-shadow: var(--shadow-lg);
}
.ovo-dialog:focus { outline: 0; }
.ovo-dialog__head { display: flex; align-items: flex-start; gap: var(--space-5); }
.ovo-dialog__titles { flex: 1; min-width: 0; }
.ovo-dialog__title { font: var(--fw-semibold) var(--fs-xl) / 1.25 var(--font-display); color: var(--text-strong); }
.ovo-dialog__desc { font: var(--type-body-sm); color: var(--text-muted); margin-top: 6px; }
.ovo-dialog__body { min-width: 0; }
.ovo-dialog__footer { display: flex; justify-content: flex-end; flex-wrap: wrap; gap: var(--space-4); }
@media (max-width: 640px) {
  .ovo-dialog--sheet.ovo-dialog__scrim { align-items: flex-end; padding: 0; }
  .ovo-dialog--sheet .ovo-dialog { border-radius: var(--radius-sheet) var(--radius-sheet) 0 0; }
}

/* ── EmptyState ────────────────────────────────────────────────────── */
.ovo-empty {
  display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center;
  gap: var(--space-5); padding: var(--space-12) var(--space-8);
  background: var(--surface-card); border: 1px dashed var(--border-strong); border-radius: var(--radius-card);
}
.ovo-empty--compact { padding: var(--space-9) var(--space-6); }
.ovo-empty__icon {
  width: 48px; height: 48px; border-radius: 50%; display: grid; place-items: center;
  background: var(--surface-accent-soft); color: var(--gold-700);
}
.ovo-empty__text { max-width: 380px; }
.ovo-empty__title { font: var(--fw-semibold) var(--fs-lg) / 1.3 var(--font-display); color: var(--text-strong); }
.ovo-empty__desc { font: var(--type-body-sm); color: var(--text-muted); margin-top: 6px; }

/* ── Toast ─────────────────────────────────────────────────────────── */
.ovo-toast {
  display: flex; align-items: flex-start; gap: var(--space-5); min-width: 280px; max-width: 420px;
  padding: 14px 14px 14px 16px; background: var(--surface-inverse); color: var(--text-on-inverse);
  border-left: 3px solid var(--toast-cor); border-radius: var(--radius-md); box-shadow: var(--shadow-lg);
}
.ovo-toast--success { --toast-cor: var(--green-500); }
.ovo-toast--danger { --toast-cor: var(--red-500); }
.ovo-toast--info { --toast-cor: var(--gold-400); }
.ovo-toast__icon { color: var(--toast-cor); margin-top: 1px; }
.ovo-toast__body { flex: 1; min-width: 0; }
.ovo-toast__title { font: var(--fw-semibold) var(--fs-sm) / 1.3 var(--font-sans); }
.ovo-toast__desc { font: var(--type-caption); color: var(--text-on-inverse-muted); margin-top: 3px; }
.ovo-toast__action { margin-top: 10px; }
```

- [ ] **Step 8: Rodar testes e tipos**

Run:
```bash
pnpm --filter @ovo/ui test
pnpm --filter @ovo/ui typecheck
```
Expected: **PASS**, typecheck limpo. O teste de guardas confirma que o `index.ts` exporta os 4 componentes novos e que toda classe `.ovo-*` usada existe no CSS.

- [ ] **Step 9: Commit**

```bash
git add packages/ui
git commit -m "feat(ui): componentes de feedback (Banner, Dialog, EmptyState, Toast)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Página `/ui-kit` (só no site, só em desenvolvimento)

**Files:**
- Create: `packages/ui/src/kit/UiKit.tsx`, `packages/ui/src/kit/DialogDemo.tsx`
- Create: `apps/site/src/app/ui-kit/page.tsx`
- Create: `.claude/launch.json`

**Interfaces:**
- Consumes: todos os componentes via `../index`.
- Produces: `UiKit({ cliente?: boolean })` — página de conferência com todos os componentes; rota `http://localhost:3002/ui-kit` (em produção responde 404).

- [ ] **Step 1: Criar `packages/ui/src/kit/DialogDemo.tsx`**

```tsx
'use client';

import { useState } from 'react';
import { Button } from '../core/Button';
import { Dialog } from '../feedback/Dialog';

export function DialogDemo() {
  const [aberto, setAberto] = useState(false);
  return (
    <>
      <Button variant="secondary" onClick={() => setAberto(true)}>
        Abrir diálogo
      </Button>
      <Dialog
        open={aberto}
        title="Pausar assinatura"
        description="A próxima entrega fica para depois do retorno."
        onClose={() => setAberto(false)}
        sheetOnMobile
        footer={
          <>
            <Button variant="secondary" onClick={() => setAberto(false)}>
              Cancelar
            </Button>
            <Button onClick={() => setAberto(false)}>Confirmar pausa</Button>
          </>
        }
      >
        <p>Você volta a receber ovos quando a pausa terminar. Sem multa e sem nova cobrança.</p>
      </Dialog>
    </>
  );
}
```

- [ ] **Step 2: Criar `packages/ui/src/kit/UiKit.tsx`**

```tsx
import type { ReactNode } from 'react';
import { cx } from '../cx';
import { Avatar } from '../core/Avatar';
import { Badge } from '../core/Badge';
import { Button } from '../core/Button';
import { Card } from '../core/Card';
import { IconButton } from '../core/IconButton';
import { Tag } from '../core/Tag';
import { Tooltip } from '../core/Tooltip';
import { Checkbox } from '../forms/Checkbox';
import { Input } from '../forms/Input';
import { Radio } from '../forms/Radio';
import { SearchField } from '../forms/SearchField';
import { Select } from '../forms/Select';
import { Switch } from '../forms/Switch';
import { Textarea } from '../forms/Textarea';
import { BarChart } from '../data/BarChart';
import { DataTable } from '../data/DataTable';
import { ProgressBar } from '../data/ProgressBar';
import { StatCard } from '../data/StatCard';
import { Trend } from '../data/Trend';
import { BottomNav } from '../navigation/BottomNav';
import { Pagination } from '../navigation/Pagination';
import { Sidebar } from '../navigation/Sidebar';
import { Tabs } from '../navigation/Tabs';
import { TopBar } from '../navigation/TopBar';
import { Banner } from '../feedback/Banner';
import { EmptyState } from '../feedback/EmptyState';
import { Toast } from '../feedback/Toast';
import { DialogDemo } from './DialogDemo';

function Secao({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <section className="ovo-kit__secao">
      <h2 className="ovo-kit__titulo">{titulo}</h2>
      <div className="ovo-kit__grade">{children}</div>
    </section>
  );
}

type Pedido = { id: number; cliente: string; plano: string; total: string; status: string };
const PEDIDOS: Pedido[] = [
  { id: 9402, cliente: 'Beatriz Mendes', plano: 'Semanal', total: 'R$ 164,00', status: 'Entregue' },
  { id: 9403, cliente: 'Cláudio Pinto', plano: 'Quinzenal', total: 'R$ 82,00', status: 'Aguardando' },
];

const MENU = [
  { section: 'Operação' },
  { id: 'inicio', label: 'Início', icon: 'layout-grid' as const, href: '#' },
  { id: 'clientes', label: 'Clientes', icon: 'users' as const, href: '#', badge: 12 },
  { id: 'entregas', label: 'Entregas', icon: 'truck' as const, href: '#' },
];

/** Página de conferência visual. Só dados fictícios; só para desenvolvimento. */
export function UiKit({ cliente = false }: { cliente?: boolean }) {
  return (
    <main className={cx('ovo-root', cliente && 'ovo-root--cliente', 'ovo-kit')}>
      <header className="ovo-kit__cabecalho">
        <p className="ovo-overline">Design System · conferência</p>
        <h1>Componentes do Ovo di Onça</h1>
        <p>Tudo que o site, o portal do assinante e a gestão vão usar. Dados fictícios.</p>
      </header>

      <Secao titulo="Botões">
        <Button>Assinar</Button>
        <Button variant="secondary">Ver planos</Button>
        <Button variant="ghost">Cancelar</Button>
        <Button variant="inverse">Painel</Button>
        <Button variant="danger">Cancelar assinatura</Button>
        <Button icon="plus" size="sm">Novo cliente</Button>
        <Button iconAfter="arrow-right" size="lg">Continuar</Button>
        <Button loading>Salvando</Button>
        <Button disabled>Indisponível</Button>
        <Button href="#">Link como botão</Button>
        <IconButton icon="bell" label="Notificações" variant="outline" />
        <IconButton icon="edit" label="Editar" />
      </Secao>

      <Secao titulo="Selos, tags, avatares e dicas">
        <Badge>Rascunho</Badge>
        <Badge tone="success" dot>Entregue</Badge>
        <Badge tone="warning">Em separação</Badge>
        <Badge tone="danger">Atrasada</Badge>
        <Badge tone="accent">Mais escolhido</Badge>
        <Badge tone="olive">Caipira</Badge>
        <Tag>Quinzenal</Tag>
        <Tag selected>Selecionada</Tag>
        <Avatar name="Maria da Silva" />
        <Avatar name="Cláudio Pinto" tone="gold" size="lg" />
        <Tooltip label="Copiar chave Pix"><IconButton icon="share" label="Copiar" variant="outline" /></Tooltip>
      </Secao>

      <Secao titulo="Cartões">
        <Card title="Próxima entrega" subtitle="Quarta, 14/10 · 30 ovos">Rota Centro-Sul</Card>
        <Card surface="raised" title="Plano quinzenal">R$ 82,00 por mês</Card>
        <Card surface="olive" title="Sem pressa" subtitle="Pause quando quiser">Volte quando estiver pronto.</Card>
        <Card surface="inverse" title="Painel do dono">Visão geral</Card>
        <Card surface="accent" title="Mais escolhido">Plano semanal</Card>
      </Secao>

      <Secao titulo="Formulários">
        <Input label="E-mail" name="email" type="email" placeholder="voce@exemplo.com" hint="Usamos só para avisar das entregas." />
        <Input label="CEP" name="cep" defaultValue="30000" error="Informe um CEP com 8 dígitos" />
        <Input label="Telefone" icon="user" suffix="WhatsApp" />
        <Select label="Frequência" options={['Semanal', 'Quinzenal', 'Mensal']} />
        <Textarea label="Observação para a entrega" rows={3} />
        <SearchField placeholder="Buscar assinante" shortcut="/" />
        <Checkbox label="Receber aviso por WhatsApp" description="Um dia antes de cada entrega" defaultChecked />
        <Checkbox label="Selecionar todos" indeterminate />
        <Radio label="Pix" name="forma" defaultChecked />
        <Radio label="Cartão" name="forma" />
        <Switch label="Entrega na portaria" defaultChecked />
      </Secao>

      <Secao titulo="Dados">
        <StatCard label="Assinaturas ativas" value="842" unit="clientes" trend={12} caption="vs. semana anterior" icon="users" />
        <StatCard surface="olive" label="Entregas do dia" value="128" unit="cestas" trend={-3} caption="vs. ontem" icon="truck" />
        <StatCard surface="inverse" label="Receita do mês" value="R$ 41.200" trend={6.2} />
        <Card title="Ocupação"><ProgressBar value={34} max={35} label="Rota 1" valueLabel="34 / 35" /><ProgressBar value={28} max={45} tone="olive" label="Rota 2" valueLabel="28 / 45" /></Card>
        <Card title="Coleta por hora"><BarChart data={[{ label: '06h', value: 12, muted: true }, { label: '07h', value: 40 }, { label: '08h', value: 82, highlight: true }, { label: '09h', value: 76 }]} height={140} /></Card>
        <Trend value={4.5} /><Trend value={-2} /><Trend value={0} />
        <div className="ovo-kit__larga">
          <DataTable<Pedido>
            caption="Pedidos de hoje"
            columns={[
              { key: 'id', label: 'Pedido', numeric: true, render: (p) => `#OD-${p.id}` },
              { key: 'cliente', label: 'Cliente' },
              { key: 'plano', label: 'Plano' },
              { key: 'total', label: 'Total', numeric: true, align: 'right' },
              { key: 'status', label: 'Status', render: (p) => <Badge tone={p.status === 'Entregue' ? 'success' : 'warning'} size="sm">{p.status}</Badge> },
            ]}
            rows={PEDIDOS}
          />
        </div>
        <div className="ovo-kit__larga"><DataTable columns={[{ key: 'nome', label: 'Nome' }]} rows={[]} emptyLabel="Nenhum cliente neste filtro" /></div>
      </Secao>

      <Secao titulo="Navegação">
        <div className="ovo-kit__sidebar"><Sidebar items={MENU} activeId="clientes" brand={<strong>Ovo di Onça</strong>} /></div>
        <Tabs items={[{ id: 'todas', label: 'Todas', count: 128, href: '#' }, { id: 'ativas', label: 'Ativas', count: 112, href: '#' }, { id: 'pausadas', label: 'Pausadas', count: 14, href: '#' }]} activeId="ativas" />
        <Tabs variant="pill" items={[{ id: 'a', label: 'Semanal' }, { id: 'b', label: 'Quinzenal' }, { id: 'c', label: 'Mensal' }]} activeId="b" />
        <div className="ovo-kit__larga"><TopBar title="Clientes" subtitle="128 ativos" search={<SearchField placeholder="Buscar cliente" />} actions={<Button size="sm" icon="plus">Novo</Button>} /></div>
        <div className="ovo-kit__larga"><Pagination page={2} pageCount={8} total={80} pageSize={10} hrefFor={(p) => `#p${p}`} /></div>
        <div className="ovo-kit__larga"><BottomNav items={[{ id: 'i', label: 'Início', icon: 'layout-grid', href: '#' }, { id: 'e', label: 'Entregas', icon: 'truck', href: '#', badge: true }, { id: 'p', label: 'Perfil', icon: 'user', href: '#' }]} activeId="e" /></div>
      </Secao>

      <Secao titulo="Avisos">
        <Banner tone="warning" title="Fatura vence amanhã">Pague pelo Pix para manter as entregas.</Banner>
        <Banner tone="success" title="Pagamento confirmado" />
        <Banner tone="danger" title="Não foi possível salvar">Confira o CEP e tente de novo.</Banner>
        <Banner tone="accent" title="Novidade">Agora você pode pausar pelo celular.</Banner>
        <Toast tone="success" title="Coleta registrada" description="Lote 2411 · 1.120 ovos" />
        <Toast tone="danger" title="Falha na rotina diária" />
        <EmptyState title="Nenhum pedido neste filtro" description="Ajuste o período ou limpe a busca." action={<Button variant="secondary" size="sm">Limpar filtros</Button>} />
        <DialogDemo />
      </Secao>
    </main>
  );
}
```

- [ ] **Step 3: Acrescentar o CSS da página de conferência ao `components.css`**

Append:

```css
/* ── Página de conferência (/ui-kit) ───────────────────────────────── */
.ovo-kit { max-width: var(--content-max); margin: 0 auto; padding: var(--space-9) var(--gutter-page); display: flex; flex-direction: column; gap: var(--space-11); }
.ovo-kit__cabecalho { display: flex; flex-direction: column; gap: var(--space-4); }
.ovo-kit__secao { display: flex; flex-direction: column; gap: var(--space-6); }
.ovo-kit__titulo { font: var(--fw-semibold) var(--fs-xl) / 1.25 var(--font-display); padding-bottom: var(--space-4); border-bottom: 1px solid var(--border-subtle); }
.ovo-kit__grade { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: var(--space-6); align-items: start; }
.ovo-kit__larga { grid-column: 1 / -1; min-width: 0; }
.ovo-kit__sidebar { display: flex; height: 360px; }
```

- [ ] **Step 4: Criar `apps/site/src/app/ui-kit/page.tsx`**

```tsx
import { notFound } from 'next/navigation';
import { UiKit } from '@ovo/ui/kit';

export const metadata = { title: 'Conferência de componentes', robots: { index: false, follow: false } };

// Só em desenvolvimento. Em produção a rota não existe.
export default function PaginaUiKit() {
  if (process.env.NODE_ENV === 'production') notFound();
  return <UiKit cliente />;
}
```

- [ ] **Step 5: Criar `.claude/launch.json`**

```json
{
  "version": "0.0.1",
  "configurations": [
    { "name": "site", "runtimeExecutable": "pnpm", "runtimeArgs": ["--filter", "@ovo/site", "dev"], "port": 3002 },
    { "name": "assinante", "runtimeExecutable": "pnpm", "runtimeArgs": ["--filter", "@ovo/assinante", "dev"], "port": 3001 },
    { "name": "gestao", "runtimeExecutable": "pnpm", "runtimeArgs": ["--filter", "@ovo/gestao", "dev"], "port": 3000 }
  ]
}
```

- [ ] **Step 6: Testes, tipos e lint**

Run:
```bash
pnpm --filter @ovo/ui test
pnpm --filter @ovo/ui typecheck
pnpm typecheck
pnpm lint
```
Expected: tudo passa. (O teste de guardas confirma que as classes `ovo-kit*` usadas existem no CSS.)

- [ ] **Step 7: Conferir no navegador (desktop e celular)**

Iniciar o servidor `site` (preview_start, nome `site`) e abrir `http://localhost:3002/ui-kit`.
- Desktop (1280 de largura): rolar a página inteira e tirar screenshots por seção (botões, selos, cartões, formulários, dados, navegação, avisos).
- Celular (preset mobile, 375 de largura): repetir; confirmar que a tabela vira cartões e que não há rolagem horizontal da página.
- Teclado: usar Tab pela página e confirmar anel de foco dourado-escuro visível em botões, campos, caixas e itens do menu.
- Abrir o diálogo, apertar Esc (fecha) e conferir que o foco volta ao botão "Abrir diálogo".
- Console do navegador: nenhuma mensagem de erro (principalmente hidratação e `key`).
- Voltar ao tamanho desktop (`resize_window` preset desktop) ao terminar.

Expected: visual consistente com o Design System (creme, dourado, marrom, oliva; títulos em Outfit; números em Plex Mono); nada cortado; nenhum erro no console.

- [ ] **Step 8: Conferir que em produção a rota não existe**

Run: `pnpm --filter @ovo/site build && pnpm --filter @ovo/site start`, abrir `http://localhost:3002/ui-kit`.
Expected: página 404. Encerrar o servidor depois.

- [ ] **Step 9: Commit**

```bash
git add packages/ui apps/site/src/app/ui-kit .claude/launch.json
git commit -m "feat(ui): página /ui-kit de conferência dos componentes (só dev, só no site)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Verificação final e aprovação das Etapas 0 e 1

**Files:**
- Modify: `CLAUDE.md` (raiz) — seção "Current State"
- Create: screenshots em `docs/superpowers/screenshots/2026-10-07-etapa-1/` (opcional, só se o usuário pedir para versionar)

**Interfaces:**
- Consumes: tudo das Tasks 1–9.
- Produces: etapas 0 e 1 verificadas, prontas para a aprovação do usuário; insumo do plano da Etapa 2 (site).

- [ ] **Step 1: Rodar todas as verificações automáticas**

Run:
```bash
pnpm typecheck
pnpm lint
pnpm test
pnpm --filter @ovo/ui test
pnpm seguranca:segredos
```
Expected: tudo passa. Se `DATABASE_TEST_URL` estiver definido no `.env`, rodar também `pnpm seguranca` e `pnpm teste:banco` (nada nesta entrega toca o banco; devem continuar passando).

- [ ] **Step 2: Provar que nenhuma regra de segurança nem lógica foi tocada**

Run:
```bash
git diff main --stat -- 'apps/*/src/app/**/acoes.ts' 'apps/*/src/middleware.ts' 'packages/database' 'packages/config'
```
Expected: **saída vazia** (nenhum desses arquivos foi alterado).

- [ ] **Step 3: Conferir a mudança de visual nas telas ainda não migradas**

Os apelidos `--cor-*` agora apontam para os tokens novos. Com os três servidores no ar (`site`, `assinante`, `gestao`), abrir a home do site, `/entrar` do assinante e `/entrar` da gestão (telas públicas, sem login) em 1280 e 375 de largura. Anotar (sem corrigir ainda): cores dos botões (laranja → dourado), fonte do texto (Archivo) e dos títulos (Outfit), qualquer texto ilegível ou quebra de layout. Isso entra como lista de atenção no plano da Etapa 2.

Expected: nenhuma tela quebrada; telas legadas legíveis, só com cor e fonte novas.

- [ ] **Step 4: Atualizar o `CLAUDE.md` da raiz**

Na seção "Current State", acrescentar este bullet:

```markdown
- **Visual (07/10/2026):** `packages/ui` agora traz os tokens do Design System (contraste AA medido em `pnpm --filter @ovo/ui test`), `next/font` (Outfit, Archivo, IBM Plex Mono) e a biblioteca de componentes (`@ovo/ui`: core, forms, data, navigation, feedback). Telas antigas ainda usam os apelidos `--cor-*`; migração por app nas Etapas 2–4 (spec e planos em `docs/superpowers/`). Conferência dos componentes: `http://localhost:3002/ui-kit` (só em dev). Botão do `@ovo/ui` tem `type="button"` por padrão: em formulário passe `type="submit"`.
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: registra a fundação visual e a biblioteca @ovo/ui no CLAUDE.md

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Gate de aprovação (obrigatório)**

Enviar ao usuário os screenshots de `/ui-kit` (desktop e celular) e do antes/depois das três telas públicas, junto com a lista de atenção do Step 3. **Parar e esperar aprovação explícita.** Só depois escrever o plano da Etapa 2 (site público) com `superpowers:writing-plans`.

---

## Self-Review (feita ao escrever)

**Spec coverage:** tokens e apelidos (T1), fontes (T2), componentes core/forms/data/navigation/feedback (T3–T8), página de conferência (T9), contraste AA, 14px no cliente, sem cor/fonte literal e sem px em fonte (guardas T2/T3), foco visível (base.css T2 + `:focus-visible` nos componentes), Etapas 2–5 (planos futuros, declarado no cabeçalho), Banco intocado e arquivos de segurança intocados (T10 Step 2). Itens do spec que **não** têm tarefa aqui por pertencerem às Etapas 2–5: Navbar, Hero, PlanCard, ComparisonTable, FaqAccordion, Footer, blocos do portal, `BottomNav` no layout da gestão, CSP ativo, remoção dos apelidos.

**Placeholders:** nenhum "TBD". Onde a fonte é um arquivo do Design System (ícones, tokens), há comando exato que gera o arquivo.

**Consistência de tipos:** `IconName` vem de `core/icons.ts` e é reexportado por `Icon.tsx`; `ButtonProps.type` padrão `'button'` (Review Focus 1); `Sidebar`/`Tabs`/`BottomNav` usam `LinkComponent?: ElementType`; `Pagination` usa `hrefFor`/`onChange`; classes `ovo-*` citadas nos `.tsx` conferidas contra o CSS pelo teste de guardas.

**Review Focus coberto:** (1) Task 3 `button.test.tsx`; (2) Task 6 `data.test.tsx` (ProgressBar); (3) Task 7 `navigation.test.tsx` (Pagination); (4) Task 5 `forms.test.tsx`; (5) Tasks 4 e 6 (`Avatar`, `DataTable` vazia).
