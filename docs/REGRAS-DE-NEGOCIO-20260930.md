# Fechamento das regras de negócio — Ovo di Onça (30/09/2026)

Análise feita só com leitura: nenhum código, migration ou dado foi alterado. Fontes: migrations `fase2` a `fase9-area-recalcula-no-banco`, `apps/gestao`, `apps/site`, `apps/assinante`, `DECISOES.md`, `PROGRESSO.md` e uma consulta `begin read only` ao banco.

Estado do banco no momento da leitura: 2 clientes, 2 assinaturas ativas, 3 faturas pagas, 1 faixa de CEP. `preco_pente_centavos = 4100`, **`preco_duzia_centavos = 1200`**, planos 7/15/30 dias com `entregas_por_mes` 4/2/1, frete 0 e 10% no 1º mês, os três com `ancorar_em_quarta = true`.

---

## 1. REGRAS ATUAIS (o que o código faz hoje)

### 1.1 Cobrança

| Tema | Comportamento atual | Onde |
|---|---|---|
| Período | 1 mês corrido a partir de `assinaturas.proxima_cobranca` (`periodo_fim = inicio + 1 mês − 1 dia`). A 1ª cobrança começa em `data_inicio`, o dia em que a assinatura foi criada | `gerar_cobranca`, gatilho `assinaturas_ciclo` |
| Valor | `(pentes_padrao × preço do pente + duzias_padrao × preço da dúzia) × entregas_por_mes`. Calculado **na hora de gerar** a fatura, com os valores daquele momento | `calcular_valor_fatura` |
| Desconto 1º mês | 10% na **primeira fatura não cancelada do cliente** (não da assinatura), se `desconto_primeiro_mes_aplicavel` | `calcular_valor_fatura` |
| Vencimento | **Igual ao início do período** (cobrança antecipada, sem tolerância) | `gerar_cobranca` |
| Geração | Rotina diária (`processar_rotina_diaria`) ou botão "Gerar cobrança". A rotina recupera até 12 períodos atrasados por assinatura por execução | fase9 |
| Atraso | `pendente` com vencimento < hoje vira `atrasada` quando a rotina roda. Como o vencimento é o 1º dia, **a fatura fica atrasada no dia seguinte ao que foi gerada** | `marcar_faturas_atrasadas` |
| Consequência do atraso | **Nenhuma.** A entrega continua, a próxima fatura continua sendo gerada, o cliente continua `ativo` | — |
| Pagamento | Manual: dono registra data + método (`pix`, `cartao`, `dinheiro`, `transferencia`, `outro`). A 1ª fatura paga muda o cliente de `cadastro_andamento` para `ativo` | `registrar_pagamento` |
| Fatura paga | Não pode ser cancelada nem estornada | `cancelar_fatura` |
| Forma de cobrança | `pix` ou `cartao` na assinatura; só muda o texto da observação. Não há integração | `definir_forma_cobranca` |
| O que a fatura guarda | valor, vencimento, período, status, método, observação. **Não guarda** plano, preço unitário, pentes, dúzias nem quantidade de entregas | tabela `faturas` |

### 1.2 Entregas × cobrança

- A agenda de entregas **não está ligada** às faturas. Uma entrega só se relaciona a um período pela data.
- Com `ancorar_em_quarta = true`, a data calculada é arredondada para a quarta mais próxima:
  - semanal: a cada 7 dias → **52 entregas/ano**, cobradas como 48 (4 × 12);
  - quinzenal: 15 dias vira **14** → **26 entregas/ano**, cobradas como 24;
  - mensal: 30 dias vira **28** → **13 entregas/ano**, cobradas como 12.
  
  Ou seja: hoje o cliente recebe ~8% de entregas a mais do que paga. Nos meses com 5 quartas, o semanal recebe 5 e paga 4. **Isso nunca foi decidido; é consequência da combinação "mensalidade fixa + agenda por quarta".**
- A 1ª entrega é `proxima_quarta(data_inicio)`, que **inclui o próprio dia**: quem assina numa quarta às 17h tem entrega marcada para a mesma quarta.
- `config_negocio.dia_corte` / `hora_corte` (segunda 18h) existem, são editáveis em `/configuracoes`, mas **nenhuma função os usa**.

### 1.3 Pausa

- `pausar_assinatura`: status → `pausada`, grava `pausada_em` e `data_retorno_prevista` (opcional), cancela entregas **pendentes** e faturas **pendentes**, cliente → `suspenso`, `proxima_cobranca` → nula.
- Faturas `atrasadas` continuam devidas **integralmente**, mesmo com as entregas do período canceladas.
- Faturas `pagas` não geram crédito: os dias pagos e não entregues **se perdem**.
- Retorno (manual ou pela rotina na data prevista): calendário recomeça na próxima quarta ≥ retorno (DECISOES #3); a cobrança recomeça em `max(retorno, fim do último período cobrado + 1)` — nunca cobra o mesmo dia duas vezes.
- Ao reativar, o gatilho **apaga `pausada_em` e `data_retorno_prevista`**. O histórico da pausa só fica na `auditoria` (JSON), não numa tabela consultável.
- Não há limite de duração da pausa.

### 1.4 Troca de plano

- `alterar_plano_assinatura` só troca `plano_id` (e `clientes.plano_id`). Vale **imediatamente**, inclusive com a assinatura pausada.
- A entrega pendente **fica na data antiga**; o novo intervalo só vale a partir da entrega seguinte.
- A fatura do período corrente **não muda**; a próxima fatura gerada usa o novo `entregas_por_mes`.
- Não existe prorrata, crédito nem cobrança da diferença.
- Histórico: auditoria registra `plano_da_assinatura_alterado`. A fatura não diz de qual plano ela era.

### 1.5 Cancelamento

- Imediato: status → `cancelada`, cancela entregas e faturas **pendentes**, cliente → `cancelado`.
- Período já pago: o cliente perde as entregas restantes; não há estorno.
- Faturas atrasadas: continuam devidas.
- `assinaturas.data_fim` e o status `encerrada` existem e **não são usados** por nenhuma função.

### 1.6 Primeira entrega

- `criar_assinatura` / `assinar_plano` criam a assinatura **já `ativa`** e a 1ª entrega **já agendada**. Nenhuma fatura é criada nesse momento.
- A 1ª fatura só nasce quando a rotina roda ou o dono clica em "Gerar cobrança".
- `marcar_entrega` não confere pagamento. Nada impede entregar para quem nunca pagou.
- O cliente fica `cadastro_andamento` até a 1ª fatura paga; esse status **não bloqueia nada**.

### 1.7 Preço da dúzia

- **Armazenado em:** `config_negocio.preco_duzia_centavos` (linha única, id = 1). Valor atual: **1200 (R$ 12,00)**. A auditoria mostra três alterações em 30/09 entre 11:26 e 11:28 (0 → 1200 → 0 → 1200), pela tela `/configuracoes`.
- **Quem lê esse valor:** só `calcular_valor_fatura`, e portanto `gerar_cobranca`, `criar_fatura` sem valor informado e a rotina diária. Entra na conta só para clientes com `duzias_padrao > 0` — **hoje nenhum**, então nenhuma fatura foi afetada até agora.
- **Quem NÃO lê:** `planos_publicos()` (site e `/assinar` mostram só o pente), `entregas` (guardam a *quantidade* de dúzias, não o preço).
- **Divergências com o que foi decidido:** DECISOES #12 diz "item avulso da entrega, com preço próprio congelado". Não há preço congelado em lugar nenhum; a fatura multiplica `clientes.duzias_padrao` por `entregas_por_mes` e ignora `entregas.duzias`. Se o dono mudar a dúzia de uma entrega específica, a fatura não acompanha.

### 1.8 Telefone do WhatsApp

Dois números diferentes em cinco lugares, fixos no código:

| Arquivo | Valor |
|---|---|
| `apps/site/src/components/Footer.tsx:3` (texto) | (31) 2516-7561 |
| `apps/site/src/components/Footer.tsx:4` (link) | 5531925167561 → (31) 92516-7561 |
| `apps/site/src/components/Navbar.tsx:3` (link) | 5531925167561 |
| `apps/site/src/components/FaqSection.tsx:30` (texto) | (31) 2516-7561 |
| `apps/assinante/src/lib/formatar.ts:7` (link) | 5531925167561 |

O texto mostra um número fixo de 8 dígitos; o link aponta para um celular de 9 dígitos. Um dos dois está errado.

### 1.9 Marketing

| Item | Situação |
|---|---|
| Selo "Mais escolhido" no semanal (`apps/site/src/hooks/usePlanos.ts:26`) | Fixo no código; não há dado que sustente |
| "Livre, ao ar aberto" × "Predominantemente em gaiolas" (`ComparisonTable.tsx`) | Afirmação sobre criação sem confirmação em DECISOES |
| "Semanas ou meses em estoque" (supermercado) | Afirmação comparativa sem fonte |
| "Direto na sua porta, dia fixo" | Verdadeiro enquanto `ancorar_em_quarta = true` |
| Programa de indicação: `clientes.indicado_por`, `origem_lead`, `config_negocio.bonus_indicador_pct`, `teto_credito_indicacao_pct` | Colunas existem e são editáveis; **nenhuma regra usa**. Não há crédito, bônus nem desconto por indicação |
| Frete grátis, 10% no 1º mês, 7 dias de frescor | Coerentes com DECISOES #1, #2, #11, #15 |

---

## 2. REGRAS INDEFINIDAS

1. **Vencimento** — início do período (atual) ou com tolerância? Dia fixo do mês?
2. **O que a mensalidade compra** — "um mês de entregas" (atual, com 5ª quarta e 13ª entrega de brinde) ou "N entregas"?
3. **Inadimplência** — depois de quantos dias de atraso as entregas param? A rotina deve continuar gerando faturas para quem não paga?
4. **Pausa dentro de um período pago** — perde (atual), estende, credita ou cobra proporcional?
5. **Pausa com fatura em atraso** — a dívida continua cheia (atual)?
6. **Duração máxima da pausa** — sem limite (atual)?
7. **Troca de plano** — imediata (atual) ou no próximo período? Com ou sem diferença?
8. **Cancelamento** — imediato (atual) ou no fim do período pago?
9. **Primeira entrega antes do primeiro pagamento** — permitida (atual)?
10. **Corte para a 1ª entrega** — `dia_corte`/`hora_corte` devem valer? Assinar na própria quarta entrega no mesmo dia?
11. **Preço da dúzia** — R$ 12,00 é o preço real? A dúzia aparece no site?
12. **Telefone oficial do WhatsApp.**
13. **Marketing** — selo "Mais escolhido", afirmações da tabela comparativa, programa de indicação.

---

## 3. IMPACTO TÉCNICO

### 3.1 O modelo consegue representar tudo sem ambiguidade?

**Não.** Seis lacunas:

| # | Lacuna | Consequência concreta |
|---|---|---|
| A | A fatura não guarda plano, preço unitário, pentes, dúzias nem nº de entregas | Depois de trocar plano ou preço, não dá para explicar ao cliente de onde saiu um valor antigo sem garimpar a auditoria |
| B | Entrega não se liga a período/fatura | "Essa entrega foi paga?" só se responde comparando datas, e a comparação quebra se o período for estendido por pausa |
| C | Pausa não tem tabela própria; `pausada_em` é apagado ao reativar | Impossível calcular crédito ou extensão depois da reativação; relatório de pausas depende de JSON da auditoria |
| D | Troca de plano não tem data de vigência | Não dá para agendar a troca para o próximo período nem saber qual plano valia em cada data |
| E | Cancelamento só existe como imediato | Não dá para "cancelar ao fim do período pago" sem deixar a assinatura num estado que as funções entendem |
| F | Nenhum estado para "aguardando 1º pagamento" ou "bloqueada por atraso" | Não dá para segurar entrega de quem não pagou sem usar `pausada`, que tem outro significado |

### 3.2 Cenários que hoje produzem resultado ruim

1. **Pausa no dia 8 de um mês pago, retorno no dia 15 do mês seguinte** — o cliente pagou 4 entregas, recebeu 1, perde 3, e volta a pagar no dia do retorno.
2. **Pausa com fatura atrasada** — a fatura do mês inteiro continua devida, mas as entregas daquele mês foram canceladas.
3. **Cliente que não paga** — recebe toda quarta; a rotina gera uma fatura nova por mês, indefinidamente.
4. **Assinatura na quarta às 17h** — entrega marcada para a mesma quarta.
5. **Mensal → Semanal no dia 2** — a entrega pendente continua daqui a 4 semanas; o semanal só começa depois dela, e só é cobrado no próximo período.
6. **Cancelamento no dia 3 de um mês pago** — o cliente perde as entregas restantes do mês sem estorno.
7. **Primeira fatura avulsa** — se o dono criar uma fatura avulsa sem valor antes da 1ª do período, ela consome os 10% de desconto.

### 3.3 Tabelas e funções afetadas por decisão

| Decisão | Tabelas | Funções |
|---|---|---|
| Vencimento | `config_negocio`, `faturas` | `gerar_cobranca`, `marcar_faturas_atrasadas` |
| O que a mensalidade compra | `planos`, `faturas` | `gerar_cobranca`, `calcular_valor_fatura`, `data_proxima_entrega` |
| Inadimplência | `config_negocio`, `assinaturas`, `entregas` | `processar_rotina_diaria`, `marcar_entrega`, `registrar_pagamento` |
| Pausa | `assinaturas`, nova `pausas` | `pausar_assinatura`, `reativar_assinatura`, `assinaturas_ciclo`, `inicio_proxima_cobranca` |
| Troca de plano | `assinaturas`, `faturas` | `alterar_plano_assinatura`, `gerar_cobranca` |
| Cancelamento | `assinaturas` | `cancelar_assinatura`, `gerar_cobranca`, `processar_rotina_diaria` |
| 1ª entrega | `assinaturas`, `entregas` | `criar_assinatura`, `data_primeira_entrega`, `registrar_pagamento` |
| Dúzia | `config_negocio`, `entregas`, `faturas` | `calcular_valor_fatura`, `planos_publicos` |
| WhatsApp | — (código) | 5 arquivos listados em 1.8 |

---

## 4. ANÁLISE DETALHADA

### 4.1 Pausa: quatro modelos

| Modelo | Como funciona | Dinheiro | Complexidade | Previsibilidade para o cliente |
|---|---|---|---|---|
| **Perda (atual)** | Pausa corta tudo; dias pagos não voltam | Nenhum cálculo | Nenhuma | Ruim: quem pausa no meio do mês sente que perdeu dinheiro |
| **Extensão do ciclo** | Os dias pausados dentro do período pago empurram a próxima cobrança. Ex.: pagou 01–31/10, pausou 08/10, voltou 15/11 → 24 dias devidos → próxima cobrança em 09/12 em vez de 15/11 | Nenhum valor novo; só datas | Média: precisa guardar as pausas | Boa: "o que você pagou, você recebe" |
| **Crédito financeiro** | Valor proporcional vira saldo e abate a próxima fatura | Saldo em centavos, arredondamento, crédito que sobra se o cliente cancelar | Alta: tabela de lançamentos, regra de estorno, crédito órfão | Boa, mas o cliente vê valores "quebrados" |
| **Cobrança proporcional** | A fatura do mês cobra só as entregas feitas | Valor variável todo mês de pausa | Alta: fatura depende do que ainda não aconteceu (pós-pago ou ajuste) | Média: PIX com valor diferente a cada mês |
| **Congelamento no limite do ciclo** | A pausa só começa no fim do período pago; até lá as entregas continuam | Nenhum cálculo | Baixa | Boa para quem planeja; ruim para quem viaja amanhã |

**Recomendação: extensão do ciclo, contada em dias.**
- Não mexe em valor, então não cria saldo, estorno nem centavos quebrados — compatível com PIX manual.
- Não conflita com DECISOES #3 (o *calendário* recomeça no retorno; o que se estende é a *cobrança*).
- Para fatura **atrasada** (não paga), a extensão também vale: a dívida continua cheia, mas o cliente recebe os dias quando voltar e pagar. Uma regra só, independente de pagamento.
- Precisa de um limite de pausa (sugestão: 60 dias, configurável). Passou disso sem retorno → decisão: cancela automaticamente ou vira pendência para o dono.

### 4.2 Troca de plano

Como todo plano custa R$ 41 por entrega, qualquer diferença pode ser medida **em entregas**, não em dias.

**Regra recomendada: a troca vale a partir do próximo período.**

| Troca | Período corrente | Próximo período | Entrega | Cobrança | Crédito |
|---|---|---|---|---|---|
| Mensal → Quinzenal | Continua mensal (1 entrega paga) | Quinzenal, R$ 82 | 1ª do novo plano na 1ª quarta ≥ início do novo período | Próxima fatura já com o valor novo | — |
| Mensal → Semanal | Continua mensal | Semanal, R$ 164 | idem | idem | — |
| Quinzenal → Semanal | Continua quinzenal | Semanal | idem | idem | — |
| Quinzenal → Mensal | Continua quinzenal (as 2 pagas) | Mensal, R$ 41 | idem | idem | — |
| Semanal → Mensal | Continua semanal (as 4 pagas) | Mensal | idem | idem | — |
| Semanal → Quinzenal | Continua semanal | Quinzenal | idem | idem | — |

- **Período vigente:** não muda; nenhum valor pago é recalculado.
- **Histórico:** a troca fica registrada com a data de pedido e a data de vigência; cada fatura passa a dizer de qual plano ela é.
- **Entrega:** ao virar o período, a entrega pendente é recalculada para o novo intervalo (hoje não é).
- **Variação opcional (decisão):** *upgrade imediato* (mais entregas) com fatura avulsa da diferença = `(entregas do novo plano até o fim do período − entregas do plano antigo até o fim do período) × R$ 41`. *Downgrade* sempre no próximo período (evita crédito). Recomendo deixar para depois: a regra simples já atende.

### 4.3 Primeira entrega antes do primeiro pagamento

| Aspecto | Entregar antes (atual) | Exigir pagamento antes |
|---|---|---|
| Cobrança | 1ª fatura pode nem existir quando a entrega sai | Fatura gerada **na assinatura**, com os 10%, e é ela que libera a entrega |
| Inadimplência | Risco de 1 entrega (R$ 41 no mensal) a várias (semanal, se nada parar a entrega) | Risco zero na 1ª entrega |
| Rotina | Nada muda | O dono vê "aguardando pagamento" na tela de assinaturas/entregas |
| Entrega | Sai na 1ª quarta, mesmo no próprio dia | Sai na 1ª quarta **depois do corte** que vier após o pagamento |
| Status da assinatura | `ativa` desde o início | Precisa de um estado novo (`aguardando_pagamento`) ou de uma entrega "não liberada" |
| Conversão | Mais fácil: assina e recebe | Um passo a mais (pagar), mas é o padrão de assinatura |

**Recomendação: exigir o 1º pagamento, usando o corte que já existe na configuração.** Assinou → fatura gerada na hora, com vencimento no dia → a entrega só é criada quando o pagamento é registrado, na 1ª quarta após o corte (segunda 18h). Isso resolve ao mesmo tempo o risco do 1º pagamento e o "entrega no mesmo dia". Se o dono preferir conversão a risco, a alternativa mínima é: manter a entrega antes do pagamento, mas **aplicar o corte** e **ligar a regra de inadimplência (4.4)**, que limita o prejuízo a uma entrega.

### 4.4 Vencimento e atraso

Recomendação:
- **Cobrança antecipada continua** (vencimento no início do período) — é o que a operação já faz e o que o PIX manual pede.
- **Tolerância configurável** (`config_negocio.dias_tolerancia`, sugestão 3 dias): a fatura só vira `atrasada` depois dela.
- **Bloqueio por atraso configurável** (`config_negocio.dias_bloqueio_atraso`, sugestão 7 dias após o vencimento): a rotina marca a assinatura como bloqueada e as entregas pendentes não saem até o pagamento. O pagamento desbloqueia e recria a próxima entrega.
- **Rotina não gera fatura nova** para assinatura bloqueada (hoje gera até 12 por execução).

### 4.5 Cancelamento

Recomendação: **cancelamento vale no fim do período pago.** O pedido grava `data_fim = periodo_fim` do último período pago; as entregas continuam até lá; não se gera cobrança depois; a rotina muda o status para `cancelada` quando a data chega. Usa as colunas `data_fim` e o fluxo de rotina que já existem. Se o período corrente não foi pago, o cancelamento é imediato e a fatura atrasada continua devida (como hoje).

### 4.6 O que a mensalidade compra

Duas opções coerentes:
- **Mensalidade fixa, agenda por quarta (atual):** simples e previsível para o cliente (R$ 164 todo mês); a Ovo di Onça absorve a 5ª quarta e a 13ª entrega. Custo aproximado: 4 entregas/ano no semanal, 2 no quinzenal, 1 no mensal por cliente.
- **Mensalidade por entregas do período:** a fatura conta as quartas do período × R$ 41. Justa, mas o valor muda de mês para mês (R$ 164 ou R$ 205 no semanal).

**Recomendação: manter a mensalidade fixa e registrar a decisão**, porque o site vende "R$ 164/mês" e o PIX manual fica mais simples com valor fixo. A decisão só precisa ser consciente.

---

## 5. DECISÕES QUE PRECISAM SER TOMADAS

Cada item tem uma recomendação; a decisão é do Fred e da Bruna.

| # | Decisão | Opções | Recomendação |
|---|---|---|---|
| D1 | Vencimento | a) início do período, sem tolerância (atual) · b) início + N dias de tolerância · c) dia fixo do mês | **b**, N = 3 |
| D2 | Consequência do atraso | a) nenhuma (atual) · b) bloquear entregas após N dias · c) cancelar após N dias | **b**, N = 7 |
| D3 | Pausa em período pago | a) perda (atual) · b) extensão do ciclo · c) crédito · d) proporcional · e) só no fim do período | **b** |
| D4 | Duração máxima da pausa | a) sem limite (atual) · b) N dias e depois cancela · c) N dias e avisa o dono | **c**, N = 60 |
| D5 | Troca de plano | a) imediata, sem diferença (atual) · b) no próximo período · c) upgrade imediato com diferença, downgrade no próximo | **b** |
| D6 | Cancelamento | a) imediato (atual) · b) no fim do período pago | **b** |
| D7 | 1ª entrega antes do pagamento | a) sim (atual) · b) não, só após pagar | **b** |
| D8 | Corte para a 1ª entrega | a) sem corte (atual) · b) usar `dia_corte`/`hora_corte` | **b** |
| D9 | O que a mensalidade compra | a) mês fixo, entregas pela agenda (atual) · b) entregas do período × R$ 41 | **a** |
| D10 | Preço da dúzia | R$ 12,00 é real? Aparece no site? Pode variar por entrega? | Confirmar valor; congelar na entrega |
| D11 | Telefone oficial | (31) 2516-7561 ou (31) 92516-7561 | Confirmar |
| D12 | Selo "Mais escolhido" | manter · remover | Remover até haver dado |
| D13 | Tabela comparativa (criação, estoque do supermercado) | confirmar · reescrever · remover as linhas | Manter só o que a granja comprova |
| D14 | Programa de indicação | não existe (remover colunas da tela) · definir regra (quem ganha, quanto, quando) | Tirar da tela `/configuracoes` até haver regra |
| D15 | Estorno de fatura paga | não existe (atual) · permitir com motivo | Só se D6 = a |

---

## 6. ALTERAÇÕES RECOMENDADAS

**Nada abaixo foi implementado.** Cada item depende da decisão indicada.

### 6.1 Sem decisão pendente (podem ser feitas já, não mudam valor)

| Alteração | Motivo |
|---|---|
| **Migration `faturas`: congelar o cálculo.** `add column plano_id smallint references planos(id) on delete restrict`, `preco_pente_centavos integer`, `preco_duzia_centavos integer`, `pentes smallint`, `duzias smallint`, `entregas_no_periodo smallint`, `desconto_pct numeric(5,2)`, `tipo text check (tipo in ('periodo','avulsa')) not null default 'avulsa'`. `gerar_cobranca` passa a preencher. Faturas antigas ficam com nulo (sem inventar dado) | Lacuna A. Não muda nenhum valor; só registra como ele foi calculado |
| **Migration `pausas`**: `id uuid pk`, `assinatura_id uuid not null references assinaturas on delete restrict`, `inicio date not null`, `retorno_previsto date`, `retorno_efetivo date`, `motivo text`, `dias_estendidos smallint not null default 0`, índice por assinatura, RLS igual a `entregas`, gatilho `auditar()`. `pausar_assinatura` insere; `reativar_assinatura` fecha | Lacuna C. Histórico consultável; base para D3/D4 mesmo se a escolha for manter a regra atual |
| **Telefone em um lugar só**: uma constante em `packages/config` (ex.: `WHATSAPP_E164`) com o texto formatado derivado dela, usada pelos 5 arquivos | Hoje são 5 cópias, com dois números. O valor em si espera D11 |
| **Criar fatura avulsa não consome o desconto do 1º mês** (`calcular_valor_fatura` considerar só `tipo = 'periodo'`) | Depende da coluna `tipo`; corrige o cenário 3.2-7 |

### 6.2 Dependem de decisão

| Decisão | Tabela / coluna | Migration | Funções |
|---|---|---|---|
| D1 | `config_negocio.dias_tolerancia smallint not null default 0 check (between 0 and 28)` | 1 coluna | `gerar_cobranca`: `vencimento = periodo_inicio + dias_tolerancia` |
| D2 | `config_negocio.dias_bloqueio_atraso smallint` (nulo = desligado); `assinaturas.bloqueada_em date` | 2 colunas | `processar_rotina_diaria` bloqueia/não gera fatura nova; `marcar_entrega` recusa entregue com bloqueio; `registrar_pagamento` desbloqueia e recria entrega |
| D3 | `pausas.dias_estendidos` (6.1) | — | `reativar_assinatura` calcula a sobreposição entre a pausa e o último período cobrado; `inicio_proxima_cobranca` soma os dias estendidos |
| D4 | `config_negocio.pausa_max_dias smallint` | 1 coluna | `pausar_assinatura` limita o retorno previsto; rotina trata pausa vencida |
| D5 | `assinaturas.plano_agendado_id smallint references planos(id)`, `plano_agendado_desde date` | 2 colunas + check | `alterar_plano_assinatura` agenda; `gerar_cobranca` aplica antes de calcular e recalcula a entrega pendente |
| D6 | usa `assinaturas.data_fim` (já existe); `cancelamento_solicitado_em date` | 1 coluna | `cancelar_assinatura` agenda se o período está pago; `gerar_cobranca` não passa de `data_fim`; rotina efetiva na data |
| D7 | `status_assinatura` + valor `aguardando_pagamento` (ou `assinaturas.liberada_em date`) | enum ou 1 coluna; revisar índice `assinaturas_vigente_idx` e gatilho `assinaturas_ciclo` | `criar_assinatura` gera a 1ª fatura e não cria entrega; `registrar_pagamento` libera e cria a 1ª entrega |
| D8 | usa `dia_corte`/`hora_corte` (já existem) | nenhuma | `data_primeira_entrega` passa a receber o instante, não só a data |
| D9 = b | `faturas.entregas_no_periodo` (6.1) | — | `calcular_valor_fatura` conta as quartas do período |
| D10 | `entregas.preco_duzia_centavos integer` (congelado ao criar a entrega); talvez `planos_publicos` expor o preço da dúzia | 1 coluna | `calcular_valor_fatura` passa a usar as dúzias das entregas do período (se D9 = b) ou continua pelo padrão do cliente |
| D12–D14 | — | — | `usePlanos.ts`, `ComparisonTable.tsx`, `/configuracoes` |

### 6.3 Ordem sugerida depois das decisões

1. 6.1 inteiro (congelar cálculo da fatura, tabela `pausas`, telefone num lugar só).
2. D7 + D8 (1ª entrega e corte) — maior risco financeiro hoje.
3. D1 + D2 (vencimento e inadimplência).
4. D6 (cancelamento no fim do período).
5. D3 + D4 (extensão da pausa).
6. D5 (troca de plano agendada).
7. D10–D14 (dúzia, textos do site, indicação).

Cada passo com teste SQL próprio (`teste-fase10-*`), cobrindo os cenários da seção 3.2.
