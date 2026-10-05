# Diagnóstico técnico — Ovo di Onça (30/09/2026)

Auditoria feita só com leitura: não alterei código, banco nem git. Li o código, rodei consultas só de leitura (`begin read only`) no Neon e medi a latência. Os resultados de testes citados são os da última execução, feita no commit `05dd6bd` (branch `feature/assinatura-pelo-site`).

## ESTADO ATUAL

O núcleo de gestão está implementado e testado no banco: clientes, planos, assinaturas, entregas, faturas manuais, pausa/cancelamento e auditoria. O cliente já consegue assinar pelo site, e esse fluxo foi verificado no navegador. O banco de produção/desenvolvimento, porém, **está vazio**: 0 clientes, 0 assinaturas e **0 faixas de CEP**, então hoje ninguém consegue assinar. As telas do painel do dono **nunca foram testadas no navegador**, só as funções SQL por trás delas. Não existem pagamento online, envio de e-mail nem registro de defeito/reposição. A lentidão do painel vem principalmente do banco estar nos EUA e de conexões que "esfriam", não do código.

## ARQUITETURA

- **Frontend:** 3 apps Next.js 15 / React 19. `apps/site` (vitrine, porta 3002), `apps/assinante` (área do cliente, 3001), `apps/gestao` (painel do dono, 3000). Usam Server Components e Server Actions, com estilo por tokens CSS em `packages/ui`.
- **Backend:** o próprio Next (Server Actions e Route Handlers). Não há servidor separado.
- **Banco:** PostgreSQL 16 no Neon, região **us-east-2 (Ohio)**, conexão pelo pooler. É um **único banco**, usado para desenvolvimento e para os testes.
- **ORM:** nenhum. SQL cru via `pg`, encapsulado em `packages/database/src/acesso.ts` (`comoAnonimo` / `comoUsuario` / `comoAdmin`), com troca de papel via `set_config('role')`. A proteção real está na RLS e em 42 funções SQL com lista fechada de campos.
- **APIs:** `apps/assinante/src/app/api`: `auth/[...all]` (Better Auth), `plans`, `neighborhoods`, `area`. O site as acessa por rewrites.
- **Autenticação:** Better Auth 1.7.6 (e-mail/senha com mínimo de 12 caracteres). O Google está preparado mas não configurado. O controle de tentativas fica em memória. A confirmação de e-mail só liga se houver serviço de e-mail, e hoje não há. Papéis: `dono` e `assinante`.
- **Migrations:** `node-pg-migrate`, 14 aplicadas (fases 0 a 8).
- **Testes:**
  - SQL por fase (`teste:estrutura`, `teste:autorizacao`, `teste:fase1..8`), todos passando, rodando em transação com rollback **no banco real**.
  - 4 testes unitários (`pnpm test`).
  - O CI roda typecheck, testes unitários, varredura de segredos e audit. **Não roda os testes SQL nem o build.**
  - Não há testes E2E automatizados.

## FUNCIONALIDADES

Convenção dos estados: **FUNCIONANDO** = fluxo completo tela → banco → tela verificado. **PARCIAL** = implementado e testado no banco, mas a tela não foi exercitada no navegador, ou falta parte da regra.

| Funcionalidade | Estado | Evidência | Problema | Prioridade |
|---|---|---|---|---|
| Assinatura pelo site (conta, endereço, CEP, assinatura) | FUNCIONANDO | Teste no navegador em 29/09 + fase 8 (24/24) | Depende de faixas de CEP, que estão vazias | P0 |
| Área de entrega (faixas de CEP) | BLOQUEADO | Tabela com 0 linhas; tela `/area-de-entrega` existe | Sem faixas, todo CEP fica "fora da área" | P0 |
| Clientes: cadastro, edição, pesquisa, filtros | PARCIAL | `clientes/*`, fase 1 (8/8) | Tela não testada no navegador | P1 |
| Clientes: endereço e bairro | PARCIAL | Colunas completas; `dentro_area_entrega` calculado | Bairro é texto livre, sem relação com a faixa | P2 |
| Clientes: status | PARCIAL | Gatilhos das fases 5 e 8 ajustam o status | Não testado na tela | P1 |
| Clientes: histórico | PARCIAL | `/historico` + auditoria (fase 6, 19/19) | Não testado na tela | P1 |
| Vínculo conta ↔ cliente | PARCIAL | Automático só com e-mail confirmado; manual na ficha do cliente | Sem e-mail, só o vínculo manual funciona | P1 |
| Planos (semanal/quinzenal/mensal, intervalo 7/15/30) | FUNCIONANDO | `planos_publicos()` exibido no site | `entregas_por_mes` 4/2/1 foi deduzido, não confirmado | P1 |
| Valores e desconto de 1º mês | PARCIAL | `calcular_valor_fatura`; 10% só na 1ª fatura | Preço da dúzia = 0 (valor provisório) | P1 |
| Frequência e entrega às quartas | FUNCIONANDO | `ancorar_em_quarta`; F8.17 testa 21 datas | — | — |
| Entregas: agenda, data, status | PARCIAL | `/entregas`, `marcar_entrega`, fase 3 (23/23) | Tela não testada no navegador | P1 |
| Entregas: horário | NÃO IMPLEMENTADO | Só `data_prevista` (date); não há janela de horário | Regra de negócio não definida | P3 |
| Entregas: bairro | PARCIAL | Lido do cliente na hora da consulta | Endereço não é congelado na entrega | P2 |
| Defeitos: registro, reposição, histórico | NÃO IMPLEMENTADO | Nenhuma tabela ou função; DECISOES #14 exige | Falta a funcionalidade inteira | P1 |
| Pausa: início e retorno | PARCIAL | `pausar_assinatura` / `reativar_assinatura(p_retorno)`, fase 5 (17/17) | Sem data prevista de retorno ao pausar; retorno é manual | P2 |
| Pausa: impacto em entregas e cobranças | PARCIAL | Cancela entregas e faturas pendentes; atrasadas continuam | Regra de fatura durante a pausa em aberto | P1 |
| Pedido de pausa/cancelamento pelo assinante | COM ERRO | Assinante grava em `solicitacoes_assinatura` | **O dono não tem tela para ver ou resolver**: pedido fica sem resposta | P1 |
| Cobranças: valor, vencimento, pagamento, status | PARCIAL | `/faturas`, fase 4 (26/26) | Fatura criada à mão; o dono escolhe o vencimento | P1 |
| Cobranças: próxima cobrança (recorrência) | NÃO IMPLEMENTADO | Nenhum job ou função de geração periódica | — | P1 |
| Cobranças: forma de pagamento | PARCIAL | enum `pix, dinheiro, transferencia, outro` | **Falta "cartão"**, embora o desconto valha para cartão | P2 |
| Pagamento online (InfinitePay/Asaas) | NÃO IMPLEMENTADO | Só variáveis comentadas no `.env.example` | Depende de decisão e credenciais | P1 |
| Faturas atrasadas | PARCIAL | `marcar_faturas_atrasadas()` | Roda como UPDATE a cada abertura de `/faturas` | P2 |
| Histórico/auditoria (plano, endereço, pausa, cobrança, status) | PARCIAL | Gatilho `auditar()` em 8 tabelas, imutável | Substituição não existe; `perfis` e `user` não auditados | P2 |
| E-mail de confirmação de conta | BLOQUEADO | Adaptador pronto; `RESEND_API_KEY` ausente | Falta provedor e credencial | P1 |
| Login com Google | BLOQUEADO | `GOOGLE_*` vazios no `.env` | Opcional | P3 |
| Configurações (`/configuracoes`) | NÃO IMPLEMENTADO | Está no menu, retorna 404 | Preços só mudam por SQL | P1 |
| Área do assinante (dados, entregas, faturas) | PARCIAL | `/` e `/dados`; tela inicial vista no navegador | `/dados` não foi testado no navegador | P2 |

## MOCKS E CONTEÚDO FIXO

Não há dados falsos, APIs simuladas, `setTimeout` de simulação nem IDs fixos no código. O que existe:

| Ocorrência | Tipo | Classificação |
|---|---|---|
| `ComparisonTable` (5 linhas, comparação com supermercado) | Texto de marketing fixo | "Galinhas livres, ao ar aberto" e "em gaiolas" **não estão em DECISOES**: afirmação sem confirmação |
| `FaqSection` (7 perguntas) | Texto fixo | Coerente com DECISOES |
| Selo "Mais escolhido" no semanal | Afirmação fixa | Sem dado que a sustente |
| Telefone: exibido (31) 2516-7561 × link 5531925167561 | Inconsistência | Um dos dois está errado |
| Lista de features dos planos (`/api/plans`) | Texto fixo derivado de `ancorar_em_quarta` | Aceitável |
| `NEXT_PUBLIC_URL_ASSINANTE ?? localhost:3001` | Valor de desenvolvimento | Exige a variável em produção |
| Conta de teste `e2e-dono@…` com papel **dono** (há 2 donos no banco) | Dado de teste real no banco | **Remover** (anotado no PROGRESSO) |

## SEGURANÇA

- **`.env`:** ignorado pelo `.gitignore` e ausente do histórico. Não existe `.env.local`. Valores não foram revelados nesta auditoria.
- **O que está bem:**
  - RLS em todas as tabelas; nenhum grant de escrita para os papéis da aplicação.
  - Funções SQL com lista fechada de campos e `search_path` fixo.
  - Validação no servidor e no banco; mensagens de login genéricas.
  - Varredura de segredos (8 verificações) limpa.
  - Cadastro público fechado no painel do dono.
- **Riscos:**
  1. Um banco só para desenvolvimento, testes e produção.
  2. O Better Auth usa a conexão de dono do banco (`DATABASE_ADMIN_URL`), que ignora a RLS.
  3. Conta de teste com papel de dono no banco.
  4. Controle de tentativas de login em memória (não vale entre instâncias).
  5. CSP só em modo relatório (avisa, não bloqueia).
  6. E-mail não confirmado: quem cria conta com e-mail alheio não vê dados, mas ocupa aquele e-mail no cadastro.
  7. 21 linhas na tabela de sessões, sem limpeza.
  8. Nada disso garante proteção absoluta.

## PERFORMANCE: causa provável dos mais de 4 s

Medido nesta auditoria:
- **Abrir uma conexão nova: 3,5 s.** Somam-se TLS e autenticação até Ohio, e provavelmente o "despertar" do Neon depois de ocioso.
- **Cada consulta: 142–167 ms** de ida e volta.

Somando:
1. **Conexão fria.** O pool fecha conexões ociosas após 5 min e o Neon suspende o banco quando fica parado. A primeira requisição paga cerca de 3,5 s (conexão nova, e mais se o banco precisar acordar). Isso sozinho já explica a espera inicial de ~4 s.
2. **Consultas em série.** Uma página do painel faz a leitura da sessão (Better Auth, 1–2 idas), a leitura do papel (`comoUsuario`: 3 idas) e a página em si (begin + 3 consultas + commit ≈ 5 idas). São ~10 idas × 150 ms ≈ **1,5 s mesmo com conexão quente**.
3. **Região do banco.** Ohio fica a ~150 ms do Brasil; São Paulo (`sa-east-1`) reduziria cada ida para algo em torno de 10–30 ms.
4. **Modo de desenvolvimento do Next.** A primeira visita a cada rota compila na hora (2 a 8 s observados no log). Isso não acontece em produção.

Não há consultas pesadas; o volume de dados é zero. **Causa principal: latência de rede e conexão fria, somadas ao modo dev.**

## BANCO DE DADOS

- **Existentes (15):**
  - Autenticação: `user`, `session`, `account`, `verification`, `perfis`.
  - Negócio: `config_negocio`, `planos`, `faixas_cep_atendidas`, `clientes`, `assinaturas`, `entregas`, `faturas`, `solicitacoes_assinatura`.
  - Controle: `auditoria`, `pgmigrations`.
- **Integridade:**
  - Chaves estrangeiras de negócio usam `restrict`, sem cascade (histórico preservado). `set null` só em `clientes.usuario_id` e `clientes.indicado_por`.
  - Nenhum perfil sem usuário (0 órfãos).
  - Com 0 linhas de negócio, não há duplicados nem outros órfãos possíveis.
  - Índices únicos: entrega por data, fatura por vencimento, e-mail do cliente.
- **Faltam:**
  - Tabela de **reposições/defeitos**, ligada à entrega com defeito e à entrega que repõe.
  - Estrutura para **cobrança recorrente** e **pagamento online**: id da cobrança no provedor, link/QR, status do webhook e registro idempotente de eventos.
- **Alterações necessárias:**
  - Incluir `cartao` em `metodo_pagamento`.
  - Data prevista de retorno na pausa, se o negócio quiser.
  - Congelar endereço e preço na entrega/fatura (decisão pendente).
  - Possível janela de horário na entrega (regra não definida).
  - Tela e ações de resolução de `solicitacoes_assinatura`: a tabela já tem `resolvida_em` e `resolvida_por`; falta só a aplicação.
- **Relacionamentos incorretos:** nenhum. Só uma redundância consciente: `entregas.cliente_id` e `faturas.cliente_id` repetem `assinaturas.cliente_id`, mantidos por gatilho e usados pela RLS.
- **Migrations necessárias:** (1) reposições; (2) `metodo_pagamento` + cartão; (3) pagamento online / eventos do provedor, depois da decisão; (4) opcionais: congelamento de endereço e preço, retorno previsto da pausa.

## PLANO DE AÇÃO

- **P0 — bloqueadores**
  - Cadastrar as faixas de CEP reais (dado do negócio).
  - Remover a conta de teste `e2e-dono`.
  - Separar um banco (ou branch do Neon) para testes.
- **P1 — funcionalidades essenciais**
  - Tela do dono para pedidos de pausa/cancelamento.
  - Teste manual no navegador de todo o painel do dono.
  - `/configuracoes`.
  - Reposição de defeitos.
  - Cobrança recorrente (regra a definir).
  - Pagamento online (decisão entre InfinitePay e Asaas + credenciais).
  - Serviço de e-mail.
  - Confirmar `entregas_por_mes`, preço da dúzia e se a entrega acontece antes do 1º pagamento.
- **P2 — consistência, segurança e confiabilidade**
  - Performance: banco em São Paulo; manter conexão aquecida ou reduzir as idas por página (juntar leitura de sessão e papel).
  - Tirar `marcar_faturas_atrasadas` do GET e passar para um job.
  - Método "cartão".
  - Testes SQL e build no CI (contra um banco de teste).
  - Better Auth com papel próprio, em vez do dono do banco.
  - Controle de tentativas de login compartilhado entre instâncias.
  - CSP em modo de bloqueio.
  - Corrigir telefone e afirmações de marketing sem confirmação.
  - Congelar endereço na entrega.
- **P3 — melhorias**
  - Paginação das listas.
  - Janela de horário de entrega.
  - Login com Google.
  - Testes E2E automatizados.
  - Remover `next lint` (descontinuado) e o aviso de `ComparisonRow`.
  - Limpar arquivos `_tmp_*` e pôr o design system no `.gitignore`.

## ORDEM DE EXECUÇÃO

1. Criar um banco ou branch de teste no Neon e apontar os testes SQL para ele. Hoje os testes rodam no banco real.
2. Remover a conta de teste com papel de dono.
3. Teste manual no navegador de todo o painel do dono (cliente → assinatura → entrega → fatura → pagamento → pausa → reativação → cancelamento → histórico), corrigindo o que falhar.
4. Tela e ações para o dono resolver os pedidos de pausa/cancelamento.
5. `/configuracoes` (preços, planos), para parar de depender de SQL.
6. Performance: medir em build de produção; avaliar migração do Neon para `sa-east-1`; reduzir as idas por página.
7. Coletar as decisões pendentes: faixas de CEP, `entregas_por_mes`, dúzia, entrega antes do pagamento, recorrência, provedor de pagamento, provedor de e-mail, telefone correto.
8. Cadastrar as faixas de CEP (o dono, pelo painel).
9. Migration e telas de reposição de defeitos.
10. Método "cartão" + job de faturas atrasadas.
11. Cobrança recorrente, conforme a regra decidida.
12. Serviço de e-mail (credencial) e ativação da confirmação de conta.
13. Integração de pagamento online com webhook verificado e idempotente, validada no ambiente de testes do provedor.
14. P2 restante (CI com banco de teste, papel próprio para o Better Auth, controle de tentativas compartilhado, CSP em bloqueio) e depois P3.
