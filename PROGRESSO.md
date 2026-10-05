# Progresso — Sistema de gestão Ovo di Onça

Atualizado em 25/09/2026, no meio da **Fase 7**. Este arquivo é um retrato do momento e, ao mesmo tempo, o **prompt para retomar** o trabalho (seção "PROMPT DE RETOMADA", no fim). Regras de negócio: `DECISOES.md`. Como a autorização funciona: `README.md` (ambos ainda NÃO refletem o que foi feito nesta sessão — atualizar no fim, ver "Pendências de documentação").

---

## 1. Onde estamos, em uma linha

Fases 1 a 6 estão **prontas e verificadas** (banco, telas, testes SQL). A Fase 7 (área do assinante) tem a **migration aplicada**, mas falta o teste SQL (o arquivo atual é um rascunho quebrado), as telas do dono para vínculo/solicitações e **todo o app `assinante`**. A Fase 8 (`/configuracoes`) não começou. O teste manual no navegador e a limpeza dos dados de teste ainda não foram feitos.

## 2. Estado de cada fase

| Fase | O quê | Banco | Telas | Testes SQL | Situação |
|---|---|---|---|---|---|
| 1 | Clientes completos (endereço, e-mail único, busca/filtros) + Área de entrega | ✔ mig. 06 | ✔ | ✔ 8/8 | **pronta** |
| 2 | Assinaturas | ✔ mig. 07 | ✔ | ✔ 22/22 | **pronta** |
| 3 | Entregas | ✔ mig. 08 | ✔ | ✔ 23/23 | **pronta** |
| 4 | Faturas (cobrança manual) | ✔ mig. 09 | ✔ | ✔ 26/26 | **pronta** |
| 5 | Pausar / cancelar / reativar | ✔ mig. 10 | ✔ | ✔ 17/17 | **pronta** |
| 6 | Auditoria / histórico | ✔ mig. 11 | ✔ `/historico` | ✔ 19/19 | **pronta** |
| 7 | Área do assinante | ✔ mig. 12 aplicada | ✘ | ✘ rascunho quebrado | **em andamento** |
| 8 | `/configuracoes` | — | ✘ | — | **não iniciada** |

Suítes anteriores também passam (rodadas após a Fase 6): `teste:autorizacao` 25/25, `teste:estrutura` 5/5. **Não rodei ainda** `pnpm seguranca` inteiro (o script de segredos) nem `pnpm build` depois da Fase 1 (só `typecheck` e `lint`, que passam até a Fase 6).

## 3. Decisões de negócio do dono (25/09/2026) — já implementadas

1. **Valor da fatura é calculado**: `(pentes × preço do pente + dúzias × preço da dúzia) × planos.entregas_por_mes`; 10% (`planos.desconto_primeiro_mes_pct`) só na **primeira fatura não cancelada** do cliente, se `clientes.desconto_primeiro_mes_aplicavel`. O dono pode ajustar o valor ao criar. `entregas_por_mes` = 4/2/1 foi **derivado** dos preços documentados (R$164/82/41, pente R$41) → **a confirmar**.
2. **Status do cliente acompanha a assinatura**: pausar → `suspenso`; cancelar → `cancelado`; reativar → `ativo` se já houve fatura paga, senão `cadastro_andamento`. Primeira fatura paga → `ativo`.
3. **Pausar/cancelar cancela entregas pendentes E faturas pendentes** (atrasadas continuam cobráveis; pagas não mudam).
4. **Vínculo conta↔cliente AUTOMÁTICO quando o e-mail é igual** (contra a recomendação). ⚠️ Risco aceito: sem confirmação de e-mail, quem criar conta com o e-mail de outra pessoa vê os dados dela. Salvaguardas já no banco: só cliente sem conta; só conta `assinante`; auditoria (`conta_vinculada`); desvincular não religa sozinho (o vínculo só roda na criação da conta, na criação do cliente e quando o e-mail do cliente MUDA).

Decisões antigas que continuam valendo (DECISOES.md): frete incluso, 10% no 1º mês, ancoragem em quarta (intervalos 7/15/30, `ancorar_em_quarta`), falha de entrega reagenda, todo o histórico (nada de cascade), papéis `dono`/`assinante`, sem granja.

## 4. Decisões que continuam SEM resposta (não inventar; listar como "DECISÃO DE NEGÓCIO NECESSÁRIA" no relatório final)

- Preço da dúzia (`config_negocio.preco_duzia_centavos` = 0, placeholder).
- Confirmar `entregas_por_mes` 4/2/1.
- Pentes por entrega quando `clientes.pentes_padrao` é nulo: hoje usa **1** (sinalizado).
- Estorno de fatura já paga (hoje: fatura paga **não** pode ser cancelada).
- Congelar preço/endereço na entrega (hoje a agenda lê o endereço atual do cliente).
- Fatura durante pausa além de cancelar as pendentes; vencimento padrão (hoje o dono escolhe).
- Regra de assinatura `encerrada` (existe no enum, sem tela).
- Assinatura para cliente fora da área: **bloqueada** (interpretação de `pre_venda`). Uma assinatura vigente (ativa/pausada) por cliente: regra de integridade adotada.
- Dourado da marca e as duas fontes (nem carregadas hoje).
- Exigir e-mail verificado para o vínculo automático (depende de envio de e-mail, que não existe).

## 5. Banco de dados

**Neon (produção de desenvolvimento, único banco).** 12 migrations aplicadas, em `packages/database/migrations/`:

| # | Arquivo | Conteúdo |
|---|---|---|
| 00–05 | (anteriores) | Better Auth, papéis/perfis/RLS, config+planos+faixas, clientes, grant do dono, desconto por cliente |
| 06 | `…406000_fase1-clientes-endereco-completo` | `numero`, `bairro`, `cidade`, `estado`; índice único `clientes_email_unico_idx` (lower(email)) |
| 07 | `…407000_fase2-assinaturas` | enum `status_assinatura`, tabela `assinaturas`, índice `assinaturas_vigente_idx`, RLS, `hoje_sp()`, `proxima_quarta()`, `quarta_mais_proxima()`, `data_primeira_entrega()`, `data_proxima_entrega()`, `criar_assinatura()`, `alterar_plano_assinatura()` |
| 08 | `…408000_fase3-entregas` | `status_entrega`, tabela `entregas` (+ `reagendada_de`), gatilho que mantém `assinaturas.proxima_entrega`, RLS, `criar_assinatura` recriada (cria 1ª entrega), `marcar_entrega()`, `agendar_entrega()`, `observacao_entrega()` |
| 09 | `…409000_fase4-faturas` | `planos.entregas_por_mes`, `status_fatura`, `metodo_pagamento`, tabela `faturas`, RLS, `calcular_valor_fatura()`, `criar_fatura()`, `registrar_pagamento()`, `cancelar_fatura()`, `marcar_faturas_atrasadas()` |
| 10 | `…410000_fase5-ciclo-de-vida` | `pausar_assinatura()`, `cancelar_assinatura()`, `reativar_assinatura()` (pula para o ciclo seguinte se a data já tem entrega viva), `cancelar_pendencias_da_assinatura()` |
| 11 | `…411000_fase6-auditoria` | tabela `auditoria` (imutável, até para o dono do banco), função `auditar()` (gatilho genérico, lê `app.usuario_id` e `app.motivo`), gatilhos em clientes, assinaturas, entregas, faturas, config_negocio, planos, faixas |
| 12 | `…412000_fase7-area-assinante` | vínculo automático (`vincular_conta_ao_cliente` em `"user"`, `clientes_vincula_conta` em `clientes`), `atualizar_meus_dados` recriada com número/bairro/cidade/estado e erros `OV001`, tabela `solicitacoes_assinatura` (+ enums, RLS, índice `solicitacoes_pendente_idx`), `solicitar_alteracao_assinatura()` (concedida a `app_usuario`), gatilho de auditoria |

Convenções que valem para todo código novo:
- **Erro exibível ao usuário** = `raise exception '<texto em pt-BR>' using errcode = 'OV001'`. A aplicação (`lib/erros.ts`) só mostra mensagens desse código (ou `ErroNegocio`); o resto vira "Erro inesperado. Nada foi salvo".
- Toda função nova: `set search_path = public` + `revoke execute … from public`; só é concedida a `app_usuario` se for o caminho do assinante (whitelist em `tests/lei1-estrutura.sql`).
- Toda tabela nova: RLS ligada na mesma migration, `select` para `app_usuario` só por policy (assinante lê o próprio via `clientes.usuario_id`; dono lê tudo), **nenhum** grant de escrita; FKs `on delete restrict`.
- Dinheiro em centavos inteiros. Datas de negócio em `date`; "hoje" = São Paulo.
- `comoUsuario()` roda como `app_usuario`, que **não pode chamar funções revogadas** (ex.: `hoje_sp()`): nas leituras, passe a data como parâmetro (`hojeEmSaoPaulo()`), como fazem `/` e `/entregas`.
- Ao editar uma migration já aplicada: `pnpm db:reverter` (desfaz só a última) e `pnpm db:migrar`.

## 6. Código (o que foi criado nesta sessão)

**Pacote `packages/database`**: `comoAdmin(trabalho, { usuarioId })` (declara quem age — a auditoria grava); mensagem de permissão "Você não tem permissão para realizar esta ação." em `auth/papel.ts`; scripts `teste:fase1` … `teste:fase6` no `package.json`.

**`apps/gestao`** (porta 3000):
- `src/lib/`: `tipos.ts`, `erros.ts` (`ErroNegocio`, `rodar()`, `traduzirErro()`), `dono.ts` (`comoDono()` = `exigirDono()` + `comoAdmin({usuarioId})`, **único caminho de escrita**), `validacao.ts`, `formatar.ts`, `rotulos.ts`, `diff.ts`.
- `src/app/_componentes/`: `form-acao.tsx` (`FormAcao`: envia por `onSubmit`, mostra sucesso/erro, não zera campos em erro), `pagina.tsx` (`Pagina`, `SemPermissao`, `Aviso`, menu).
- Padrão de Server Action: arquivo `'use server'`, `export async function nome(_estado: Estado, dados: FormData): Promise<Estado> { return rodar(async () => { …; return 'mensagem de sucesso'; }); }` (precisa ser `async function` declarada, não `const`).
- Telas: `/` (painel + "Hoje"), `/clientes`, `/clientes/novo`, `/clientes/[id]` (dados, assinaturas, nova assinatura, link de histórico), `/area-de-entrega`, `/assinaturas`, `/assinaturas/[id]` (situação, entregas, agendar, faturas, nova fatura, trocar plano), `/entregas` (hoje/pendentes/atrasadas), `/faturas` (devendo/pagas/todas), `/historico`.
- Ações: `clientes/acoes.ts`, `area-de-entrega/acoes.ts`, `assinaturas/acoes.ts` (criar, trocar plano, pausar, cancelar, reativar), `entregas/acoes.ts`, `faturas/acoes.ts`.
- Menu (`pagina.tsx`) já aponta para `/configuracoes` (**ainda não existe**, dá 404).

**`apps/assinante`** (porta 3001): **inalterado** — ainda é o marcador "Fase 0" e o middleware manda para `/entrar` que não existe.

**Testes SQL** em `packages/database/tests/`: `teste-fase1-clientes.sql` … `teste-fase6-auditoria.sql` (todos passam) e `teste-fase7-assinante.sql` (⚠️ **rascunho quebrado** — tem SQL inválido no fim; reescrever do zero).

## 7. Ambiente e sujeira de teste (limpar antes de terminar)

- **Servidor de desenvolvimento do gestão pode estar rodando em segundo plano** (`pnpm dev:gestao`, porta 3000, log em `scratchpad/dev-gestao.log`). Parar antes de `pnpm build`, ou usar outra porta.
- **Conta de teste no banco**: `e2e-dono@ovo-teste.test`, nome "[TESTE] Dono E2E", **papel `dono`** (criada por sign-up e promovida por SQL, porque a senha do dono real não é conhecida). A senha estava em `scratchpad/senha-e2e.txt` (temporária; se sumir, criar outra conta de teste). **Remover ao final** (`delete from "user" where email = 'e2e-dono@ovo-teste.test'`, cascade leva o perfil).
- **Regra do navegador**: não digito senha em formulário de login. Para o teste manual, **o usuário faz o login** no Chrome "Browser 2" (deviceId `b2908d8a-41b2-4116-9949-227db8bf8f49`, já selecionado; há uma aba vazia aberta, tabId 827017680) e eu conduzo o resto.
- **Clientes antigos "Teste Claude (pode apagar)" e "Teste Claude 2 editado"** já existiam (sessão anterior): não tocar sem o usuário pedir.
- **Auditoria é imutável**: para limpar dados de teste que geraram linhas de auditoria, desligar o gatilho só durante a limpeza (`alter table auditoria disable trigger auditoria_sem_alteracao;` … e religar com `enable trigger`), e avisar o usuário. Dados criados no teste manual devem ter nome com prefixo `[TESTE]`.
- **Bloqueio**: ler e-mails/dados pessoais de clientes reais foi negado pelo classificador; consultar só contagens/estrutura.
- Git: **nenhum commit** foi feito nesta sessão (nem deve, a menos que o usuário peça). `Ovo di Onça Design System*` continua não ignorado (85 MB + 84 MB zip).

## 8. O que falta (ordem)

**Fase 7 — terminar**
1. Reescrever `tests/teste-fase7-assinante.sql` (script `teste:fase7` no `package.json`). Cobrir: vínculo automático nos dois sentidos (caixa diferente); não vincula e-mail de conta `dono`; desvincular + salvar sem trocar e-mail **não** religa; isolamento entre duas contas em clientes, assinaturas, entregas, faturas e solicitações; A não altera B via `atualizar_meus_dados`; A altera os próprios `bairro/cidade/estado`; estado inválido → `OV001`; assinante não altera e-mail/plano/status (nem direto nem pela função); solicitar pausa/cancelamento da própria assinatura; alheia recusada; duplicada pendente recusada; pausa em assinatura não ativa recusada; assinante não insere em `solicitacoes_assinatura`; anon não lê nenhuma tabela de negócio; auditoria registra a solicitação com o `usuario_id` do assinante (ação `solicitacoes_assinatura_insert`) e o vínculo automático como "sistema" (`usuario_id` nulo).
2. Gestão — ficha do cliente (`clientes/[id]/page.tsx`): seção **Conta de login** (mostrar conta vinculada lendo `"user"` via `comoDono`; ações `vincularConta` por e-mail e `desvincularConta` em `clientes/acoes.ts`; validar: conta existe, é `assinante`, não está ligada a outro cliente, cliente sem conta).
3. Gestão — `/assinaturas`: bloco **Solicitações pendentes** (lista de `solicitacoes_assinatura` com cliente, tipo, motivo; ações "atendida"/"recusada" via `comoDono`, gravando `resolvida_em` e `resolvida_por`; o dono então pausa/cancela pela própria assinatura). Acrescentar nomes `solicitacoes_assinatura_insert/_update` em `historico/page.tsx` (`NOME_ACAO`).
4. Gestão — `apps/gestao/src/app/api/auth/[...all]/route.ts`: recusar `sign-up` (POST em `/sign-up/*`) para fechar o cadastro público no app do dono (confirmado: hoje `POST /api/auth/sign-up/email` responde 200).
5. `apps/assinante`: (a) `next.config.ts` carregar o `.env` da raiz como o gestão faz (+ `dotenv` em devDependencies); (b) rota `/api/auth/[...all]`; (c) `/entrar` e `/cadastro` (o cadastro cria a conta; o vínculo é automático pelo e-mail); (d) `/` com meus dados, minha assinatura, plano, próxima entrega, histórico de entregas, faturas (tudo por `comoUsuario` + RLS — o assinante **nunca** usa `comoAdmin`); (e) editar dados pessoais por `atualizar_meus_dados` (chamada via `comoUsuario`, caminho real da RLS); (f) pedir pausa/cancelamento por `solicitar_alteracao_assinatura`; (g) botão Sair; (h) se a conta não estiver vinculada a nenhum cliente: mensagem "sua conta ainda não está vinculada a um cadastro — fale com a Ovo di Onça". Duplicar em `apps/assinante/src/lib/` só o necessário (`tipos`, `erros`, `validacao`, `formatar`, `form-acao`) — decisão: **sem pacote novo**. Usar `pnpm --filter @ovo/assinante dev` (porta 3001) e lembrar de `BETTER_AUTH_URL`/`trustedOrigins` (já incluem 3000 e 3001).

**Fase 8** — `/configuracoes` (gestão): formulário de `config_negocio` (preço do pente e da dúzia em reais → centavos, dia e hora de corte, `bonus_indicador_pct`, `teto_credito_indicacao_pct`) e de cada plano (nome, `intervalo_dias`, `ancorar_em_quarta`, `freshness_max_dias`, `frete_centavos`, `desconto_primeiro_mes_pct`, `entregas_por_mes`, `ativo`), com ação em `configuracoes/acoes.ts` via `comoDono`. Não inventar configurações novas. `config_negocio.atualizado_em` não tem gatilho: setar na ação. Registrar em `DECISOES.md` que preço da dúzia é pendente.

**Verificação final**
6. Encadear `teste:fase1..7` no script `seguranca` do `package.json` raiz; rodar `pnpm seguranca` (segredos + estrutura + autorização) e todas as suítes; `pnpm typecheck`; `pnpm lint` (`next lint` em cada app); `pnpm build` (parar o dev server antes); conferir `bash scripts/verificar-segredos.sh` (item 4 exige `exigirDono`/`exigirPapel` junto de `comoAdmin` — hoje só `lib/dono.ts` usa `comoAdmin`).
7. **Teste manual pelo navegador** (pedir o login ao usuário): fluxo do dono — criar cliente → endereço → área de entrega (cadastrar faixa antes!) → criar assinatura → ver entrega → marcar entregue → criar fatura → registrar pagamento → pausar → reativar → cancelar → consultar histórico; e fluxo do assinante — criar conta com o e-mail do cliente (vínculo automático) → entrar → ver só os próprios dados → tentar acessar dado de outro (URL/ID de outro cliente) → confirmar RLS.
8. Limpeza dos dados `[TESTE]` e da conta de teste (ver seção 7); parar servidores; fechar a aba do Chrome.
9. Atualizar `README.md` (situação, telas, testes: hoje diz "ainda não existe tela" e "15/25 verificações"), `DECISOES.md` (decisões 1–4 desta sessão + pendências da seção 4), e este arquivo.
10. **Relatório final** no formato pedido: o que foi implementado; mudanças no banco; migrations; telas; Server Actions; testes executados; o que passou; o que falhou; o que falta; próximo passo recomendado; lista "DECISÃO DE NEGÓCIO NECESSÁRIA".

## 9. Problemas já vistos (para não repetir)

- Em teste SQL: `ON DELETE RESTRICT` levanta `restrict_violation` (23001), não `foreign_key_violation`; guardar `count(*)` em variável de tipo `date`/`uuid` dá erro; `set local role` em bloco `do $$` exige `reset role` também no ramo de exceção.
- Em PL/pgSQL: expressão `CASE` é analisada inteira — não use `old.coluna` de coluna que só existe em algumas tabelas do gatilho genérico (usar `to_jsonb(old)->>'coluna'`); `array || 'texto'` interpreta o literal como array → usar `array_append`.
- Next: arquivo `'use server'` só exporta `async function`; `React 19` zera campos do `<form action>` (por isso `FormAcao` usa `onSubmit`); `comoUsuario` não executa funções revogadas.
- Better Auth em navegador exige `Origin` em `trustedOrigins` (3000 e 3001 já configurados); `curl` de sign-up precisa do header `Origin`.
- Migration editada depois de aplicada: reverter a última e reaplicar.

---

## PROMPT DE RETOMADA (copie tudo abaixo numa nova sessão)

```
Você vai continuar o desenvolvimento do sistema de gestão da Ovo di Onça
(pasta: C:\Users\jbrun\Documents\Ovo di Onça\siteesistema\sistema — monorepo pnpm, Next.js
15 + TypeScript, PostgreSQL no Neon, Better Auth; apps/gestao na porta 3000,
apps/assinante na 3001, packages/database com migrations e testes SQL).

ANTES DE QUALQUER COISA, leia por inteiro:
1. sistema/PROGRESSO.md  (este arquivo: estado exato, decisões, convenções,
   o que falta, sujeira de teste a limpar)
2. sistema/DECISOES.md e sistema/README.md  (regras de negócio e modelo de
   autorização; ainda não refletem as fases 2–7)
3. As migrations 06 a 12 em packages/database/migrations/ e os arquivos de
   apps/gestao/src/lib e apps/gestao/src/app/_componentes.

OBJETIVO GERAL (já aprovado pelo dono): um sistema funcional capaz de
administrar CLIENTE → ASSINATURA → ENTREGA → FATURA → PAGAMENTO, com
PAUSAR/CANCELAR/REATIVAR, HISTÓRICO (auditoria) e uma ÁREA BÁSICA DO
ASSINANTE, sem o dono precisar mexer no banco. NÃO é hora de design: interface
mínima e funcional. Prioridade: funcionamento > banco > regras de negócio >
segurança > usabilidade > design.

ESTADO: fases 1–6 prontas e testadas. Fase 7: migration 12 aplicada; faltam o
teste SQL (o arquivo tests/teste-fase7-assinante.sql é um rascunho quebrado —
reescreva do zero), as telas do dono (vincular/desvincular conta, solicitações
pendentes), o fechamento do sign-up público no gestão e TODO o app assinante.
Fase 8 (/configuracoes) não começou. Depois: verificação final, teste manual
no navegador, limpeza dos dados de teste, atualização de README/DECISOES e
relatório final. A lista ordenada está na seção 8 do PROGRESSO.md — siga-a.

REGRAS DE TRABALHO (obrigatórias):
- Trabalhe em etapas: leia o código existente → migration → backend/funções
  SQL → interface mínima → testes → só então a próxima etapa.
- Reutilize a arquitetura: leitura por comoUsuario() (RLS); escrita SOMENTE
  por comoDono() (lib/dono.ts = exigirDono() + comoAdmin({usuarioId})); regras
  em funções SQL com erro exibível `using errcode = 'OV001'`; formulários com
  <FormAcao>; Server Actions como `export async function x(_estado: Estado,
  dados: FormData): Promise<Estado> { return rodar(async () => {...}) }`.
  NÃO crie um segundo sistema de autorização.
- Toda tabela nova: RLS na mesma migration, sem grant de escrita a papéis de
  aplicação, FKs `on delete restrict`. Toda função nova: `set search_path =
  public` e `revoke execute … from public` (grant a app_usuario só no caminho
  do assinante, com posse conferida na 1ª instrução e nome na whitelist de
  tests/lei1-estrutura.sql). Dinheiro em centavos inteiros.
- Nunca use DATABASE_ADMIN_URL fora do pacote de banco; nunca NEXT_PUBLIC_
  para segredo; não exponha credenciais nem leia dados pessoais reais de
  clientes (consulte só contagens/estrutura).
- Decisão de negócio não definida: NÃO invente — implemente o mínimo seguro,
  sinalize e liste como "DECISÃO DE NEGÓCIO NECESSÁRIA" no relatório final.
  Decisões já tomadas estão na seção 3 do PROGRESSO.md; as pendentes, na 4.
- Depois de cada etapa: pnpm typecheck, pnpm lint (next lint), testes SQL da
  fase (pnpm --filter @ovo/database teste:faseN), suítes anteriores (para
  regressão) e, ao fim, pnpm build (pare o dev server antes).
- Migration já aplicada que precisa mudar: pnpm db:reverter (só a última) e
  pnpm db:migrar.
- Não faça commit a menos que o usuário peça.
- Navegador: NÃO digite senha em formulário de login (regra de segurança do
  navegador). Peça ao usuário para entrar (conta de teste: e2e-dono@ovo-
  teste.test, papel dono; se a senha não estiver mais em
  scratchpad/senha-e2e.txt, crie outra conta de teste por sign-up e promova a
  dono por SQL) e conduza o resto. Chrome "Browser 2" (b2908d8a-41b2-4116-
  9949-227db8bf8f49) já foi escolhido pelo usuário; confirme com
  tabs_context_mcp. Não dispare alert/confirm.
- Dados de teste com prefixo [TESTE]; ao final remova-os, remova a conta de
  teste e pare os servidores. A tabela auditoria é imutável: para limpar as
  linhas de teste desligue o gatilho auditoria_sem_alteracao SÓ durante a
  limpeza, religue e AVISE o usuário. Não toque nos clientes "Teste Claude".

ENTREGA FINAL: relatório com (1) o que foi implementado, (2) o que mudou no
banco, (3) migrations criadas, (4) telas, (5) Server Actions, (6) testes
executados, (7) o que passou, (8) o que falhou, (9) o que ainda falta,
(10) próximo passo recomendado — mais a lista "DECISÃO DE NEGÓCIO NECESSÁRIA".

Comece confirmando o estado real: git status, pnpm typecheck, as suítes
teste:fase1..6 e teste:autorizacao/estrutura (devem passar), e se há servidor
rodando na porta 3000. Depois execute o item 1 da seção 8.
```
