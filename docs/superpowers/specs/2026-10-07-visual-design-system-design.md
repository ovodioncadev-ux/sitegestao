# Sub-projeto 1 — Camada visual (Design System)

Data: 07/10/2026 · Status: aguardando revisão

## Contexto

O Ovo di Onça será publicado para clientes reais somente depois da integração com a API PIX do Sicoob (sub-projeto 2). A ordem combinada é: **1 Visual → 2 Pagamento Sicoob → 3 Pré-lançamento → 4 Publicação**. Este documento cobre só o sub-projeto 1.

## Objetivo

Aplicar o **Ovo di Onça Design System** nos três apps (`site`, `assinante`, `gestao`) por meio de uma biblioteca de componentes completa em `packages/ui`, usando o **Stitch** apenas como referência de estrutura das telas.

Critério de sucesso: todas as telas dos três apps usam a biblioteca e os tokens do Design System; nenhuma lógica, ação de servidor ou regra de autorização foi alterada; todas as verificações automáticas passam; o usuário aprovou os screenshots de cada etapa.

## Decisões já tomadas

| Tema | Decisão |
|---|---|
| Fonte de verdade visual | Design System: paleta (dourado-gema, marrom-terra, verde-oliva, cremes), fontes (Outfit, Archivo, IBM Plex Mono) e tom de voz |
| Papel do Stitch | Só estrutura e hierarquia das telas (sidebar, cards, hero, faixa final). Não define cor nem fonte |
| Abordagem | Biblioteca completa de componentes portada para `packages/ui` e telas reescritas em cima dela |
| Fotos | Não existem. Usa-se o glifo de ovo sobre creme, como o Design System prevê. O layout reserva o espaço |
| Fontes | Substitutas do Google Fonts (a marca não enviou os arquivos). Trocáveis em um único arquivo |

## Fora de escopo

- Funções que só existem no Stitch: rotas, lotes, postura, câmara fria, "Novo Registro de Coleta". Preços e dados continuam vindo do banco; os valores do mock (R$ 48/89/158 etc.) não são usados.
- Paginação das listas da gestão (limites de 200/300/500 linhas continuam).
- Tema escuro.
- Telas de pagamento do Sicoob (sub-projeto 2; usarão esta biblioteca).
- Qualquer mudança em `acoes.ts`, `exigirDono()`, `comoDono`, `FormAcao`, funções SQL, migrations ou RLS.

## Arquitetura

### Tokens
- `packages/ui/src/tokens.css` passa a conter os tokens do Design System (`tokens/*.css`: cores `--gold-*`, `--brown-*`, `--olive-*`, tipografia, espaçamento, raios, elevação, movimento).
- Os nomes atuais (`--cor-ouro`, `--cor-fundo`, `--texto-corpo` etc.) permanecem como **apelidos temporários** apontando para os tokens novos, para que telas ainda não migradas continuem funcionando. Os apelidos são removidos na etapa 5.
- Regra mantida: nenhum hex solto nos componentes.

### Fontes
- Outfit (títulos e métricas), Archivo (interface), IBM Plex Mono (números, IDs, deltas, com `tabular-nums`).
- Carregadas com `next/font` (auto-hospedadas), sem requisição externa em tempo de execução. Aclonica e Poppins são removidas na etapa 5.

### Componentes (`packages/ui/src`)
Portados do Design System para **TypeScript + classes CSS**; `:hover`, `:active` e `:focus-visible` ficam no CSS.

- **core:** Avatar, Badge, Button, Card, Icon, IconButton, Tag, Tooltip
- **forms:** Checkbox, Input, Radio, SearchField, Select, Switch
- **data:** BarChart, DataTable, ProgressBar, StatCard, Trend
- **navigation:** BottomNav, Pagination, Sidebar, Tabs, TopBar
- **feedback:** Banner, Dialog, EmptyState, Toast

Componentes de servidor por padrão. `'use client'` apenas onde há estado: Dialog, Tabs, Toast, Switch, menus da Sidebar/TopBar.

**Criados no estilo do Design System (não existem nele):** Navbar, Hero, PlanCard, ComparisonTable, FaqAccordion, Footer, e blocos do portal do assinante (passos de assinatura, cartão de assinatura).

### Acessibilidade
- Mínimo de 14px na área do cliente; 11–12px só em rótulo de tabela/overline no painel.
- Foco de teclado sempre visível.
- Contraste WCAG AA calculado nos testes. O dourado `#D4A437` não carrega texto claro: botões primários usam o tom escuro do dourado ou o marrom, conforme o contraste.

## Etapas e ordem

| Etapa | Entrega | Telas afetadas |
|---|---|---|
| 0. Fundação | Tokens, fontes, CSS base, apelidos `--cor-*` | nenhuma |
| 1. Componentes | Biblioteca completa + página interna `/ui-kit` por app para conferência (só em desenvolvimento) | só `/ui-kit` |
| 2. Site público | Navbar, Hero, planos, comparação, bairros, FAQ, rodapé, com o layout do Stitch | `apps/site` |
| 3. Portal do assinante | entrar, cadastro, assinar (3 passos), painel, dados | `apps/assinante` |
| 4. Gestão | Sidebar, topo, cards de resumo, tabelas (clientes, assinaturas, faturas, entregas, histórico), formulários, configurações, `BottomNav` no celular | `apps/gestao` |
| 5. Fechamento | Remoção dos apelidos e das fontes antigas, revisão de contraste, teste em celular, passada de consistência | todos |

Cada etapa é um commit (ou branch) próprio, para poder ser revertida isoladamente, e termina com screenshots para aprovação do usuário antes da seguinte.

## Regras transversais

- **Só a camada visual muda.** Formulários continuam enviando para as mesmas ações de servidor e usando `{ok, mensagem}`.
- **Mobile completo:** desktop (1280) e celular (375) sem perda de recurso.
- **Estados:** vazio, erro, carregando e desativado desenhados em todas as telas, no tom do Design System (frases curtas, dado antes do adjetivo, sentence case, formato pt-BR).
- **CSP:** CSS por classes e fontes auto-hospedadas; ao final, os apps rodam com CSP ativo (`modoRelatorio: false`) para provar que nada é bloqueado.
- **Banco:** não escrever no banco principal. Leitura apenas, ou branch de teste do Neon.

## Verificação

- Automática a cada etapa: `pnpm typecheck`, `pnpm lint`, `pnpm test`, `pnpm seguranca`.
- Teste novo (mesmo estilo de `apps/assinante/tests/whatsapp.test.ts`): reprova hex solto e fonte fora do conjunto nos componentes; calcula contraste WCAG dos pares de cor dos tokens.
- Visual: screenshots antes/depois, desktop e celular, no navegador embutido, de cada tela migrada.

## Riscos

| Risco | Tratamento |
|---|---|
| Contraste do dourado com texto claro | Tom escuro para texto/botão; checagem automática |
| Fontes substitutas | `next/font`; troca em um arquivo quando houver fonte licenciada |
| CSP ativado no futuro quebrar estilos/fontes | Sem inline e sem fonte externa; teste final com CSP ativo |
| Regressão em formulários/autorização | Nenhuma alteração em `acoes.ts`/SQL; testes a cada etapa |
| Tabelas largas da gestão | Rolagem horizontal no desktop, cartões no celular |
| Restos de Aclonica/Poppins | Busca na etapa 5 |

## Pendências do usuário

- Fotos reais da granja/produto (opcional; sem elas, glifo de ovo).
- Fontes licenciadas da marca (opcional; sem elas, Outfit/Archivo/Plex Mono).
- Solicitar a API Pix ao Sicoob em paralelo (afeta os sub-projetos 2 e 4, não este).
