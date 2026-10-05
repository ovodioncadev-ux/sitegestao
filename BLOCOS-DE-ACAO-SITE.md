# Blocos de ação — site completo (gráfico + back-end)

Gerado em 05/10/2026 a partir da leitura de `CLAUDE.md`, `docs/CODEBASE_MAP.md`, `DECISOES.md`, `apps/site`, `packages/ui` e `Interface Stitch/`.

## Ponto de partida (o que existe de fato)

| Camada | Estado |
|---|---|
| **Site (`apps/site`)** | 7 componentes, 682 linhas, estilo inline com tokens `@ovo/ui`. Planos/bairros/CEP vêm do assinante por rewrites. "Assinar" é só um link para `/assinar?plano=`. Sem fotos, sem fontes carregadas (`Aclonica`/`Poppins` declaradas, nunca importadas), sem SEO além de title/description. |
| **Design de referência** | `Interface Stitch/01_site_público…` (hero, pilares, planos, FAQ, CTA final, rodapé) e `clube_caipira_da_granja/DESIGN.md` (Outfit + Archivo + IBM Plex Mono, paleta `#944a00`/`#e67e22`/`#50652a`). **Diverge dos tokens atuais** (fontes e cores). |
| **Back-end** | Postgres com RLS, 24 migrations, funções SQL com lista fechada, Better Auth. Fluxo `/assinar` pronto. Etapas 1–2 (snapshot de fatura, pausas, calendário nas quartas, corte) prontas. |
| **Faltando** | Faixas de CEP (ninguém assina), e-mail, pagamento online, D1–D8 e D11/D15 (regras decididas e não implementadas), cron da rotina, `/configuracoes` já existe (Etapa 1). |

## Conflitos achados na leitura (resolver antes de pintar tela)

1. **Fontes:** tokens usam Aclonica/Poppins; o design Stitch usa Outfit/Archivo. `DECISOES.md` deixa isso "em aberto".
2. **Nomes de plano:** o Stitch mostra "Cesto Quinzenal / Semanal 30 / Familiar 60"; o banco tem semanal/quinzenal/mensal (D10). Vale o banco.
3. **Preço no site:** hoje mostra "R$ 164/mês" fixo; D10 manda mostrar "R$ 41 por entrega · cerca de R$ 164/mês no semanal".
4. **Dúzia (D11):** não pode aparecer no site público.
5. **Brinde / atendimento prioritário (#16):** proibidos; conferir o Stitch antes de copiar texto.
6. **`FUNCIONALIDADES-SITE.md` está desatualizado** (ainda descreve checkout modal e "22 bairros").

---

## Bloco 0 — Decisões que destravam o resto (você / Fred / Bruna)

Sem isso os blocos 3, 5 e 6 ficam parados.

- [ ] Fonte da marca: Aclonica+Poppins **ou** Outfit+Archivo.
- [ ] Provedor de pagamento: InfinitePay ou Asaas (ou continuar 100% PIX manual por ora).
- [ ] Provedor de e-mail (Resend já tem adaptador).
- [ ] Lista real de faixas de CEP/bairros atendidos.
- [ ] Domínio de produção + onde hospedar (3 apps + Neon).
- [ ] Fotos e textos reais (granja, galinhas, ovos, entrega).
- [ ] Confirmar "interpretação a confirmar" da D3 (crédito de pausa).

**Pronto quando:** cada item tem resposta registrada em `DECISOES.md`.

---

## Bloco 1 — Fundação visual (design system do site)

**Objetivo:** uma base única de tokens e componentes, em vez de estilo inline repetido.

- [ ] Alinhar `packages/ui/src/tokens.css` ao Stitch (cores `surface/primary/secondary`, raios, sombras, espaçamentos, breakpoints) conforme a decisão de fonte do Bloco 0.
- [ ] Carregar fontes com `next/font` (hoje não são carregadas → cai em `system-ui`).
- [ ] Criar `apps/site/src/components/ui/`: `Botao`, `Cartao`, `Selo`, `Secao` (com título/subtítulo), `Container`, `Icone`.
- [ ] Trocar `style={{…}}` inline por classes (Tailwind já está importado em `globals.css`) ou CSS modules; manter contraste AA e foco visível.
- [ ] Revisão de acessibilidade base: `prefers-reduced-motion`, alvo de toque ≥ 44px, ordem de tabulação, `lang=pt-BR`.

**Arquivos:** `packages/ui/src/tokens.css`, `apps/site/src/app/{layout,globals}.css|tsx`, novo `components/ui/*`.
**Pronto quando:** `pnpm typecheck` e lint passam; nenhum hex solto em componente; Lighthouse acessibilidade ≥ 95.

---

## Bloco 2 — Seções da página (fiel ao Stitch)

**Objetivo:** reconstruir a landing seguindo `01_site_público_shell_institucional`.

Ordem das seções: Navbar → Hero (com foto) → faixa de confiança (7 dias, frete incluso na área, sem fidelidade) → 3 pilares (origem, ciclo semanal, flexibilidade) → destaque do produto (gema) → **Planos** → Como funciona (4 passos) → Comparativo (D14: manter) → Área de entrega → Depoimentos (só se houver reais) → FAQ → CTA final → Rodapé.

- [ ] Reescrever `Hero`, `Navbar` (menu mobile/hambúrguer — hoje não há), `Footer`.
- [ ] Novas: `Pilares`, `ComoFunciona`, `CtaFinal`, `FaixaConfianca`.
- [ ] `PlansSection`: preço por entrega + estimativa do mês (D10), selo vindo do banco ("Recomendado", D13), sem dúzia (D11), skeleton em vez de "Carregando…", erro com botão "Tentar de novo".
- [ ] `NeighborhoodSection`: campo de CEP em destaque (máscara via `formatar.ts`), resultado "Atendemos / Ainda não atendemos — avise-me" (liga ao Bloco 5), lista de bairros quando houver faixas.
- [ ] Imagens otimizadas (`next/image`, WebP/AVIF, `alt` em pt-BR). Sem foto de banco que pareça ser da granja real.
- [ ] Texto 100% em pt-BR e conferido contra `DECISOES.md` (#1, #15, #16, D13).

**Pronto quando:** screenshot desktop (1280) e mobile (390) comparados com `screen.png` do Stitch; nenhuma promessa fora das decisões.

---

## Bloco 3 — Back-end público do site (APIs e dados)

**Objetivo:** tudo que o site mostra vem do banco; nada de texto de preço/área no código.

- [ ] `planos_publicos()` devolver também "entregas no mês" estimadas (D10) e texto do calendário (semanal = toda quarta; quinzenal = 1ª e 3ª; mensal = 1ª).
- [ ] Endpoint `GET /api/site/conteudo` (ou colunas em `config_negocio`): telefone WhatsApp, horário de corte, dia de entrega, frescor — editáveis em `/configuracoes` do gestão.
- [ ] FAQ e depoimentos em tabelas (`faq_itens`, `depoimentos`) lidos por `app_anon` com RLS só de ativos; CRUD no gestão (`exigirDono` + função SQL de lista fechada).
- [ ] Manter cache (30 s) e rewrites; adicionar `Cache-Control`/`revalidate` e rate limit nas rotas públicas.
- [ ] Testes SQL novos (`teste-fase11-site.sql`) com controle positivo; teste unitário das rotas.

**Arquivos:** nova migration `…424_site-conteudo.sql`, `apps/assinante/src/app/api/*`, `apps/gestao/src/app/{faq,depoimentos}/*`.
**Pronto quando:** `pnpm teste:banco`, `pnpm seguranca`, `pnpm test` verdes; `app_anon` sem escrita (Lei 1).

---

## Bloco 4 — Conversão: do clique à assinatura

**Objetivo:** o fluxo `Assinar → /assinar` fica contínuo e confiável (back-end já pronto; falta experiência).

- [ ] Fazer `/assinar`, `/cadastro`, `/entrar` do assinante usarem os mesmos tokens/componentes do site (hoje são visualmente outro produto).
- [ ] Passo-a-passo com indicador (plano → conta → endereço → confirmação), estados de erro/carregando, CEP fora da área → captura de interesse (Bloco 5).
- [ ] Página de sucesso pós-assinatura (`/?nova=1`) explicando a 1ª entrega e como pagar o PIX.
- [ ] Eventos de funil (clique em plano, início do cadastro, conclusão) em endpoint próprio, sem dado pessoal na URL.
- [ ] Teste ponta a ponta com Playwright: site → plano → cadastro → endereço → confirmação.

**Pronto quando:** E2E passa com faixa de CEP de teste; nenhum dado pessoal em query string (regra atual do `CLAUDE.md`).

---

## Bloco 5 — Captação de interesse (fora da área e contato)

**Objetivo:** não perder quem digita um CEP não atendido e dar canal de contato além do WhatsApp.

- [ ] Tabela `interessados` (nome opcional, contato, CEP, origem) + função SQL `registrar_interesse(...)` (`security definer`, `search_path` fixo, grant só a `app_anon`, validação e rate limit por IP/hash).
- [ ] Rota `POST /api/interesse` no assinante, rewrite no site; honeypot + limite; sem CORS.
- [ ] Tela no gestão `/interessados` (lista, marcar "avisado", exportar); aviso automático quando uma faixa nova cobrir o CEP.
- [ ] Consentimento (LGPD) com texto curto no formulário.
- [ ] Auditoria (`auditar()`) na tabela nova; teste SQL de isolamento.

**Depende de:** Bloco 0 (e-mail, se o aviso for por e-mail).

---

## Bloco 6 — Back-end de negócio que o site promete

**Objetivo:** fechar as regras decididas e não implementadas, para o site não prometer o que o sistema não cumpre.

Ordem sugerida (cada uma com migration, teste SQL e rollback):

1. **D8** — 1ª fatura gerada ao assinar (com 10%); 1ª entrega só após o pagamento. Passar o instante do pagamento a `criar_assinatura`.
2. **D1/D2** — fatura do mês do calendário, vence dia 3, atrasada dia 8, bloqueio no dia 28.
3. **D7 / D6** — cancelamento no fim do mês pago; troca de plano (aumento na hora, redução no mês seguinte).
4. **D3–D5** — crédito de pausa, redução de fatura, limite de 60 dias.
5. **D11 / D15** — dúzia pedida pelo assinante e aprovada pelo dono; desconto de indicação.
6. **Pagamento online** (se decidido no Bloco 0): webhook assinado, idempotência, conciliação, nunca confiar no cliente.
7. **E-mail transacional:** confirmação de conta, fatura gerada, lembrete de vencimento.

**Pronto quando:** cada regra tem teste SQL com controle positivo e `FUNCIONALIDADES-SITE.md`/`DECISOES.md` atualizados.

---

## Bloco 7 — SEO, desempenho e conteúdo técnico

- [ ] Transformar `page.tsx` em Server Component com seções estáticas (hoje `SiteApp` é 100% client → HTML inicial vazio de conteúdo).
- [ ] `metadata` completa: Open Graph, Twitter, canonical, `lang`, ícones, `manifest`.
- [ ] JSON-LD (`LocalBusiness`/`Product`/`FAQPage`), `sitemap.xml`, `robots.txt`.
- [ ] Páginas legais: Termos, Privacidade (LGPD), Política de cancelamento/pausa.
- [ ] Orçamento: LCP < 2,5 s em 4G, CLS < 0,1, JS inicial enxuto.
- [ ] Analytics respeitando consentimento (sem cookie antes do aceite).

---

## Bloco 8 — Segurança, qualidade e entrada no ar

- [ ] CSP: sair de report-only (`modoRelatorio: false`) depois de validar fontes/imagens/analytics.
- [ ] Rate limit compartilhado (hoje em memória) — usar `docs/RATE-LIMIT-DB-CONFIG.md` como base.
- [ ] CI: adicionar build dos 3 apps, `pnpm test`, E2E; testes SQL contra o branch de teste.
- [ ] Cron da rotina diária (`POST /api/rotina` + `CRON_SECRET`) e de faturas atrasadas.
- [ ] `.env.example` completo; remover `_tmp_*`; `.gitignore` do Design System.
- [ ] Deploy (staging → produção), domínio, HTTPS/HSTS, backups Neon, monitoramento de erros.
- [ ] Checklist de lançamento: faixas de CEP cadastradas, teste de assinatura real, telefone/WhatsApp único (`packages/config/src/whatsapp.mjs`).

---

## Ordem recomendada e paralelismo

```
Bloco 0 ──┬─> Bloco 1 ─> Bloco 2 ─┬─> Bloco 4 ─┐
          │                       └─> Bloco 7 ─┤
          ├─> Bloco 3 ────────────> Bloco 5 ───┤──> Bloco 8 (lançamento)
          └─> Bloco 6 (1→7, independente do visual) ┘
```

- **Trilha gráfica:** 1 → 2 → 4 → 7.
- **Trilha back-end:** 3 → 5, e 6 em paralelo.
- **Mínimo para publicar com segurança:** 0, 1, 2, 3, 4, 8 + faixas de CEP cadastradas. Os blocos 5, 6 e 7 podem entrar em versões seguintes, desde que o site não prometa o que ainda não existe.

## Estimativa grossa (1 pessoa)

| Bloco | Esforço |
|---|---|
| 0 | decisões (dias, depende de vocês) |
| 1 | 2–3 dias |
| 2 | 4–6 dias |
| 3 | 2–3 dias |
| 4 | 3–4 dias |
| 5 | 2–3 dias |
| 6 | 8–12 dias (maior risco) |
| 7 | 2–3 dias |
| 8 | 3–4 dias |
