# Decisões de negócio

Respostas do Fred e da Bruna às perguntas que o código não pode responder
sozinho. **Este arquivo é a fonte da verdade para elas.** Se um valor aqui
mudar, ele muda em `config_negocio` ou em `planos` — nunca escrito direto
num componente.

Última atualização: 28/09/2026.

---

## Respondidas

| # | Pergunta | Resposta | O que isso decide no código |
|---|---|---|---|
| 1 | Existe frete? | **Não existe frete separado — já está incluso no valor da assinatura** | `planos.frete_centavos = 0` nos três planos. O site não promete "frete grátis" só no semanal: ou é grátis em todos, ou a frase sai |
| 2 | O desconto de 10% na 1ª mensalidade vale para cartão ou só PIX? | **Para os dois** | `planos.desconto_primeiro_mes_pct = 10`, aplicado independentemente da forma de pagamento. O texto "PIX (10% OFF no 1º mês)" do checkout precisa ser corrigido |
| 3 | Ao voltar da pausa, o ciclo continua ou recomeça? | **Recomeça a partir de hoje** | `reativar()` gera calendário novo a partir da data do retorno, ancorado na próxima quarta. Não tenta recuperar as entregas perdidas na pausa |
| 4 | Como o PIX é conferido hoje? | **Comprovante enviado no WhatsApp, anotado numa planilha** | A conciliação começa **manual**: o admin marca a fatura como paga. A conciliação automática (Open Finance/OFX) é Fase 4, não Fase 2 |
| 5 | O que acontece quando a entrega falha (cliente ausente)? | **Reagenda** | O estado `falhou` existe e é um estado de passagem: ao marcar como falhou, o sistema propõe uma nova data. Não perde e não cobra a mais |
| 6 | Quem usa o sistema, e quantos papéis? | **Bruna e Fred como administradores; o resto é área do cliente** | O enum `papel_usuario` tem **dois valores: `dono` e `assinante`**. Não existe `entregador` |
| 7 | O cliente tem tela? | **Sim: calendário de entregas, pausar, cancelar, alterar endereço e perfil** | Confirma que a área do assinante existe, e com ela o risco mais grave do sistema: um assinante ver ou alterar dado de outro. É o que as 15 verificações da Fase 0 guardam |
| 8 | Quanto tempo de histórico guardar? | **Todo o histórico** | Nenhuma chave estrangeira de entrega ou fatura pode ser `on delete cascade`. Cancelar cliente **nunca** apaga histórico: `restrict` ou anonimização |
| 9 | Precisa funcionar sem internet na hora da entrega? | **Não** | A agenda de entregas nasce online-only. Nada de sincronização offline, que é caro e ninguém pediu |
| 10 | Existe alguém lançando dados na granja? | **A granja já tem um app próprio, que não será conectado por enquanto** | `apps/producao` saiu do monorepo e o papel `producao` saiu do enum. **A Fase 3 inteira sai do plano.** Se um dia a integração acontecer, ela entra como importação de dados, não como app novo |
| 11 | Qual é o prazo real de frescor, por plano? | **7 dias, no máximo, em todos os planos** | `planos.freshness_max_dias = 7` nos três. A promessa do site está certa; quem está errada é a calculadora, que mostra "Max 25 dias" no mensal |
| 12 | Assinatura em dúzias ainda é produto? | **Não como plano. A dúzia só existe como item que acompanha o pente** (ex.: 1 pente + 1 dúzia por entrega) | Não existe plano em dúzias. `entregas.quantidade_duzias` continua existindo como item avulso da entrega, com preço próprio congelado. `clientes.duzias_padrao` guarda o padrão de quem sempre pede a dúzia junto |
| 13 | Quinzenal e mensal: 15/30 dias ou 2/4 quartas? | **Em dias: 15 e 30** — *substituída em 30/09/2026 pela D10: quartas fixas do calendário (ver "Fechamento das regras de cobrança")* | `planos.intervalo_dias` = 7, 15, 30. **Ver a consequência registrada abaixo** |
| 14 | Reposição de ovo com defeito vira registro? | **Sim, vinculada à próxima entrega** | A reposição é um registro próprio que aponta para a entrega em que o defeito apareceu **e** para a entrega em que será reposta. Vai sem custo: não entra no subtotal da fatura |
| 15 | Frete: grátis em todos ou cobrado? | **Grátis para os bairros da região centro-sul.** Não existe frete cobrado separado | Confirma o nº 1: `planos.frete_centavos = 0` nos três planos. No site, "frete grátis" vale para a área atendida e o texto é derivado de `freightCents` |
| 16 | Brinde no 3º mês e atendimento prioritário existem de fato? | **Não** | Nenhuma tela, plano ou tabela comparativa pode prometer brinde ou atendimento prioritário. Foram removidos do site |
| 17 | Os preços "de" (R$ 91 / R$ 182 / R$ 46) foram praticados? | **Não. Os preços praticados são R$ 41 (mensal), R$ 82 (quinzenal) e R$ 164 (semanal)** | Não existe preço "de/por": `originalPrice` saiu do tipo `Plan`. `priceCents` = 4100, 8200 e 16400 |
| 18 | Qual é o dourado da marca: #e67e22 (site) ou #d4a437 (app)? | **Os dois** | `--cor-ouro: #e67e22` é o de ação (botões, links, foco); `--cor-ouro-app: #d4a437` é o de destaque (badges, ícones). Ambos em `packages/ui/src/tokens.css` |

---

---

## Uma consequência que vale conhecer

**Intervalo em dias tira os planos da quarta-feira.**

15 e 30 não são múltiplos de 7. Ancorando a primeira entrega numa quarta e
somando dias corridos, o dia da semana vai escorregando:

| Entrega | Semanal (7 dias) | Quinzenal (15 dias) | Mensal (30 dias) |
|---|---|---|---|
| 1ª | quarta | quarta | quarta |
| 2ª | quarta | **quinta** | **sexta** |
| 3ª | quarta | **sexta** | **domingo** |
| 4ª | quarta | **sábado** | **terça** |

Em um ano, o cliente mensal receberia em todos os dias da semana, inclusive
domingo. Isso conflita com "dia de entrega: quarta-feira", que é como o
negócio funciona hoje.

**Como o código ficou:** `planos.intervalo_dias` guarda 7, 15 e 30, como
pedido, e `planos.ancorar_em_quarta` decide se o calendário arredonda para a
quarta mais próxima. Hoje está ligado para os três planos — ou seja, na
prática quinzenal cai a cada 2 quartas e mensal a cada 4.

**Trocar é uma linha de UPDATE, sem migration.** Se o Fred quiser mesmo a
contagem em dias corridos, com entrega caindo em qualquer dia:

```sql
update planos set ancorar_em_quarta = false;
```

Só não dá para ter as duas coisas: ou o intervalo é exato, ou o dia é fixo.

## Ainda em aberto

| # | Pergunta | Por que trava |
|---|---|---|
| 1 | Quais são as duas fontes? | Três contratos tipográficos conflitantes. Hoje: Aclonica em `h1`/`h2`, Poppins no resto |


---

## Fase 8 — assinatura pelo site (29/09/2026)

**Implementado sem decisão nova de negócio:** cadastro, escolha de plano, validação de CEP contra as faixas e criação da assinatura pelo próprio cliente, usando as regras que já existiam (`criar_assinatura`: área, endereço, uma assinatura vigente, 1ª entrega na quarta).

**Dependem de decisão, credencial ou configuração — não foram inventadas:**

| Item | Situação |
|---|---|
| Pagamento online (InfinitePay ou Asaas) | Nenhuma integração existe no código, só variáveis comentadas. Enquanto isso o pagamento segue manual (PIX + comprovante). Nenhuma fatura é criada pelo site. |
| A entrega pode acontecer antes do 1º pagamento? | Hoje a assinatura nasce `ativa` com a 1ª entrega agendada, como no painel do dono. Se a regra for "só entrega após pagar", é preciso definir o estado da assinatura. |
| Serviço de e-mail | Não configurado. Adaptador pronto (`RESEND_API_KEY` + `EMAIL_REMETENTE`); o provedor não foi escolhido. Sem ele o e-mail da conta não é confirmado, e alguém pode criar conta com e-mail alheio (não vê dado nenhum, mas ocupa aquele e-mail no cadastro). |
| Faixas de CEP | Tabela vazia: hoje todo CEP é "fora da área" e ninguém consegue assinar. O dono cadastra em `/area-de-entrega`. |
| Cliente que estava fora da área e depois passou a ser atendido | Reavaliado ao assinar; não há aviso automático. |
| `entregas_por_mes` 4/2/1, preço da dúzia, pentes por entrega | Continuam pendentes (ver PROGRESSO.md §4). O preço da vitrine usa 1 pente por entrega. |
| Origem do lead | Cadastro pelo site grava `organico`. |
| Telefone do WhatsApp | **Resolvido pela D12** (30/09/2026): (31) 2516-7561. Implementado na Etapa 1: uma fonte só, `packages/config/src/whatsapp.mjs`. |


---

## Fase 9 — operação (30/09/2026)

**Regras informadas pelo dono e implementadas:** pente = 30 ovos; entrega = R$ 41 (`config_negocio.preco_pente_centavos`); semanal R$ 164/mês (4 entregas), quinzenal R$ 82 (2), mensal R$ 41 (1) — confirma `entregas_por_mes` 4/2/1; 10% na 1ª fatura; PIX = cobrança mensal manual; cartão = recorrência; sem fidelidade (cancelar a qualquer momento); sem carência; pausa controlada (retorno previsto, reativação automática pela rotina diária); alterações importantes na auditoria.

**Como ficou no código:**
- Cada assinatura tem `forma_cobranca` (pix | cartao) e `proxima_cobranca`. `gerar_cobranca()` cria a fatura do período de 1 mês, com vencimento no início do período, e avança a data. A rotina diária (`processar_rotina_diaria`, botão no painel ou `POST /api/rotina` com `CRON_SECRET`) gera os períodos vencidos, reativa pausas cujo retorno chegou e marca faturas atrasadas.
- Pausa cancela entregas e faturas **pendentes**, para a cobrança e suspende o cliente. Ao voltar, a cobrança recomeça no dia seguinte ao fim do último período já cobrado (nunca cobra o mesmo dia duas vezes).
- Defeito: `reposicoes`, sem custo, ligada à próxima entrega pendente; segue a entrega reagendada; vira "reposta" quando essa entrega é marcada como entregue.
- Horário de entrega: opcional, por entrega.

**Não existe integração com operadora de cartão ou banco.** "Cartão (recorrência)" registra a forma combinada e gera a fatura mensal; o pagamento é confirmado à mão pelo dono.

**Ainda em aberto (não inventado):**

| Item | Situação |
|---|---|
| Vencimento da cobrança | **Decidido em 30/09/2026** — ver "Fechamento das regras de cobrança" (D1). |
| Crédito por dias de pausa dentro de um período já pago | **Decidido em 30/09/2026** — ver "Fechamento das regras de cobrança" (D3). |
| Frete no valor da fatura | `planos.frete_centavos` aparece no site, mas `calcular_valor_fatura` não soma frete. O frete do Mensal ficou em R$ 1,00 depois de um teste em 30/09 e contradizia "frete grátis" (site/FAQ); voltou a R$ 0,00 na auditoria de estabilidade do mesmo dia. Frete continua sendo exibido e não cobrado. |
| Preço da dúzia | **Decidido em 30/09/2026**: R$ 12,00 — ver "Fechamento das regras de cobrança" (D11). |
| Integração de pagamento e e-mail | Dependem de provedor e credenciais. |


---

## Fechamento das regras de cobrança (30/09/2026)

Respostas do Fred e da Bruna às decisões D1–D15 de
`docs/REGRAS-DE-NEGOCIO-20260930.md`. **Ainda não implementadas**: o código
continua com as regras anteriores até cada item ser feito e testado. A
coluna "Hoje" diz o que muda.

| # | Tema | Regra decidida | Hoje (antes de implementar) |
|---|---|---|---|
| D1 | Vencimento | A fatura cobre o **mês do calendário**, paga adiantada, e vence no **dia 3**. Vira **atrasada no dia 8** (5 dias de tolerância). A **1ª fatura vence no dia da assinatura** e cobre as entregas desde a 1ª entrega até o fim do mês dela; da 2ª em diante, sempre dia 3 | Período de 1 mês a partir da assinatura; vence no início do período; atrasada no dia seguinte |
| D2 | Inadimplência | As entregas **param 20 dias depois do fim da tolerância** (dia 28, para a fatura do dia 3) e voltam quando o pagamento é registrado. Assinatura bloqueada não gera fatura nova | Nenhuma consequência |
| D3 | Pausa em mês pago | As entregas pagas e não feitas viram **crédito na próxima fatura** (padrão), ou, se o cliente preferir, ele **recebe os pentes depois**. O cliente escolhe ao pedir a pausa na área do assinante; o dono continua aprovando o pedido. Crédito = entregas pagas e não feitas × valor da entrega (pentes + dúzias) | Dias perdidos |
| D4 | Pausa com fatura atrasada | A fatura é **reduzida às entregas feitas** | Fatura continua cheia |
| D5 | Duração da pausa | Máximo de **60 dias**. Passou disso, o **dono é avisado** no painel e decide | Sem limite |
| D6 | Troca de plano | **Aumento vale na hora**: fatura avulsa, com vencimento no dia, de (entregas do plano novo − entregas do plano antigo até o fim do mês) × R$ 41; o novo ritmo começa na 1ª quarta depois do corte. **Redução vale no mês seguinte** | Vale na hora, sem diferença |
| D7 | Cancelamento | Vale no **fim do mês pago**; as entregas continuam até lá e não se gera cobrança nova | Imediato |
| D8 | 1ª entrega | **Só depois do 1º pagamento.** Ao assinar, a 1ª fatura (com os 10%) é gerada na hora; a 1ª entrega é criada quando o pagamento é registrado | Entrega antes de pagar |
| D9 | Corte | Vale o corte de `config_negocio` (segunda 18h): depois dele, a entrega vai para a quarta seguinte. Vale para 1ª entrega, retorno de pausa e troca de plano | Sem corte |
| D10 | O que a fatura cobra | **Entregas previstas no mês × valor da entrega.** Entregas presas ao calendário: **semanal = toda quarta** (4 ou 5 por mês), **quinzenal = 1ª e 3ª quarta do mês** (sempre 2), **mensal = 1ª quarta do mês** (sempre 1). Substitui a contagem em dias (7/15/30) da decisão #13. O site deixa de mostrar preço mensal fixo (ex.: "R$ 41 por entrega · cerca de R$ 164/mês no semanal") | Valor fixo por mês; entregas a cada 7/14/28 dias |
| D11 | Dúzia | **R$ 12,00.** Só para quem já recebe pente; **não aparece no site público**. O **assinante pede** na área dele e o **dono aprova**; vale a partir da próxima entrega depois do corte | R$ 12,00; só o dono cadastra; fatura usa o padrão do cliente |
| D12 | WhatsApp | **(31) 2516-7561** (link `wa.me/553125167561`; o número tem WhatsApp Business, confirmado). Um lugar só no código | Texto e link com números diferentes, em 5 arquivos |
| D13 | Selo do semanal | **"Recomendado"** no lugar de "Mais escolhido" | "Mais escolhido" |
| D14 | Tabela comparativa | **Mantida como está** | — |
| D15 | Indicação | O **indicado** recebe os 10% do 1º mês, os mesmos de todo novo assinante (**não** 20%). O **indicador** ganha **10% na fatura do mês** em que uma pessoa indicada por ele fez uma nova assinatura (paga a 1ª fatura); duas indicações no mesmo mês continuam 10% | Campos existem, nenhuma regra |

**Ordem dos descontos na mesma fatura (D15c):** uma fatura recebe **ou** um
desconto percentual (10% do 1º mês ou 10% de indicação, nunca os dois) **ou**
crédito em reais. Se os dois existirem no mesmo mês, aplica-se os 10% e o
crédito passa para a fatura do mês seguinte.

**Interpretação a confirmar:** na D3, "ele recebe os pentes referentes ao
crédito" foi lido como a resposta para **quem cancela com crédito sobrando**:
o crédito não vira dinheiro; o cliente recebe os pentes correspondentes antes
de encerrar.


---

## Etapa 1 — estrutura sem mudança de regra (30/09/2026)

Implementadas **só as bases** para as próximas etapas; nenhuma regra de D1–D15
mudou de comportamento. Migrations `1758758418`, `…419` e `…420`.

| Item | O que existe agora | O que NÃO faz ainda |
|---|---|---|
| Snapshot da fatura | Colunas `faturas.calculo_*` gravadas no INSERT por `inserir_fatura_com_snapshot` (plano, preços, entregas, pentes/dúzias, bruto, desconto, crédito, ajuste manual, `calculo_regra = 'mensalidade-fixa-v1'`). A conta fecha por constraint: bruto − desconto − crédito + ajuste = valor. | Créditos (D3/D15c) entram como 0; a fórmula é a de antes (D10 é etapa própria). |
| Pausas | Tabela `pausas_assinatura` (uma linha por pausa, nunca apagada, no máximo 1 ativa, sem sobreposição). Um gatilho espelha `pausar/reativar` nela; as colunas antigas de `assinaturas` continuam em uso. | Crédito, extensão, redução de fatura, limite de 60 dias, aviso (D3–D5). Decidir depois se `assinaturas.pausada_em`/`data_retorno_prevista` saem. |
| WhatsApp (D12) | `packages/config/src/whatsapp.mjs` é a única fonte; texto e link derivam do E.164. `apps/assinante/tests/whatsapp.test.ts` reprova número escrito em outro lugar. | — |
| Selo (D13) | `planos.selo` (texto, nulo = sem selo), devolvido por `planos_publicos()`, editável em `/configuracoes`. Semanal = "Recomendado". Destaque do cartão no site segue o selo. | — |

**Faturas anteriores à Etapa 1 ficam sem snapshot** (`calculo_regra` nula): o
banco não guardava plano nem preço da época e reconstruir a partir do estado
atual seria inventar (uma das faturas pagas tem valor de plano semanal numa
assinatura hoje quinzenal).


---

## Etapa 2 — calendário nas quartas (D10) e corte (D9) (30/09/2026)

Migration `1758758421000_etapa2-calendario-e-corte.sql`. **Aplicada primeiro no branch
de teste do Neon e, após confirmação, também no principal (30/09/2026)**
(`pnpm db:migrar`). Ela só troca funções: nenhuma entrega, assinatura ou fatura
existente é reescrita.

- **D10:** `data_de_entrega_do_plano` define o calendário (semanal = toda quarta;
  quinzenal = 1ª e 3ª quarta; mensal = 1ª quarta; a 5ª quarta só vale para o
  semanal). `data_proxima_entrega` passou a devolver a próxima data desse
  calendário, estritamente depois da base; `planos.intervalo_dias` e
  `ancorar_em_quarta` não comandam mais as datas (as colunas permanecem).
- **D9:** `primeira_quarta_apos_corte(instante)` lê `dia_corte`/`hora_corte` de
  `config_negocio`, em `America/Sao_Paulo`. "Depois do corte" é **estritamente
  depois**: segunda 18:00:00 ainda vale; 18:00:01 vai para a quarta seguinte.
- **1ª entrega** = primeira data do calendário do plano na primeira quarta que o
  corte permite. **Interpretação confirmada (30/09/2026):** para quinzenal e mensal, se a
  quarta liberada pelo corte não é dia do plano, a 1ª entrega vai para a
  próxima data do calendário do plano.
- **Instante injetável:** `criar_assinatura(cliente, plano, inicio, agora)`,
  `reativar_assinatura(assinatura, retorno, motivo, agora)` e
  `data_primeira_entrega(inicio, plano, agora)`. Sem `agora`: `now()` (ou, se o
  início foi dado no passado, aquele dia às 00:00 de São Paulo). Hoje o instante é o
  da assinatura; **a D8 (etapa posterior) deve passar o instante do pagamento.**
- **Não implementado (etapas seguintes):** D8 (1ª entrega só após o pagamento),
  D1/D2, D3–D7, D11, D15; recalcular datas das assinaturas atuais; fatura pelo
  novo calendário.


---

## Bloco 3 — conteúdo público do site vindo do banco (05/10/2026)

Migration `1758758424000_bloco3-conteudo-publico.sql`. **Aplicada só no banco de teste local; ainda não no Neon (principal nem teste).**

| Item | O que existe agora |
|---|---|
| Preço por entrega (D10) | `planos_publicos()` devolve `entregas_por_mes` e `preco_entrega_centavos`; `/api/plans` expõe `deliveriesPerMonth` e `deliveryPriceCents`. O card mostra "R$ 41 por entrega" e "4 entregas por mês · cerca de R$ 164/mês" (só o semanal leva "cerca de": o mês tem 4 ou 5 quartas). **A fatura ainda cobra o valor fixo da regra anterior** (D10 na cobrança é etapa própria). |
| Conteúdo do site | `GET /api/site` (cache de 30 s): frescor, frete grátis em todos?, desconto do 1º mês e corte, derivados de `site_conteudo()`; mais o FAQ. Se o banco não confirma, o site não afirma (a faixa de confiança omite a promessa). |
| FAQ | Tabela `faq_itens` (RLS: anon lê só as ativas; escrita só pelo dono; auditada). Tela `/faq` no gestão. O telefone do WhatsApp **não** entra aqui: a pergunta de contato é fixa e usa `packages/config/src/whatsapp.mjs` (D12). |
| Limite de acesso | `limitar_acesso_publico(ip, rota)` (definer, rotas e limites fixos): `/api/area` aceita 30 consultas/min por IP e responde 429 depois. `/api/plans`, `/api/neighborhoods` e `/api/site` não têm limite próprio porque são cacheadas (30 s). Vale a ressalva: o IP vem de `x-forwarded-for`, só confiável atrás de proxy que o reescreva. Se o contador falhar, a rota libera (fail-open). |
| Correções da Fase 10 achadas no caminho | `rateLimit` estava **sem RLS** (reprovava a Lei 1 no `pnpm seguranca`) e `verificar_rate_limit` estava concedida a `app_usuario` sem funcionar (security invoker, sem privilégio na tabela). Ligou-se a RLS (sem policy) e revogou-se o grant. |

**Não feito (de propósito):** depoimentos — não existem depoimentos reais e a tabela ficaria vazia; entra quando houver conteúdo. Textos do Hero, pilares e comparativo continuam no código (viram busca no servidor no Bloco 7).


---

## Bloco 4 — fluxo de assinatura com a cara do site (05/10/2026)

Migration `1758758425000_bloco4-funil-de-conversao.sql`. **Aplicada só no banco de teste local; ainda não no Neon.**

| Item | O que existe agora |
|---|---|
| Telas | `/assinar`, `/cadastro` e `/entrar` ganham topo com a marca, "Voltar ao site" (`NEXT_PUBLIC_URL_SITE`) e indicador de etapas (Plano → Conta → Endereço → Confirmação). O resumo do plano mostra preço por entrega e entregas por mês (D10); a data de entrega diz "sempre às quartas". |
| Pós-assinatura | `/?nova=1` mostra a data da 1ª entrega, como pagar (PIX com comprovante no WhatsApp) e o botão do WhatsApp. |
| Funil | `eventos_funil` + `registrar_evento_funil(etapa, plano)`: só etapa, plano público e instante (sem IP, e-mail ou sessão). Etapas: plano clicado (site, `sendBeacon`), conta criada (cadastro), endereço salvo e assinatura confirmada (nas actions, **na mesma transação** do fato). `POST /api/evento` com limite de 60/min por IP. O dono lê a contagem dos últimos 30 dias no painel inicial. Como não há identificador, o funil **não** liga etapas da mesma pessoa. |
| Contraste (correção de B1/B2) | Texto branco sobre `--cor-ouro` dava 2,85:1. `--cor-sobre-ouro` agora é o texto escuro (5,3:1); `--cor-ouro-escuro` passou de `#b85f12` para `#a15200` (≥ 4,7:1 nos fundos claros); `--cor-whatsapp` de `#1a9e4b` para `#157f3c` (5,1:1 com texto branco). Novo `--cor-sobre-escuro` para texto sobre verde/WhatsApp. Vale para os três apps. |
| E2E | `scripts/e2e/assinatura.mjs` (Playwright): site → plano → conta → endereço → confirmação → contagem do funil. Roda só contra banco de teste; precisa de uma faixa de CEP ativa. |

**Pendente:** "fora da área → deixar contato" (Bloco 5); e-mail de confirmação de conta e fatura gerada ao assinar (Bloco 6, D8); o E2E ainda não roda no CI.


---

## Bloco 5 — interessados fora da área (05/10/2026)

Migration `1758758426000_bloco5-interessados.sql`. **Aplicada só no banco de teste local; ainda não no Neon.**

| Item | O que existe agora |
|---|---|
| Captação | CEP fora da área no site (e na tela "Ainda não entregamos aí" do `/assinar`) abre o formulário "Avise-me": telefone **ou** e-mail (nome opcional) + caixa de consentimento nunca pré-marcada. `POST /api/interesse` → `registrar_interesse()` (valida, normaliza, exige consentimento). |
| Consentimento | Texto e versão em `packages/config/src/privacidade.mjs` (v1). O banco grava a versão aceita; **quem decide a versão é o servidor**, não o navegador. **O texto precisa de revisão jurídica antes de ir ao ar** (não sou advogado e não validei LGPD). |
| Abuso | Campo-isca (robô recebe 204 sem gravar), limite de 5 pedidos/min por IP, pedido repetido não duplica e a resposta é a mesma de um sucesso (não revela quem já está na lista), CEP já atendido também responde igual. |
| Painel | `/interessados`: "prontos para avisar" (a faixa nova passou a cobrir o CEP, marcado por gatilho), aguardando, todos; link de conversa por WhatsApp, marcar avisado, descartar, **remover de vez** (com confirmação) e exportar CSV (só o dono; células neutralizadas contra injeção de fórmula). Contador no painel inicial. |
| Privacidade | **Sem auditoria** nesta tabela, de propósito: a auditoria é imutável e copiaria telefone e e-mail para onde não dá apagar. Remover apaga de verdade. Quem mudou a situação não fica registrado. |

**Não feito:** aviso automático (precisa de serviço de e-mail ou WhatsApp API — hoje o dono avisa à mão, pelo link); prazo de retenção (os dados ficam até o dono avisar, descartar ou remover; defina um prazo e eu automatizo a limpeza).


---

## Bloco 6 · rodada 1 — D8: 1ª entrega só depois do pagamento + confirmação automática (05/10/2026)

Migration `1758758427000_bloco6-d8-pagamento-antes-da-entrega.sql`. **Aplicada só no banco de teste local; ainda não no Neon.** Depois de migrar, rode `criar-papel-servidor.mjs` de novo para conceder `app_pagamentos` ao `app_servidor`.

| Item | Como ficou |
|---|---|
| Chave | `config_negocio.exigir_pagamento_antes_da_1a_entrega`, **desligada** por padrão (editável em `/configuracoes`). Desligada = comportamento de sempre. Ligada vale só para assinaturas **novas** (as existentes não são tocadas). |
| Assinatura nova (ligada) | Nasce `ativa` com `aguardando_pagamento_desde` preenchido, **sem entrega**, e a 1ª fatura já gerada (10% do 1º mês, vence no dia). Vale também para assinatura criada pelo dono no painel. Pausar, trocar de plano e agendar entrega à mão ficam recusados enquanto aguarda. |
| Liberação | Pagar a fatura do 1º período (manual ou automático) chama `liberar_primeira_entrega`: cria a entrega na 1ª data do calendário do plano após o corte (D9). **O instante do corte é o da confirmação do pagamento** (`now()`), nunca uma data digitada. |
| Prazo | `dias_para_pagar_1a_fatura` (padrão 7): a rotina diária cancela a assinatura e a 1ª fatura; o cliente volta a "cadastro em andamento" e pode assinar de novo. A rotina não gera fatura nova para quem aguarda. |
| Confirmação online | Papel `app_pagamentos` (só executa `confirmar_pagamento_online`; sem `comoAdmin`). Idempotente por `(provedor, transacao)`; valor **menor** que o da fatura → `divergente` (não baixa); pagamento para fatura já paga/cancelada → `sem_efeito` (dono avalia estorno). Valor maior confirma e guarda o valor real. O painel do dono lista os dois casos. |
| Webhook | `POST /api/pagamento/webhook`. **O corpo do aviso nunca é prova**: o servidor consulta o provedor e só então chama o banco. Limite de 120/min por IP; 404 se o pagamento online está desligado. |
| Provedores | `PAGAMENTO_PROVEDOR=nenhum` (padrão, pagamento manual) · `simulado` (só dev; recusado em produção) · `infinitepay`. |

### ⚠️ InfinitePay: contrato A CONFIRMAR

O adaptador (`apps/assinante/src/lib/pagamento/infinitepay.ts`) foi escrito **sem acesso à documentação oficial** (domínio bloqueado no ambiente de desenvolvimento). Os nomes `order_nsu`, `handle`, `webhook_url`, `transaction_nsu`, `slug` e o endereço de `payment_check` vêm de fontes secundárias; o endereço de criação de link, os campos de item/valor e a **unidade do valor** (centavos?) são suposições, marcados com «A CONFIRMAR» no código. Por isso ele **só liga com `INFINITEPAY_CONTRATO_CONFIRMADO=sim`**. Antes de ligar: conferir cada ponto em infinitepay.io/checkout-documentacao, informar `INFINITEPAY_HANDLE` e uma `URL_PUBLICA_ASSINANTE` https alcançável pela InfinitePay. Se a unidade do valor estiver errada, o efeito é "divergente" (nenhuma fatura é baixada a menos): falha para o lado seguro. Cartão em **recorrência** não consta como suportado pelo checkout: "cartão" segue gerando uma fatura mensal com link avulso.

### Fora desta rodada
D1/D2/D10 (ciclo por mês de calendário e inadimplência), D3–D7 (pausa com crédito, troca de plano, cancelamento no fim do mês), D11 (dúzia pedida pelo assinante) e D15 (indicação). Com a chave ligada, o texto do FAQ "como funciona o pagamento" fica desatualizado: ajuste em `/faq`.
