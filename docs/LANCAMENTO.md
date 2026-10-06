# Checklist de lançamento — Ovo di Onça

Última revisão: 06/10/2026 (Bloco 11). **Nada aqui foi executado em produção nem no Neon**: tudo foi testado num Postgres 16 local e descartável. Cada item diz como conferir e como desfazer.

Legenda: ☐ a fazer · 🔒 só você pode fazer (credencial/decisão) · ⚠️ risco real se pular

---

## 0. O que já está pronto no código

| Área | Estado |
|---|---|
| Banco | 29 migrations, todas com `down`; ~280 verificações SQL + concorrência do limite de login |
| Site, fluxo de assinatura, funil, "Avise-me" | prontos e testados de ponta a ponta |
| D8 (1ª entrega só depois do pagamento) | pronta, **chave desligada por padrão** |
| Pagamento online | adaptador da InfinitePay **escrito sem a documentação oficial: não liga sozinho** (ver §6) |
| Limite de tentativas | login/cadastro e rotas públicas compartilhados entre instâncias (no Postgres) |
| CSP | **imposta** sem violações nas telas principais; padrão continua "relatório" (ver §8) |
| CI | `.github/workflows/ci.yml`, 4 jobs (ver §1) |

---

## 1. Antes de qualquer deploy

- ☐ **Conferir o CI.** O workflow já está em `.github/workflows/ci.yml` (roda em push na `main` e em todo pull request). ⚠️ Ele foi validado (sintaxe, scripts referenciados e simulação passo a passo num Postgres local), mas **nunca rodou no GitHub**: abra um pull request e confira os 4 jobs verdes antes de confiar nele.
- ☐ Rode localmente, num banco **de teste**: `pnpm db:migrar:teste && pnpm teste:banco && pnpm seguranca`.
  ⚠️ `teste:banco` espera um banco de teste **sem dados soltos**: a Fase 10 conta linhas (assinaturas, faixas de CEP) e falha se sobrou coisa de um E2E ou de uso manual. Rode os E2E (`scripts/e2e/*`) num banco **separado**, ou recrie o branch de teste antes. No CI isso já é garantido: cada job tem o próprio Postgres.

## 2. Banco (Neon)

⚠️ **Sempre no branch de teste primeiro, depois no principal.** As migrations 424–431 ainda não foram aplicadas em nenhum Neon.

1. ☐ 🔒 No Neon, **crie um branch do principal** (ponto de restauração) antes de migrar. É o seu "desfazer" mais rápido.
2. ☐ 🔒 `DATABASE_TEST_URL` apontando para o branch de teste → `pnpm db:migrar:teste` → `pnpm teste:banco` → `pnpm seguranca`. Tudo verde antes de seguir.
3. ☐ 🔒 `pnpm db:migrar` (banco principal, usa `DATABASE_ADMIN_URL`).
4. ☐ 🔒 **`pnpm db:papel-servidor`** de novo (com `APP_SERVIDOR_SENHA`): a migration 427 criou o papel `app_pagamentos`, e é este script que o concede ao `app_servidor`. Sem isso o webhook de pagamento falha com "permission denied" (os outros fluxos não sofrem).
5. ☐ 🔒 **Faixas de CEP** em `/area-de-entrega` do painel. ⚠️ Sem nenhuma faixa ativa **ninguém consegue assinar**.
6. ☐ Confira em `/configuracoes`: preço do pente, dia/hora do corte, planos (e o selo "Recomendado" do semanal).

**Como desfazer:** `pnpm db:reverter` desce uma migration por vez (cada uma tem `down` testado: o CI sobe, desce e sobe de novo). Em emergência, restaure o branch do passo 1.

## 3. Variáveis de ambiente por app

Valores reais só no painel da hospedagem; **nunca** no Git. O modelo completo, comentado, está em `.env.example`.

| Variável | Assinante | Gestão | Site | Observação |
|---|:--:|:--:|:--:|---|
| `DATABASE_URL` (papel `app_servidor`) | ✔ | ✔ | — | consultas sob RLS |
| `DATABASE_ADMIN_URL` (dona) | ✔ | ✔ | — | Better Auth e caminho do dono |
| `BETTER_AUTH_URL` / `BETTER_AUTH_SECRET` | ✔ | ✔ | — | o domínio real; segredo **diferente** do de teste (32+ caracteres) |
| `NEXT_PUBLIC_URL_ASSINANTE` / `_SITE` / `_GESTAO` | ✔ | ✔ | ✔ | ⚠️ lidas **no build**: trocar exige novo build |
| `CRON_SECRET` | — | ✔ | — | 32+ caracteres; autoriza `POST /api/rotina` |
| `CSP_MODO` | ✔ | ✔ | ✔ | ⚠️ lida **no build** (ver §8) |
| `PAGAMENTO_PROVEDOR`, `URL_PUBLICA_ASSINANTE` | ✔ | — | — | padrão `nenhum` (pagamento manual) |
| `RESEND_API_KEY`, `EMAIL_REMETENTE` | ✔ | ✔ | — | opcional; sem elas não há confirmação de e-mail |
| `GOOGLE_CLIENT_ID` / `_SECRET` | ✔ | ✔ | — | opcional |

⚠️ O **build** do assinante e do gestão precisa de `DATABASE_URL`, `DATABASE_ADMIN_URL`, `BETTER_AUTH_URL` e `BETTER_AUTH_SECRET` definidas (a rota do Better Auth é inicializada na coleta de páginas). Os valores **não são usados** no build (não abre conexão), mas têm de existir.

⚠️ **Atrás de proxy/CDN:** o limite de tentativas (login e rotas públicas) usa o **primeiro** IP de `x-forwarded-for`. Isso só é confiável se o proxy da hospedagem **reescreve** o cabeçalho com o IP real do cliente (Vercel, por exemplo). Se o proxy apenas **acrescenta** o IP ao final, o primeiro valor é o que o cliente mandou: qualquer um troca o cabeçalho a cada tentativa e foge do limite. Confira no provedor antes de abrir ao público; se for o caso de acrescentar, o limite precisa passar a ler o último IP (ou um cabeçalho próprio do provedor, como `cf-connecting-ip`), **nas duas pontas**: em `apps/assinante/src/lib/limite-publico.ts` (`ipDaRequisicao`) e em `advanced.ipAddress.ipAddressHeaders` do Better Auth (`packages/database/src/auth/better-auth.ts`). Hoje nenhuma das duas está configurada para isso.

## 4. Rotina diária

Gera as faturas (a do mês seguinte sai 7 dias antes), reativa pausas, marca faturas atrasadas (dia 8), **bloqueia quem está 25 dias além do vencimento (dia 28)** e (com a D8 ligada) cancela quem não pagou a 1ª fatura. É idempotente e serializada por bloqueio no banco: rodar duas vezes não duplica nada.

- ☐ 🔒 Agende **uma vez por dia** a execução de:
  ```bash
  URL_GESTAO=https://SEU-PAINEL CRON_SECRET=... bash scripts/rodar-rotina.sh
  ```
  O script sai com código ≠ 0 se a resposta não for 200 (o agendador deve alertar). O segredo vai só no cabeçalho.
- Onde agendar depende da hospedagem (ainda não escolhida): cron do servidor, tarefa agendada da plataforma, ou um workflow do GitHub com `schedule:` que rode o comando acima com `URL_GESTAO` e `CRON_SECRET` em *secrets*.
- Sem agendador, a rotina continua disponível no botão **"Rodar rotina agora"** do painel — mas **ninguém vai apertar todo dia**: faturas não são geradas e pausas não voltam sozinhas.

## 5. Chave D8 (1ª entrega só depois do pagamento)

- Padrão: **desligada** (comportamento de sempre). Liga em `/configuracoes` ("Só entregar depois do 1º pagamento"); vale só para assinaturas **novas**.
- ⚠️ Ligada sem pagamento online, quem assina precisa mandar o comprovante pelo WhatsApp e **o dono registrar o pagamento** em `/faturas` para a entrega ser agendada. Quem não pagar em `dias_para_pagar_1a_fatura` (7) é cancelado pela rotina — **a rotina precisa estar agendada** (§4).
- ☐ Atualize o FAQ ("Como funciona o pagamento?") em `/faq` quando ligar.
- **Desfazer:** desmarque a chave. Assinaturas já "aguardando" continuam aguardando (pague a fatura ou cancele).

## 6. Pagamento online (InfinitePay) — **não ligar antes disto**

O adaptador (`apps/assinante/src/lib/pagamento/infinitepay.ts`) foi escrito **sem acesso à documentação oficial**. Pontos marcados «A CONFIRMAR» no código: endereço de criação de link, nomes dos campos, **unidade do valor (centavos?)** e formato do aviso.

1. ☐ 🔒 Conferir cada ponto em infinitepay.io/checkout-documentacao e ajustar o arquivo.
2. ☐ 🔒 `INFINITEPAY_HANDLE` (InfiniteTag, sem `$`), `PAGAMENTO_PROVEDOR=infinitepay`, `INFINITEPAY_CONTRATO_CONFIRMADO=sim`.
3. ☐ 🔒 `URL_PUBLICA_ASSINANTE=https://...` — o aviso chega em `<URL>/api/pagamento/webhook` e precisa ser alcançável pela internet, em https.
4. ☐ **Teste real de ponta a ponta com valor pequeno** antes de abrir ao público: gerar fatura → pagar → conferir `paga` e a entrega. Se a unidade do valor estiver errada, o efeito seguro é "divergente" no painel (nada é baixado a menos).
5. ☐ Com a CSP imposta (§8), confirme que o clique em "Pagar agora" leva ao domínio da InfinitePay.

Cartão **recorrente** não consta como suportado pelo checkout deles: "cartão" segue como fatura mensal com link avulso.

**Desfazer:** `PAGAMENTO_PROVEDOR=nenhum` (o webhook passa a responder 404 e o portal volta às instruções de PIX).

## 7. Domínio, HTTPS e cabeçalhos

- ☐ 🔒 Três endereços (site, assinante, gestão) com HTTPS. `BETTER_AUTH_URL` e `NEXT_PUBLIC_URL_*` com os domínios reais, e **rebuild**.
- ⚠️ O HSTS enviado inclui `includeSubDomains; preload` por 2 anos. Só ative o domínio quando **todos** os subdomínios servirem HTTPS, e **não submeta** o domínio à lista de preload do navegador sem ter certeza (é difícil desfazer).
- ☐ Login com Google (se usar): adicione `https://SEU-DOMINIO/api/auth/callback/google` no Google Cloud Console.

## 8. CSP (política de segurança de conteúdo)

Hoje o padrão é **relatório** (só avisa no console). Para impor:

1. Defina `CSP_MODO=impor` e **faça novo build** (é lida no build).
2. Antes de publicar, rode `scripts/e2e/csp.mjs` contra esse build: ele navega pelas telas principais e reprova se houver qualquer violação. (Testado: 0 violações nos 3 apps.)
3. Em seguida rode o teste de fumaça (§9).

**Desfazer:** `CSP_MODO=relatorio` + novo build.

## 9. Depois de cada deploy

- ☐ Teste de fumaça (somente leitura; falha com código 1):
  ```bash
  SITE=https://... ASSINANTE=https://... GESTAO=https://... node scripts/smoke.mjs
  ```
  Confere: o que responde, o que se recusa (visitante sem login é mandado ao `/entrar`, `/api/rotina` sem segredo é 401, o simulador de pagamento não existe), os cabeçalhos de segurança e que nenhuma resposta vaza URL de banco, nome de segredo ou stack trace.
- ☐ Monitor de disponibilidade: aponte para `GET /api/saude` do assinante e do gestão (200 `{ok:true}` ou 503; só devolve `ok`, sem detalhe). O site também tem `/api/saude`.
- ☐ Faça **uma assinatura de verdade** com um e-mail seu e confira: conta → endereço → confirmação → portal.

## 9b. SEO e desempenho do site

- ☐ **`NEXT_PUBLIC_URL_SITE` = endereço público real** do site, **antes do build** (canonical, Open Graph, sitemap e robots partem dele; com o padrão `localhost` o buscador receberia endereços inválidos).
- ☐ O **site precisa alcançar o app do assinante no servidor** (`NEXT_PUBLIC_URL_ASSINANTE`): é de lá que a home busca planos/FAQ/bairros. Se não alcançar, a página ainda funciona (busca pelo navegador), mas o buscador volta a ver a vitrine sem os planos. O smoke reprova nesse caso.
- ☐ Registre o site no Google Search Console e envie `/sitemap.xml`.
- 🔒 **`/privacidade` e `/termos` são rascunhos factuais**: faltam razão social/CNPJ do controlador e revisão jurídica antes de valerem como documento final.
- ☐ Orçamento de desempenho (laboratório): `SITE=https://... node scripts/e2e/desempenho.mjs` (precisa de Playwright + Chromium). Em produção meça também com dados reais de campo.
- Sem fotos/avaliações reais, **não** foram publicados dados estruturados de avaliação ou endereço (só Organization, WebSite e FAQPage, que espelham o que a página mostra).

## 10. Monitoramento de erros e backup

- 🔒 **Ferramenta de erros: ainda não escolhida** (Sentry, logs da hospedagem, etc.). Hoje os erros inesperados vão só para `console.error` do servidor, **sem dado pessoal** por convenção. Sem ferramenta, ninguém é avisado de falhas.
- 🔒 **Backup:** use o histórico/branches do Neon (confira o prazo de retenção do seu plano). O branch criado antes de cada migration (§2) é o ponto de restauração mais simples.

## 11. Pendências conhecidas (não bloqueiam o lançamento da vitrine, mas existem)

- Sem serviço de e-mail: ninguém tem e-mail confirmado; o dono vincula contas à mão na ficha do cliente.
- **Antes de migrar o Neon principal (migration 429, D1/D2):** assinaturas que já existem com `proxima_cobranca` no meio do mês recebem **uma fatura de transição** até o fim do mês e só depois entram no ciclo do dia 1; e **faturas que já estiverem vencidas há mais de 25 dias bloqueiam a assinatura na primeira rotina**. Rode antes `select a.id from assinaturas a join faturas f on f.assinatura_id = a.id where a.status='ativa' and f.status in ('pendente','atrasada') and f.vencimento + 25 <= current_date;` para saber quem será bloqueado e avisar essas pessoas.
- **Migration 430 (D3–D7):** assinaturas **pausadas há mais de 60 dias** passam a aparecer no painel como pendência (consulta antes: `select a.id, p.inicio from pausas_assinatura p join assinaturas a on a.id = p.assinatura_id where p.status = 'ativa' and p.inicio + 60 < current_date;`). Cancelar passa a **agendar** para o fim do mês pago: avise quem opera o painel (há a opção "Cancelar agora"). Reduções de plano ficam agendadas para o mês seguinte.
- **Migration 431 (D11/D15):** põe `bonus_indicador_pct` = 10 **só onde estiver em zero**. 🔒 **Defina o preço real da dúzia em `/configuracoes`** (o R$ 12,00 era valor de teste): com preço zero a dúzia sai de graça. Todas as regras D1–D15 estão implementadas. As interpretações da D1/D2 e da D3–D7 (fatura 7 dias antes, período bloqueado não cobrado, crédito sem refazer o desconto do 1º mês, crédito que sobra ao cancelar) precisam da confirmação do Fred/da Bruna.
- Texto de consentimento do "Avise-me" **precisa de revisão jurídica** (`packages/config/src/privacidade.mjs`).
- Fotos e depoimentos reais ainda não existem no site.
- `rateLimit` no Better Auth cobre login/cadastro; as demais rotas do Better Auth usam o limite geral (100/min por IP).
