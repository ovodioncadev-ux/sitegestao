# Plano do sistema de gestão — Ovo di Onça (13/10/2026)

Revisão feita só com leitura (código de `apps/gestao`, `packages/database`, `DECISOES.md`, `PROGRESSO.md`, `docs/DIAGNOSTICO-20260930.md`, `docs/REGRAS-DE-NEGOCIO-20260930.md`, spec e plano do visual de 07/10). Nada foi alterado no código nem no banco.

---

## 1. Onde o gestão está hoje

**Pronto e funcionando no banco:** clientes, área de entrega, assinaturas, entregas, faturas manuais, pausa/cancelamento/reativação, reposição de defeitos, pedidos do assinante (com resposta do dono), forma de cobrança (pix/cartão), cobrança do período, rotina diária (botão + `POST /api/rotina`), `/configuracoes`, histórico/auditoria. Calendário nas quartas (D10) e corte de segunda 18h (D9) já valem para as datas de entrega.

**O que ainda falta, em resumo:**

| Área | Situação |
|---|---|
| Teste do painel no navegador | Nunca feito de ponta a ponta (só as funções SQL foram testadas) |
| Regras de cobrança D1–D8, D11, D15 | Decididas em 30/09, **não implementadas**. O código ainda cobra mensalidade fixa, entrega antes do pagamento, cancela na hora, não tem crédito de pausa nem bloqueio por atraso |
| Fatura pelo calendário (D10) | As datas já seguem as quartas, mas o **valor** da fatura ainda é a fórmula antiga (`mensalidade-fixa-v1`) |
| CI | O workflow foi removido (commit `a2bddd2`). Nada roda sozinho hoje |
| Rate limit nas Server Actions | O helper existe (`rate-limit-server-action.ts`), mas **nenhuma ação** do gestão usa |
| CSP | Ainda em modo relatório (`modoRelatorio` padrão `true`) |
| Better Auth | Conecta com `DATABASE_ADMIN_URL` (dono do banco, ignora RLS) |
| `comoAdmin` direto em página | `assinaturas/[id]/page.tsx` (valor sugerido) e `clientes/[id]/page.tsx` (conta) chamam `comoAdmin` fora do `comoDono` |
| Listas | Sem paginação (limites fixos de 200/300/500) |
| Visual | Interface "provisória, sem design". `packages/ui` só tem `tokens.css`: as Etapas 0 e 1 do plano visual ainda não foram executadas |
| Pagamento online (Sicoob PIX) | Não existe. É o sub-projeto 2 |
| E-mail | Não existe. Sem ele não há vínculo automático nem aviso ao cliente |
| Dados reais | 0 faixas de CEP ativas: ninguém consegue assinar |

---

## 2. Decisões que ainda dependem de vocês (Fred e Bruna)

Não dá para programar estes itens sem resposta. Vale resolver antes dos blocos indicados.

| # | Pergunta | Bloco que trava |
|---|---|---|
| A | **Fontes do visual:** o `design.md` do projeto diz Aclonica + Poppins; o spec de 07/10 diz Outfit + Archivo + IBM Plex Mono. Qual vale? | 5 |
| B | **Estorno de fatura já paga:** existe? Com motivo? Vira crédito ou dinheiro? | 2 |
| C | **D3, cancelamento com crédito sobrando:** confirmar a leitura "o crédito não vira dinheiro; o cliente recebe os pentes antes de encerrar" | 2 |
| D | **Endereço congelado na entrega:** se o cliente muda de endereço, entregas já agendadas vão para o novo ou o antigo? | 2 |
| E | **Status `encerrada`:** quando uma assinatura vira "encerrada" (diferente de cancelada)? Ou sai do enum? | 2 |
| F | **Faixas de CEP reais** que vocês atendem | 7 |
| G | **Sicoob:** API Pix solicitada? Certificado e credenciais de sandbox? | 6 |
| H | **Provedor de e-mail** (Resend ou outro) e domínio de envio | 6 |

---

## 3. Os blocos, em ordem

| Bloco | O quê | Depende de |
|---|---|---|
| 0 | Base: CI de volta, limpeza, conferência do banco de teste | — |
| 1 | Teste de ponta a ponta do painel no navegador | 0 |
| 2 | Regras de cobrança D1–D15 (banco + telas), em 7 etapas | 1, decisões B–E |
| 3 | Ajustes técnicos do painel (sem regra nova) | 1 |
| 4 | Segurança | 0 |
| 5 | Visual do gestão (Etapas 0, 1 e 4 do plano visual) | 2 e 3 estáveis, decisão A |
| 6 | Pagamento Sicoob PIX + e-mail | 2, decisões G e H |
| 7 | Pré-lançamento | todos |

Regra de ouro: **um bloco (ou uma etapa do bloco 2) por sessão do Claude Code**, um commit por etapa, e só passar para a próxima com os testes verdes.

---

## 4. Cabeçalho comum (cole antes de qualquer prompt abaixo)

```
Projeto: Ovo di Onça (monorepo pnpm em C:\Users\jbrun\Documents\Ovo di Onça).
Antes de mexer em qualquer coisa, leia: CLAUDE.md, DECISOES.md,
docs/REGRAS-DE-NEGOCIO-20260930.md, docs/PLANO-GESTAO-20261013.md e os
arquivos citados na tarefa.

Regras desta sessão:
- Toda escrita do painel passa por comoDono() (lib/dono.ts) e por função SQL
  com lista fechada de campos. Nunca update(req.body), nunca grant de escrita
  para app_usuario/app_anon.
- Erro exibível ao usuário = raise exception '<texto pt-BR>' using errcode = 'OV001'.
- Dinheiro em centavos inteiros; datas no SQL com fuso America/Sao_Paulo;
  sem Date do JS para regra de negócio.
- Migrations novas: RLS ligada na mesma migration, set search_path = public,
  revoke execute from public, FKs on delete restrict, gatilho auditar() em
  tabela de negócio.
- Banco: migre e teste SÓ no branch de teste (pnpm db:migrar:teste,
  DATABASE_TEST_URL). Não aplique no principal sem eu confirmar.
- Antes de dizer que terminou: pnpm typecheck, pnpm lint, pnpm test,
  pnpm teste:banco, pnpm seguranca. Mostre o resultado.
- Não invente regra de negócio. Se faltar decisão, pare e me pergunte.
- Faça commit só quando eu pedir. Branch própria para o bloco.
- No fim: atualize DECISOES.md (se mudou regra), CLAUDE.md ("Current State")
  e marque a etapa como feita em docs/PLANO-GESTAO-20261013.md.
```

---

## BLOCO 0 — Base

**O quê:** voltar a ter verificação automática e garantir que o ambiente de teste está limpo e separado.

- Recriar o workflow de CI (`.github/workflows/ci.yml`): `pnpm install --frozen-lockfile`, `typecheck`, `lint`, `test`, `seguranca`, `build` dos 3 apps. Testes SQL contra `DATABASE_TEST_URL` (segredo do GitHub), nunca o principal.
- Conferir se a conta `e2e-dono@ovo-teste.test` (papel dono) ainda existe no banco principal e removê-la.
- Rodar `pnpm db:limpar-teste` se ainda houver dados `[TESTE]`.
- Decidir o que fazer com a branch `feat/visual-fundacao-componentes` (hoje só tem docs).
- Pôr `Ovo di Onça Design System/`, `_tmp_*`, `build.log` e `graphify-out/cache` no `.gitignore`.

**Prompt:**
```
[cabeçalho comum]

Tarefa: BLOCO 0 do docs/PLANO-GESTAO-20261013.md.

1. Recrie .github/workflows/ci.yml (o anterior foi removido no commit a2bddd2
   por problema de permissão do token). Jobs: install com lockfile congelado,
   typecheck, lint, test, seguranca e build dos apps gestao, assinante e site.
   Um job separado roda pnpm teste:banco usando o segredo DATABASE_TEST_URL;
   se o segredo não existir, o job pula com aviso, sem falhar e sem usar
   DATABASE_URL. Permissões mínimas (contents: read). Me diga quais segredos
   eu preciso cadastrar no GitHub.
2. Consulte (só leitura, begin read only) se existe no banco PRINCIPAL a conta
   e2e-dono@ovo-teste.test e quantos usuários têm papel dono. Não apague
   nada: me mostre o resultado e o SQL de remoção para eu aprovar.
3. Conte as linhas com prefixo [TESTE] no principal e no branch de teste.
4. Ajuste o .gitignore (Design System, _tmp_*, build.log, graphify-out/cache)
   sem remover as linhas de .env.
5. Rode as verificações e me entregue um resumo: o que passou, o que falhou.
```

---

## BLOCO 1 — Teste de ponta a ponta do painel

**O quê:** o painel nunca foi usado de verdade no navegador. Antes de mudar regra, provar que o fluxo atual funciona e anotar o que quebra.

Roteiro: login do dono → cadastrar faixa de CEP → cliente → assinatura → entrega → marcar entregue → registrar defeito → fatura → pagamento → pausa com retorno → rotina diária → reativação → pedido do assinante (pelo app assinante) → resposta do dono → cancelamento → histórico → configurações.

**Prompt:**
```
[cabeçalho comum]

Tarefa: BLOCO 1 do docs/PLANO-GESTAO-20261013.md — teste manual de ponta a
ponta do painel do dono no navegador, apontando os apps para o BRANCH DE TESTE
do Neon (nunca o principal).

- Suba gestao (3000) e assinante (3001) com DATABASE_URL/DATABASE_ADMIN_URL
  do branch de teste. Me mostre como você fez isso antes de abrir o navegador.
- Eu faço o login; você não digita senha.
- Todo dado criado tem prefixo [TESTE].
- Siga este roteiro e, a cada passo, registre: OK / FALHOU (mensagem,
  print, causa provável):
  faixa de CEP -> novo cliente -> assinatura -> ver 1ª entrega -> marcar
  entregue -> registrar defeito -> gerar cobrança -> registrar pagamento ->
  pausar com retorno previsto -> rodar rotina -> reativar -> criar conta de
  assinante, vincular na ficha do cliente -> pedir pausa pelo app assinante ->
  responder no painel com "executar" -> cancelar -> conferir /historico ->
  editar /configuracoes e desfazer.
- Teste também em largura 375px e só com teclado em 3 telas.
- NÃO corrija nada ainda. Entregue a lista de falhas em
  docs/TESTE-PAINEL-<data>.md, ordenada por gravidade, com a correção
  sugerida para cada uma. Depois eu digo quais corrigir.
- No fim: pnpm db:limpar-teste no branch de teste e pare os servidores.
```

---

## BLOCO 2 — Regras de cobrança (D1–D15)

As regras já foram decididas (DECISOES.md, "Fechamento das regras de cobrança"). Falta implementar. A ordem abaixo reduz o risco financeiro primeiro. **Cada etapa = uma sessão, uma migration, um arquivo de teste SQL (`teste-fase11-*`), uma tela ajustada.**

| Etapa | Regra | Resumo |
|---|---|---|
| 2.1 | D10 (valor) | Fatura = entregas previstas no mês do calendário × valor da entrega. Nova `calculo_regra` |
| 2.2 | D8 | Ao assinar, gera a 1ª fatura (com 10%) e **não** cria entrega; a 1ª entrega nasce no `registrar_pagamento`, respeitando o corte |
| 2.3 | D1 + D2 | Fatura do mês do calendário, vence dia 3; 1ª vence no dia da assinatura; atrasada no dia 8; entregas param no dia 28 e voltam ao pagar; bloqueada não gera fatura |
| 2.4 | D7 | Cancelamento vale no fim do mês pago; entregas seguem até lá; sem cobrança nova |
| 2.5 | D3 + D4 + D5 | Pausa: crédito na próxima fatura (padrão) ou pentes depois, à escolha do cliente; fatura atrasada reduzida às entregas feitas; máximo 60 dias com aviso no painel |
| 2.6 | D6 | Aumento de plano na hora com fatura avulsa da diferença × R$ 41; redução no mês seguinte |
| 2.7 | D11 + D15 | Dúzia R$ 12 pedida pelo assinante e aprovada pelo dono; indicação 10% ao indicador; regra D15c de ordem dos descontos |

**Prompt da etapa 2.1** (os demais seguem o mesmo molde, trocando a regra):
```
[cabeçalho comum]

Tarefa: BLOCO 2, etapa 2.1 do docs/PLANO-GESTAO-20261013.md — regra D10
(valor da fatura pelo calendário), conforme DECISOES.md "Fechamento das
regras de cobrança" e "Etapa 2".

Hoje: as datas já seguem data_de_entrega_do_plano, mas calcular_valor_fatura
e gerar_cobranca ainda usam mensalidade fixa (calculo_regra =
'mensalidade-fixa-v1').

Quero:
1. Antes de codar, me mostre o plano: quais funções mudam, a nova
   calculo_regra (ex.: 'calendario-v1'), e 6 exemplos numéricos (semanal em
   mês com 4 e com 5 quartas, quinzenal, mensal, com e sem 10%, com dúzias).
   Espere meu ok.
2. Migration nova que troca só funções (não reescreve faturas existentes).
   O snapshot faturas.calculo_* continua fechando a conta pela constraint.
3. Fatura avulsa NÃO consome o desconto do 1º mês (conferir se já é assim).
4. tests/teste-fase11-1-fatura-calendario.sql cobrindo os 6 exemplos e os
   casos de borda (mês começando numa quarta, fevereiro, troca de ano).
5. Tela: em /assinaturas/[id] o texto do valor sugerido passa a explicar
   "N entregas × R$ X"; nada além disso.
6. Rode tudo no branch de teste e me mostre os resultados.
```

Para as etapas 2.2 a 2.7, use o mesmo prompt trocando o título, a regra (copie a linha da tabela D1–D15 do DECISOES.md) e o nome do teste. Na 2.5 e na 2.7 inclua também o app assinante (o cliente escolhe crédito ou pentes ao pedir a pausa; o cliente pede a dúzia). Antes da 2.4, responder a decisão C; antes da 2.7, conferir se a indicação já tem campos (`clientes.indicado_por` existe).

---

## BLOCO 3 — Ajustes técnicos do painel

Sem regra nova. Pode rodar em paralelo ao bloco 2, em outra branch, desde que não mexa nas mesmas funções SQL.

- **`comoAdmin` em página:** mover as chamadas de `assinaturas/[id]/page.tsx` e `clientes/[id]/page.tsx` para um helper de leitura que já exige o dono (ex.: `lerComoDono` em `lib/dono.ts`), para o item 4 de `verificar-segredos.sh` valer sem exceção.
- **Dividir `assinaturas/[id]/page.tsx`** (547 linhas) em componentes: situação, pedidos, entregas, reposições, cobrança, faturas, trocar plano.
- **Paginação** em clientes, assinaturas, entregas, faturas e histórico (cursor por data + id), mantendo os filtros na URL.
- **Performance:** juntar leitura de sessão + papel numa ida ao banco; medir com `next build && next start`; avaliar Neon em `sa-east-1`.
- **Rotina diária agendada de verdade:** cron externo chamando `POST /api/rotina` com `CRON_SECRET` (Vercel Cron ou similar), com registro da última execução visível no painel.

**Prompt:**
```
[cabeçalho comum]

Tarefa: BLOCO 3 do docs/PLANO-GESTAO-20261013.md. Nenhuma regra de negócio
muda; nenhuma função SQL muda.

1. Crie em apps/gestao/src/lib/dono.ts um helper de leitura administrativa
   que chama exigirDono() antes de comoAdmin, e use-o no lugar do comoAdmin
   direto em assinaturas/[id]/page.tsx e clientes/[id]/page.tsx. Confirme
   que scripts/verificar-segredos.sh continua passando.
2. Divida assinaturas/[id]/page.tsx em componentes de servidor na mesma
   pasta (_secoes/), sem mudar HTML nem comportamento.
3. Paginação por cursor (data + id) em /clientes, /assinaturas, /entregas,
   /faturas e /historico, 50 por página, filtros preservados na URL.
4. Meça o tempo de / e /assinaturas/[id] em build de produção, antes e
   depois de juntar sessão + papel numa ida só. Me mostre os números.
5. Proponha (sem configurar) como agendar POST /api/rotina uma vez por dia
   no host onde vamos publicar, e mostre no painel a data/hora da última
   execução da rotina (lendo da auditoria ou de uma tabela simples — me
   pergunte antes de criar tabela).
```

---

## BLOCO 4 — Segurança

- Aplicar `rateLimitServerAction` / `rateLimitServerActionPorUsuario` nas Server Actions do gestão (escritas) e do assinante (cadastro, assinar, pedidos).
- Better Auth com papel próprio no Postgres (só as tabelas `user`, `session`, `account`, `verification`), no lugar de `DATABASE_ADMIN_URL`.
- Limpeza periódica de sessões expiradas (pode entrar na rotina diária).
- CSP em modo de bloqueio (`modoRelatorio: false`) depois de conferir o console limpo nos 3 apps.

**Prompt:**
```
[cabeçalho comum]

Tarefa: BLOCO 4 do docs/PLANO-GESTAO-20261013.md. Leia docs/SEGURANCA.md,
docs/SERVER-ACTIONS-RATE-LIMIT.md e packages/database/src/auth/.

1. Liste todas as Server Actions de escrita de gestao e assinante e proponha
   limite por ação (por usuário no gestão, por IP + usuário no assinante).
   Espere meu ok e aplique o helper existente.
2. Crie uma migration com um papel app_auth que só lê/escreve as tabelas do
   Better Auth, e uma variável DATABASE_AUTH_URL. Better Auth passa a usá-la.
   Atualize .env.example (sem valores reais) e o teste de autorização para
   provar que app_auth não lê clientes, faturas etc.
3. Inclua na rotina diária a remoção de sessões expiradas (via função SQL
   com search_path fixo).
4. Abra os 3 apps com CSP em report-only, colete os avisos do console,
   corrija e só então troque para modoRelatorio: false. Me mostre o console
   limpo.
5. Atualize docs/SEGURANCA.md com o que mudou.
```

---

## BLOCO 5 — Visual do gestão

Segue o spec `docs/superpowers/specs/2026-10-07-visual-design-system-design.md` e o plano `docs/superpowers/plans/2026-10-07-visual-fundacao-e-componentes.md`. Para o gestão é preciso executar **Etapa 0 (tokens/fontes) → Etapa 1 (componentes em `packages/ui`) → Etapa 4 (telas do gestão)**. Fazer depois dos blocos 2 e 3, para não redesenhar telas que ainda vão mudar. **Responder a decisão A (fontes) antes.**

**Prompt (Etapas 0 e 1):**
```
[cabeçalho comum]

Tarefa: BLOCO 5 do docs/PLANO-GESTAO-20261013.md, Etapas 0 e 1. Execute o
plano docs/superpowers/plans/2026-10-07-visual-fundacao-e-componentes.md
tarefa por tarefa (Task 1 a Task 10), respeitando o spec de 07/10.
Fontes: <colar a decisão A>.
Só a camada visual muda: nenhum acoes.ts, função SQL, exigirDono, comoDono
ou FormAcao é alterado. Ao fim de cada Task, rode as verificações. No fim,
screenshots de /ui-kit em 1280 e 375 para eu aprovar.
```

**Prompt (Etapa 4 — telas do gestão):**
```
[cabeçalho comum]

Tarefa: BLOCO 5, Etapa 4 — aplicar a biblioteca de packages/ui nas telas de
apps/gestao: Sidebar + TopBar (BottomNav no celular), cards de resumo no
painel, DataTable nas listas (cartões no celular), formulários com Input/
Select/Button, Banner para avisos, EmptyState nas listas vazias, Dialog para
confirmar pausar/cancelar. Use as telas do Stitch (Interface Stitch/02_...)
só como referência de estrutura. Remova globals.css provisório. Uma tela por
vez, com screenshot antes/depois (1280 e 375) para eu aprovar antes da
próxima. Nada de lógica muda.
```

---

## BLOCO 6 — Pagamento Sicoob PIX e e-mail

Depende das credenciais (decisões G e H). Fazer no sandbox do Sicoob primeiro.

- Migration: cobranças no provedor (`txid`, QR/copia-e-cola, status, expiração) e tabela de eventos do webhook (idempotente por id do evento).
- Gerar cobrança Pix junto com a fatura; webhook com verificação de assinatura/mTLS; pagamento confirmado chama a mesma lógica de `registrar_pagamento` (e, com a D8, libera a 1ª entrega).
- Conciliação diária (consultar cobranças pendentes no provedor) na rotina.
- E-mail: confirmação de conta (liga o vínculo automático), aviso de fatura, aviso de entrega.

**Prompt:**
```
[cabeçalho comum]

Tarefa: BLOCO 6 do docs/PLANO-GESTAO-20261013.md — integração Pix do Sicoob
em SANDBOX. Antes de codar, pesquise a documentação oficial da API Pix do
Sicoob (autenticação, mTLS/certificado, criação de cobrança imediata e com
vencimento, webhook) e me mostre um desenho: tabelas novas, funções SQL,
rota do webhook, onde ficam os segredos (.env, nunca no código), e como a
confirmação reaproveita registrar_pagamento. Espere meu ok.
Regras extras: webhook idempotente (evento repetido não paga duas vezes),
nenhum valor vem do cliente, toda chamada externa com timeout e registro de
erro, testes SQL para a parte do banco e testes unitários para o parser do
webhook.
```

(E-mail pode ser uma sessão separada com o mesmo molde, depois da decisão H.)

---

## BLOCO 7 — Pré-lançamento

- Cadastrar as faixas de CEP reais pelo painel (decisão F).
- Banco de produção separado (branch `producao` no Neon ou projeto próprio), com backup automático e migrations aplicadas por script.
- Variáveis de produção (`BETTER_AUTH_URL`, `NEXT_PUBLIC_URL_ASSINANTE`, `CRON_SECRET`, Sicoob, e-mail).
- Deploy dos 3 apps, domínio, HTTPS, cron da rotina ligado.
- Runbook de incidente (já existe base em `docs/SEGURANCA.md`) e checklist de lançamento.

**Prompt:**
```
[cabeçalho comum]

Tarefa: BLOCO 7 do docs/PLANO-GESTAO-20261013.md. Monte comigo o checklist
de lançamento: ambiente de produção separado do de desenvolvimento no Neon,
backup, variáveis de produção (liste todas que os 3 apps leem), deploy,
domínio, cron da rotina, monitoramento de erro e runbook. Use a skill de
deploy-checklist. Não crie nada em produção sem eu confirmar item a item.
```

---

## 5. Acompanhamento

| Bloco / etapa | Situação | Data |
|---|---|---|
| 0 Base | a fazer | |
| 1 Teste no navegador | a fazer | |
| 2.1 D10 valor | a fazer | |
| 2.2 D8 1ª entrega após pagar | a fazer | |
| 2.3 D1 + D2 vencimento e atraso | a fazer | |
| 2.4 D7 cancelamento | a fazer | |
| 2.5 D3–D5 pausa | a fazer | |
| 2.6 D6 troca de plano | a fazer | |
| 2.7 D11 + D15 dúzia e indicação | a fazer | |
| 3 Ajustes técnicos | a fazer | |
| 4 Segurança | a fazer | |
| 5 Visual | a fazer | |
| 6 Sicoob + e-mail | a fazer | |
| 7 Pré-lançamento | a fazer | |
