# Visual do painel de gestão — diagnóstico e plano (19/10/2026)

Escopo: só `apps/gestao`. Site e portal do assinante não mudam. Nenhum `acoes.ts`, função SQL, migration, `exigirDono`, `comoDono`, middleware, script do `package.json` ou dependência é alterado.

## Decisões tomadas pela Bruna (19/10/2026)

| # | Decisão |
|---|---|
| A | Identidade do painel = **Design System oficial** (`Ovo di Onça Design System/`): dourado-gema e marrom-terra, oliva de apoio, cremes; Outfit (títulos e métricas), Archivo (interface), IBM Plex Mono (números). Aclonica/Poppins deixam de valer no gestão. |
| — | Visual feito **agora**, antes dos Blocos 2 e 3 do `PLANO-GESTAO-20261013.md`. As telas de assinatura e faturas serão ajustadas de novo quando as regras D1–D15 entrarem. |
| — | Ações destrutivas ganham **diálogo de confirmação** com o nome do registro. A ação de servidor chamada continua a mesma. |
| — | Telas do plano montadas no **Figma** para aprovação antes do código. |

Ajustes ao Design System por causa das regras do prompt mestre (sem criar um segundo sistema):
- Texto mínimo de **14px** em tudo, inclusive cabeçalho de tabela (em sentence case, sem caixa alta de 11px).
- Espaçamentos só de múltiplos de 4 que também são da escala de 8 do prompt: 4, 8, 12, 16, 24, 32, 48, 64. Padding de cartão 24px (o DS sugere 20).
- Sem `blur` no fundo do diálogo (scrim marrom sólido a 44%). Sem `scale` no clique do botão.
- Sem listras alternadas; célula com 12px de padding; valores em R$ à direita em IBM Plex Mono.

## 1. Diagnóstico (resumo)

- Interface "provisória, sem design": CSS global em `app/globals.css` (70 linhas); moldura em `_componentes/pagina.tsx`; todas as escritas por `FormAcao`.
- Fontes declaradas (Aclonica/Poppins) **nunca carregadas**: o painel aparece em `system-ui`.
- Todos os botões iguais (dourado), inclusive "Cancelar fatura" e "Remover faixa". `.perigo` e `.secundario` existem e não são usados.
- Menu sem item atual, quebra em várias linhas no celular. Situação em texto puro. Valores à esquerda. Até 5 `<details>` por linha de tabela.
- Entregas com 10 colunas, faturas com 7: no celular a tabela rola de lado e a agenda fica inutilizável.
- Hex soltos (`#fff` em `globals.css`), `style={{}}` em `entrar/page.tsx` e `sair-botao.tsx`, `opacity` em desabilitado.
- Não existem: `loading.tsx`, `error.tsx`, `not-found.tsx`, atalhos de teclado, exportação, paginação, ordenação, ações em lote, visão semanal de entregas. **Continuam fora** (não é visual).

### Inventário de comandos (todos preservados)

| Tela | Ações de servidor / interações |
|---|---|
| Menu | 8 destinos + Sair (`authClient.signOut`) |
| Entrar | login Better Auth |
| Painel `/` | `rodarRotinaDiaria`; links de pendências; `POST /api/rotina` (externo) |
| Clientes | busca GET `q`, `status`, `plano`; Limpar; Novo; Abrir |
| Novo cliente | `criarCliente` |
| Ficha do cliente | `atualizarCliente`, `vincularConta`, `desvincularConta`, `criarAssinatura`; link histórico |
| Assinaturas | `responderSolicitacao` (atender c/ executar e retorno previsto; recusar); busca GET `q`, `status` |
| Ficha da assinatura | `pausarAssinatura`, `cancelarAssinatura`, `reativarAssinatura`, `agendarEntrega`, `cancelarReposicao`, `definirFormaCobranca`, `gerarProximaCobranca`, `criarFatura`, `alterarPlanoAssinatura` + ações de entrega e de fatura |
| Entrega (linha) | `marcarEntrega` (entregue / não entregue + reagendar / cancelada), `definirHorarioEntrega`, `salvarObservacaoEntrega`, `registrarDefeito` |
| Entregas | visões dia / pendentes / atrasadas; filtro GET data e situação |
| Fatura (linha) | `registrarPagamento`, `cancelarFatura` |
| Faturas | visões; filtro GET `q`, `status`; total do recorte |
| Histórico | filtro GET tipo, id, de, até; links "abrir" |
| Área de entrega | `criarFaixa`, `editarFaixa`, `alternarFaixa`, `removerFaixa` |
| Configurações | `salvarConfiguracao`, `salvarPlano` |

## 2. Plano (Fase C, em ordem)

Cada etapa = um commit na branch `feat/visual-gestao`, com `pnpm typecheck`, `pnpm lint`, `pnpm test`, `pnpm seguranca` e `pnpm --filter @ovo/gestao build`, mais screenshots antes/depois em 360, 390, 768, 1024 e 1366 do app apontando para o **branch de teste** do Neon.

| Etapa | O quê | Arquivos |
|---|---|---|
| C1 Fundação | `packages/ui/src/ds.css` com os tokens do DS (cores, espaço, raio, sombra, movimento) importado **só pelo gestão**; `tokens.css` intacto (site e assinante não mudam). Fontes com `next/font/google` (auto-hospedadas, sem requisição externa, compatível com o CSP). Reset/base. | `packages/ui/src/ds.css`, `packages/ui/package.json` (só `exports`), `apps/gestao/src/app/layout.tsx`, `globals.css` |
| C2 Componentes | Em `apps/gestao/src/app/_componentes/`: `Botao` (primário, secundário, perigo, fantasma), `Selo` (ponto + texto), `Icone` (mapa Lucide do DS), `CartaoResumo`, `Tabela` + `ListaCartoes` (celular), `Campo`/`Selecao`, `Vazio`, `Aviso` (banner), `ConfirmarAcao` (diálogo nativo `<dialog>` com foco preso, Esc, clique fora, devolve foco). `FormAcao` só ganha classes. | `_componentes/*` |
| C3 Moldura | `Pagina`: rail marrom de 248px com item atual (`aria-current`), topo com título e data; no celular topo compacto + barra inferior (Painel, Entregas, Clientes, Faturas, Mais → Assinaturas, Histórico, Área de entrega, Configurações, Sair). Destinos idênticos aos atuais. | `pagina.tsx`, `sair-botao.tsx` |
| C4 Painel | Cartões com os números que já existem (entregas de hoje, atrasadas, pedidos, faturas vencidas, reposições, cobranças a gerar); aviso de faixa de CEP; rotina diária em bloco próprio; planos em tabela. Nenhuma métrica nova. | `page.tsx` |
| C5 Entregas | Abas dia / pendentes / atrasadas; filtro em linha; desktop em tabela (data+horário, cliente+telefone, endereço+bairro, quantidade, situação, ações); celular em cartões sem rolagem lateral. Ações da linha num botão "Ações" que abre o mesmo `FormAcao`. | `entregas/page.tsx`, `acoes-entrega.tsx` |
| C6 Ficha da assinatura | Cabeçalho com situação e dados-chave; seções em cartões (Situação, Pedidos, Entregas, Reposições, Cobrança e faturas, Trocar plano); pausar/cancelar/reativar com `ConfirmarAcao`. Mesmo HTML de formulário, mesmos `name`/`id`. | `assinaturas/[id]/page.tsx`, `solicitacoes.tsx`, `acoes-fatura.tsx` |
| C7 Demais telas | Faturas, Assinaturas, Clientes (lista, novo, ficha), Histórico, Área de entrega, Configurações, Entrar (sem `style={{}}`). | respectivos `page.tsx`, `campos-cliente.tsx`, `entrar/page.tsx` |
| C8 Confirmações | `ConfirmarAcao` em: cancelar assinatura, cancelar fatura, cancelar entrega, cancelar reposição, remover faixa, desvincular conta, recusar pedido. | componentes acima |
| C9 Estados | `loading.tsx` (esqueleto) por rota, `error.tsx` com "Tentar de novo", `not-found.tsx`; vazios com saída ("Limpar filtros"). | novos arquivos em `app/` |
| C10 Validação | Roteiro do Bloco 1 no branch de teste, só com teclado em 3 telas, e todas as ações do inventário. Relatório final. | `docs/` |

### Riscos

- `id`/`htmlFor` gerados por registro (`obs-e-${id}` etc.) precisam continuar únicos quando a mesma ação aparecer em tabela e em cartão (renderizar um ou outro, não os dois).
- Visibilidade de pausar/cancelar/reativar depende da situação: a lógica vem junto, sem mudança.
- Filtros são `method="get"` e vivem na URL: continuam assim.
- Telas de assinatura e faturas vão mudar de novo no Bloco 2 (regras D1–D15).

## 3. Figma (Fase B)

Arquivo: https://www.figma.com/design/VWi6R57E6kgByeou7jzURY

- Página **Componentes**: 19 ícones (Lucide do DS, um significado cada), Botão (Primário, Secundário, Perigo, Perigo contorno, Fantasma × 40/44px), Selo de situação (5 tons, ponto + texto), Item de menu, Item da barra inferior, Campo (padrão, foco, erro), Cartão de resumo, Linha de entrega, Cartão de entrega, Linha de fatura.
- Variáveis `Ovo DS / Cores` (39) e `Ovo DS / Medidas` (14); 11 estilos de texto (Outfit, Archivo, IBM Plex Mono; nada abaixo de 14px).
- Página **Telas**: Painel, Entregas, Ficha da assinatura (1366 e 360) e Confirmação de cancelamento (diálogo no desktop, folha inferior no celular). Nomes e números são ilustrativos.

### Lacunas de contraste encontradas no Design System (extensão mínima proposta)

Calculado pela fórmula WCAG 2.1; vários pares que o DS dá como aprovados ficam abaixo de 4.5:1 sobre o creme `#F9F5EA`:

| Token do DS | Contraste | Usado no painel |
|---|---|---|
| `--text-muted` `#8A7A63` | 3.82 | `#7A6142` (brown-500), 5.33 |
| `--text-link` / `--text-accent` `#A9791F` | 3.54 | `#7E5A15` (gold-700), 5.74 |
| `--text-success` `#0E8A31` | 4.10 (3.90 no selo) | `#0A6626` (green-700), 6.55 / 6.23 |
| `--text-on-inverse-muted` `#B7A98E` sobre o rail | 4.45 | `#D8C9AE` (brown-200), 6.31 |
| Cabeçalho de tabela suave sobre `#E6DCC5` | 4.26 | texto principal `#4A3F2E`, 7.55 |

Todos os substitutos já existem nas rampas do DS; nenhum hex novo.
