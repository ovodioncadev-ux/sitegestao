# Graph Report - sistema  (2026-10-02)

## Corpus Check
- Large corpus: 319 files · ~3,252,313 words. Semantic extraction will be expensive (many Claude tokens). Consider running on a subfolder.

## Summary
- 1209 nodes · 2472 edges · 86 communities (47 shown, 39 thin omitted)
- Extraction: 92% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 185 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- area-de-entrega/page.tsx / AreaDeEntrega
- app/acoes.ts / atualizarMeusDados() / so
- acoes-painel.ts / Resultado / rodarRotin
- whatsapp.test.ts / arquivos() / codigo /
- form-cadastro.tsx / FormCadastro() / aoE
- CODEBASE_MAP.md (mapa da base de código)
- assinante/eslint.config.mjs / compat / a
- assinante/package.json / dependencies / 
- gestao/package.json / dependencies / bet
- site/package.json / dependencies / next 
- assinante/src/app/api/auth/[...all]/rout
- _ds_bundle.js / AttentionRow() / Avatar(
- package.json / devDependencies / typescr
- Avatar.jsx / Avatar() / sizes / Badge.js
- D13: selo do semanal 'Recomendado' / D15
- Badge.d.ts / BadgeProps / Button.d.ts / 
- Avatar component / BottomNav component /
- Icon() / Tag.jsx / Tag() / DataTable.jsx
- scripts / db:limpar-teste / db:migrar / 
- Reference visual style: bold uppercase h
- pt-BR localization and egg-business doma
- tsconfig.base.json / compilerOptions / e
- GET /api/plans / apps/assinante (API + p
- Decisao: dois dourados (#e67e22 acao, #d
- database/package.json / better-auth / do
- IconButton.jsx / box / IconButton() / Ba
- Roomify case study: visual evolution and
- GET /api/neighborhoods / POST /api/subsc
- assinante/tsconfig.json / compilerOption
- CheckoutModal.tsx / verificar-segredos.s
- gestao/tsconfig.json / compilerOptions /
- site/tsconfig.json / compilerOptions / a
- D12: WhatsApp (31) 2516-7561, fonte unic
- config/package.json / exports / ./header
- exports / ./acesso / ./auth / ./auth-cli
- D10: entregas presas ao calendario (sema
- Mustard/golden yellow brand color (logo)
- devDependencies / dotenv / next / node-p
- ui/package.json / exports / ./tokens.css
- Better Auth / Auditoria imutavel (gatilh
- Button.jsx / Button() / hovers / sizes
- database/tsconfig.json / exclude / exten
- CLAUDE.md (Claude Code Guide for Ovo di 
- Ovo di Onça stacked wordmark (egg-shaped
- Icon.d.ts / IconName / IconProps
- BarChart.d.ts / BarChartProps / BarDatum
- DataTable.d.ts / DataColumn / DataTableP
- Input.jsx / heights / Input()
- Select.d.ts / SelectOption / SelectProps
- Tabs.d.ts / TabItem / TabsProps
- DashboardScreen.jsx / AttentionRow() / D
- dependencies / better-auth / pg
- Fase 9 (cobranca, pausa, reposicao, roti
- Roomify case study: AI search and web-to
- assinante/postcss.config.mjs / config
- gestao/postcss.config.mjs / config
- site/postcss.config.mjs / config
- Avatar.d.ts / AvatarProps
- Card.d.ts / CardProps
- Tooltip.d.ts / TooltipProps
- ProgressBar.d.ts / ProgressBarProps
- Trend.d.ts / TrendProps
- Banner.d.ts / BannerProps
- Dialog.d.ts / DialogProps
- Toast.d.ts / ToastProps
- Checkbox.d.ts / CheckboxProps
- Radio.d.ts / RadioProps
- SearchField.d.ts / SearchFieldProps
- Switch.d.ts / SwitchProps
- Pagination.d.ts / PaginationProps
- TopBar.d.ts / TopBarProps
- headers.d.mts / Opcoes
- BottomNav component / Pagination compone
- WHATSAPP_E164
- WHATSAPP_EXIBICAO
- WHATSAPP_URL
- Corner radii scale

## God Nodes (most connected - your core abstractions)
1. `comoDono()` - 40 edges
2. `rodar()` - 37 edges
3. `comoUsuario()` - 36 edges
4. `campo()` - 34 edges
5. `Icon()` - 33 edges
6. `uuid()` - 30 edges
7. `Pagina()` - 24 edges
8. `exigirDono()` - 24 edges
9. `SemPermissao()` - 23 edges
10. `ErroNegocio` - 22 edges

## Surprising Connections (you probably didn't know these)
- `UI kit Painel administrativo README` --semantically_similar_to--> `apps/gestao (painel do dono)`  [INFERRED] [semantically similar]
  Ovo di Onça Design System/ui_kits/admin/README.md → docs/CODEBASE_MAP.md
- `Modelo de autorização app_anon/app_usuario + RLS` --semantically_similar_to--> `Segurança em camadas (middleware, sessão, papel, RLS, função SQL)`  [INFERRED] [semantically similar]
  README.md → docs/CODEBASE_MAP.md
- `packages/ui (@ovo/ui tokens)` --ambiguous_placeholder--> `Ovo di Onça Design System README`  [AMBIGUOUS]
  docs/CODEBASE_MAP.md → Ovo di Onça Design System/readme.md
- `Decisões de negócio pendentes` --conceptually_related_to--> `Fechamento das regras de negócio 30/09/2026`  [INFERRED]
  PROGRESSO.md → docs/REGRAS-DE-NEGOCIO-20260930.md
- `pnpm-workspace.yaml (apps/*, packages/*)` --references--> `packages/database (@ovo/database)`  [INFERRED]
  pnpm-workspace.yaml → docs/CODEBASE_MAP.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Brand colour hierarchy (brown structures, gold acts, olive supports)** — siteesistema_sistema_ovo_di_on_a_design_system_guidelines_color_brown_brown, siteesistema_sistema_ovo_di_on_a_design_system_guidelines_color_brand_gold, siteesistema_sistema_ovo_di_on_a_design_system_guidelines_color_olive_olive [EXTRACTED 1.00]
- **Design system core components** — siteesistema_sistema_ovo_di_on_a_design_system_components_core_button, siteesistema_sistema_ovo_di_on_a_design_system_components_core_iconbutton, siteesistema_sistema_ovo_di_on_a_design_system_components_core_badge, siteesistema_sistema_ovo_di_on_a_design_system_components_core_tag, siteesistema_sistema_ovo_di_on_a_design_system_components_core_avatar, siteesistema_sistema_ovo_di_on_a_design_system_components_core_card, siteesistema_sistema_ovo_di_on_a_design_system_components_core_tooltip, siteesistema_sistema_ovo_di_on_a_design_system_components_core_icon [EXTRACTED 1.00]
- **Typography guideline cards** — siteesistema_sistema_ovo_di_on_a_design_system_guidelines_type_display, siteesistema_sistema_ovo_di_on_a_design_system_guidelines_type_body, siteesistema_sistema_ovo_di_on_a_design_system_guidelines_type_numeric, siteesistema_sistema_ovo_di_on_a_design_system_guidelines_type_scale [EXTRACTED 1.00]
- **Monorepo apps and shared packages** — siteesistema_sistema_docs_codebase_map_apps_assinante, siteesistema_sistema_docs_codebase_map_apps_gestao, siteesistema_sistema_docs_codebase_map_apps_site, siteesistema_sistema_docs_codebase_map_packages_database, siteesistema_sistema_docs_codebase_map_packages_ui, siteesistema_sistema_docs_codebase_map_packages_config [EXTRACTED 1.00]
- **Navigation component set** — siteesistema_sistema_ovo_di_on_a_design_system_components_navigation_sidebar_prompt_sidebar, siteesistema_sistema_ovo_di_on_a_design_system_components_navigation_tabs_prompt_tabs, siteesistema_sistema_ovo_di_on_a_design_system_components_navigation_topbar_prompt_topbar, siteesistema_sistema_ovo_di_on_a_design_system_components_navigation_navigation_card_bottomnav, siteesistema_sistema_ovo_di_on_a_design_system_components_navigation_navigation_card_pagination [EXTRACTED 1.00]
- **Ovo di Onça logo color variants** — siteesistema_sistema_ovo_di_onca_design_system_assets_logo_ovo_di_onca_brown, siteesistema_sistema_ovo_di_onca_design_system_assets_logo_ovo_di_onca_cream, siteesistema_sistema_ovo_di_onca_design_system_assets_logo_ovo_di_onca [EXTRACTED 1.00]
- **Pending billing lifecycle rule decisions** — siteesistema_sistema_docs_regras_de_negocio_20260930_pausa_extensao_do_ciclo, siteesistema_sistema_docs_regras_de_negocio_20260930_troca_de_plano_proximo_periodo, siteesistema_sistema_docs_regras_de_negocio_20260930_primeira_entrega_apos_pagamento, siteesistema_sistema_docs_regras_de_negocio_20260930_cancelamento_fim_do_periodo, siteesistema_sistema_docs_regras_de_negocio_20260930_inadimplencia [EXTRACTED 1.00]
- **Landing page sections of apps/site** — site_navbar, site_hero, site_plans_section, site_comparison_table, site_neighborhood_section, site_faq_section, site_footer [EXTRACTED 1.00]
- **CI security pipeline (secret scan, audit, depcheck)** — siteesistema_sistema_github_workflows_ci_job_seguranca, scripts_verificar_segredos, siteesistema_sistema_checklist_execucao_20260929_git_secrets_audit [INFERRED 0.75]
- **Data display components** — siteesistema_sistema_ovo_di_on_a_design_system_components_data_statcard, siteesistema_sistema_ovo_di_on_a_design_system_components_data_trend, siteesistema_sistema_ovo_di_on_a_design_system_components_data_progressbar [INFERRED 0.85]
- **Feedback components family** — siteesistema_sistema_ovo_di_on_a_design_system_components_feedback_banner, siteesistema_sistema_ovo_di_on_a_design_system_components_feedback_toast, siteesistema_sistema_ovo_di_on_a_design_system_components_feedback_dialog, siteesistema_sistema_ovo_di_on_a_design_system_components_feedback_emptystate [INFERRED 0.85]
- **Form controls family** — siteesistema_sistema_ovo_di_on_a_design_system_components_forms_input, siteesistema_sistema_ovo_di_on_a_design_system_components_forms_select, siteesistema_sistema_ovo_di_on_a_design_system_components_forms_checkbox, siteesistema_sistema_ovo_di_on_a_design_system_components_forms_radio, siteesistema_sistema_ovo_di_on_a_design_system_components_forms_switch, siteesistema_sistema_ovo_di_on_a_design_system_components_forms_searchfield [INFERRED 0.85]
- **Roomify redesign case study sections** — siteesistema_sistema_ovo_di_on_a_design_system_uploads_imagem_06_new_visual_language, siteesistema_sistema_ovo_di_on_a_design_system_uploads_imagem_07_two_step_product_creation, siteesistema_sistema_ovo_di_on_a_design_system_uploads_imagem_08_dashboard_workspace, siteesistema_sistema_ovo_di_on_a_design_system_uploads_imagem_10_ai_search [INFERRED 0.85]
- **Roomify research-to-design flow** — roomify_user_survey, roomify_usability_testing, roomify_core_workflows, roomify_updated_information_architecture [INFERRED 0.85]
- **Vivid signal colours system** — siteesistema_sistema_ovo_di_on_a_design_system_guidelines_color_semantic_semantic, siteesistema_sistema_ovo_di_on_a_design_system_guidelines_color_data_data, siteesistema_sistema_ovo_di_on_a_design_system_guidelines_color_indicators_indicators [INFERRED 0.85]
- **Roomify case study design references** — siteesistema_sistema_ovo_di_onca_design_system_references_case_study_02, siteesistema_sistema_ovo_di_onca_design_system_references_case_study_05, siteesistema_sistema_ovo_di_onca_design_system_references_case_study_10 [INFERRED 0.95]

## Communities (86 total, 39 thin omitted)

### Community 0 - "area-de-entrega/page.tsx / AreaDeEntrega"
Cohesion: 0.06
Nodes (92): AreaDeEntrega(), Faixa, Assinatura, DetalheAssinatura(), EntregaLinha, FaturaLinha, ReposicaoLinha, Assinaturas() (+84 more)

### Community 1 - "app/acoes.ts / atualizarMeusDados() / so"
Cohesion: 0.06
Nodes (69): atualizarMeusDados(), solicitarAlteracao(), dynamic, GET(), dynamic, GET(), dynamic, GET() (+61 more)

### Community 2 - "acoes-painel.ts / Resultado / rodarRotin"
Cohesion: 0.13
Nodes (66): Resultado, rodarRotinaDiaria(), alternarFaixa(), criarFaixa(), editarFaixa(), lerFaixa(), recalcularClientes(), removerFaixa() (+58 more)

### Community 3 - "whatsapp.test.ts / arquivos() / codigo /"
Cohesion: 0.06
Nodes (43): arquivos(), codigo, FONTE_UNICA, FONTE_UNICA_TIPOS, IGNORAR, RAIZ, Pagina(), COMPARISON_ROWS (+35 more)

### Community 4 - "form-cadastro.tsx / FormCadastro() / aoE"
Cohesion: 0.07
Nodes (22): FormCadastro(), Busca, Cadastro(), SairBotao(), FormEntrar(), Busca, Entrar(), metadata (+14 more)

### Community 5 - "CODEBASE_MAP.md (mapa da base de código)"
Cohesion: 0.06
Nodes (44): CODEBASE_MAP.md (mapa da base de código), apps/assinante (portal e API pública), apps/gestao (painel do dono), apps/site (landing page SPA), Better Auth, Fluxo de assinatura pelo site (fase 8), packages/config (@ovo/config headers), packages/database (@ovo/database) (+36 more)

### Community 6 - "assinante/eslint.config.mjs / compat / a"
Cohesion: 0.07
Nodes (29): compat, nextConfig, compat, nextConfig, compat, nextConfig, URL_ASSINANTE, cabecalhosDeSeguranca() (+21 more)

### Community 7 - "assinante/package.json / dependencies / "
Cohesion: 0.04
Nodes (46): dependencies, better-auth, next, @ovo/database, @ovo/ui, react, react-dom, devDependencies (+38 more)

### Community 8 - "gestao/package.json / dependencies / bet"
Cohesion: 0.04
Nodes (45): dependencies, better-auth, next, @ovo/database, @ovo/ui, react, react-dom, devDependencies (+37 more)

### Community 9 - "site/package.json / dependencies / next "
Cohesion: 0.05
Nodes (41): dependencies, next, @ovo/ui, react, react-dom, devDependencies, dotenv, eslint (+33 more)

### Community 10 - "assinante/src/app/api/auth/[...all]/rout"
Cohesion: 0.09
Nodes (29): GET, POST, GET, handlers, POST(), dynamic, POST(), conexaoAdmin() (+21 more)

### Community 11 - "_ds_bundle.js / AttentionRow() / Avatar("
Cohesion: 0.18
Nodes (31): AttentionRow(), Avatar(), Badge(), Banner(), BarChart(), BatchesScreen(), Button(), Card() (+23 more)

### Community 12 - "package.json / devDependencies / typescr"
Cohesion: 0.07
Nodes (29): devDependencies, typescript, engines, node, typescript, name, glob@>=11.0.0 <11.1.0, postcss (+21 more)

### Community 13 - "Avatar.jsx / Avatar() / sizes / Badge.js"
Cohesion: 0.08
Nodes (4): sizes, Badge(), tones, surfaces

### Community 14 - "D13: selo do semanal 'Recomendado' / D15"
Cohesion: 0.11
Nodes (23): D13: selo do semanal 'Recomendado', D15: indicacao (10% indicado e indicador) e ordem dos descontos, D1: fatura do mes do calendario, vence dia 3, atrasada dia 8, D2: entregas param 20 dias apos a tolerancia, D3-D5: pausa (credito ou pentes depois, fatura reduzida, maximo 60 dias), D6: aumento de plano na hora, reducao no mes seguinte, D7: cancelamento vale no fim do mes pago, D8: 1a entrega so depois do 1o pagamento (+15 more)

### Community 15 - "Badge.d.ts / BadgeProps / Button.d.ts / "
Cohesion: 0.12
Nodes (12): BadgeProps, ButtonProps, iconPaths, IconButtonProps, TagProps, StatCardProps, EmptyStateProps, InputProps (+4 more)

### Community 16 - "Avatar component / BottomNav component /"
Cohesion: 0.13
Nodes (22): Avatar component, BottomNav component, IconButton component, Navigation design system card (sidebar, top bar, tabs), Pagination component, SearchField component, Sidebar component, Tabs component (+14 more)

### Community 17 - "Icon() / Tag.jsx / Tag() / DataTable.jsx"
Cohesion: 0.16
Nodes (11): Icon(), Tag(), DataTable(), StatCard(), Trend(), EmptyState(), Checkbox(), SearchField() (+3 more)

### Community 18 - "scripts / db:limpar-teste / db:migrar / "
Cohesion: 0.10
Nodes (21): scripts, db:limpar-teste, db:migrar, db:migrar:teste, db:papel-servidor, db:reverter, teste:autorizacao, teste:estrutura (+13 more)

### Community 19 - "Reference visual style: bold uppercase h"
Cohesion: 0.14
Nodes (18): Reference visual style: bold uppercase headings, electric blue panels, rounded cards, black/white pills, AI-assisted global search (query, AI summary, grouped results, action), Four core experience areas (product creation, navigation, premium collaboration, workspace efficiency), Double Diamond design process (Discover, Define, Develop, Deliver), Roomify platform (furniture catalog SaaS dashboard with AR), Survey results: 72% slow creation, 91% want 3D preview, 54% unclear premium, Target groups: company admin, in-house designer, independent designer, Updated information architecture (4 intent-based domains, 10 modules, 1 shared content source) (+10 more)

### Community 20 - "pt-BR localization and egg-business doma"
Cohesion: 0.18
Nodes (18): pt-BR localization and egg-business domain, Brand design tokens (cream, gold, olive, clay), Data card demo, ProgressBar component, StatCard component, Trend component, Banner component, Dialog component (+10 more)

### Community 21 - "tsconfig.base.json / compilerOptions / e"
Cohesion: 0.11
Nodes (17): compilerOptions, esModuleInterop, forceConsistentCasingInFileNames, incremental, isolatedModules, jsx, lib, module (+9 more)

### Community 22 - "GET /api/plans / apps/assinante (API + p"
Cohesion: 0.16
Nodes (14): GET /api/plans, apps/assinante (API + portal, porta 3001), apps/assinante (portal do assinante, Fase 7), apps/gestao (admin panel, porta 3000), apps/site (landing page SPA, porta 3002), Fluxo de assinatura pelo site (site -> /assinar -> /cadastro -> criar_meu_cadastro -> assinar_plano), Neon Postgres (principal e branch de teste), Ovo di Onca subscription system (+6 more)

### Community 23 - "Decisao: dois dourados (#e67e22 acao, #d"
Cohesion: 0.21
Nodes (14): Decisao: dois dourados (#e67e22 acao, #d4a437 destaque) (#18), Avatar component, Badge component (status pill), Button component, Card component, Card surfaces demo card, Core components demo card, Icon component (Lucide-derived) (+6 more)

### Community 24 - "database/package.json / better-auth / do"
Cohesion: 0.14
Nodes (13): better-auth, dotenv, next, @types/node, typescript, name, peerDependencies, next (+5 more)

### Community 25 - "IconButton.jsx / box / IconButton() / Ba"
Cohesion: 0.26
Nodes (8): box, IconButton(), Banner(), tones, Dialog(), Toast(), tones, Pagination()

### Community 26 - "Roomify case study: visual evolution and"
Cohesion: 0.18
Nodes (13): Roomify case study: visual evolution and guided sign-up, Guided sign-up flow (Account, Role, Plan) with progressive disclosure, New distinctive visual language (cobalt blue, soft surfaces, Mona Sans Expanded, vertical nav), Roomify case study: product creation redesigned workflow, Two-step product creation with always-visible 3D preview (creation time 12:00 to 7:30), Roomify case study: dashboard as operational workspace, Dashboard with quick actions, catalog performance, activity feed (adoption 65% to 78%), Roomify case study: customizable dashboard and presentation editor (+5 more)

### Community 27 - "GET /api/neighborhoods / POST /api/subsc"
Cohesion: 0.18
Nodes (12): GET /api/neighborhoods, POST /api/subscriptions, Bug: API_BASE gera /api/api em producao, Bug: lista de bairros hardcoded em dois lugares, Bug: checkout exige autenticacao mas site e anonimo (CORS), Bug: CheckoutModal envia priceCents em vez de plan.id, CheckoutModal (site), usePlanos hook (+4 more)

### Community 28 - "assinante/tsconfig.json / compilerOption"
Cohesion: 0.20
Nodes (9): compilerOptions, allowImportingTsExtensions, allowJs, paths, plugins, exclude, extends, include (+1 more)

### Community 29 - "CheckoutModal.tsx / verificar-segredos.s"
Cohesion: 0.24
Nodes (9): CheckoutModal.tsx, aviso(), pnpm seguranca / verificar-segredos (8 verificacoes), ok(), verificar-segredos.sh script, Checklist de Execucao 29/09/2026, Validacao do CheckoutModal (ja implementada), Verificacao de segredos no Git (limpo) (+1 more)

### Community 30 - "gestao/tsconfig.json / compilerOptions /"
Cohesion: 0.22
Nodes (8): compilerOptions, allowJs, paths, plugins, exclude, extends, include, ../../tsconfig.base.json

### Community 31 - "site/tsconfig.json / compilerOptions / a"
Cohesion: 0.22
Nodes (8): compilerOptions, allowJs, paths, plugins, exclude, extends, include, ../../tsconfig.base.json

### Community 32 - "D12: WhatsApp (31) 2516-7561, fonte unic"
Cohesion: 0.25
Nodes (9): D12: WhatsApp (31) 2516-7561, fonte unica, Decisao: frescor maximo de 7 dias (#11), packages/config (headers de seguranca, whatsapp), ComparisonTable, FaqSection, Footer, Hero section, Navbar (scroll-spy) (+1 more)

### Community 33 - "config/package.json / exports / ./header"
Cohesion: 0.25
Nodes (7): exports, ./headers, ./whatsapp, name, private, type, version

### Community 34 - "exports / ./acesso / ./auth / ./auth-cli"
Cohesion: 0.25
Nodes (8): exports, ./acesso, ./auth, ./auth-cliente, ./middleware, ./papel, ./rotina, ./types

### Community 35 - "D10: entregas presas ao calendario (sema"
Cohesion: 0.43
Nodes (6): D10: entregas presas ao calendario (semanal toda quarta, quinzenal 1a e 3a, mensal 1a), D9: corte segunda 18h (config_negocio), Etapa 2: calendario nas quartas (D10) e corte (D9), criar_assinatura (SQL), data_de_entrega_do_plano (SQL), primeira_quarta_apos_corte (SQL)

### Community 36 - "Mustard/golden yellow brand color (logo)"
Cohesion: 0.33
Nodes (7): Mustard/golden yellow brand color (logo), Egg-shaped O letterforms in wordmark, Roomify (furniture catalog SaaS web app), 3 strategic goals: subscription growth, operational efficiency, product adoption, Visual style: electric blue, black, white, glass cards, bold uppercase type, Roomify web app redesign case study (overview, goals), Ovo di Onça Official Logotype

### Community 37 - "devDependencies / dotenv / next / node-p"
Cohesion: 0.29
Nodes (7): devDependencies, dotenv, next, node-pg-migrate, @types/node, @types/pg, typescript

### Community 38 - "ui/package.json / exports / ./tokens.css"
Cohesion: 0.29
Nodes (6): exports, ./tokens.css, name, private, type, version

### Community 39 - "Better Auth / Auditoria imutavel (gatilh"
Cohesion: 0.40
Nodes (3): Better Auth, Auditoria imutavel (gatilho auditar()), RLS no Postgres (protecao real)

### Community 40 - "Button.jsx / Button() / hovers / sizes"
Cohesion: 0.40
Nodes (4): Button(), hovers, sizes, variants

### Community 41 - "database/tsconfig.json / exclude / exten"
Cohesion: 0.40
Nodes (4): exclude, extends, include, ../../tsconfig.base.json

### Community 42 - "CLAUDE.md (Claude Code Guide for Ovo di "
Cohesion: 0.40
Nodes (5): CLAUDE.md (Claude Code Guide for Ovo di Onca), CI workflow (GitHub Actions), CI job: Segredos e dependencias, CI job: TypeScript (typecheck + test), Ovo di Onca Design System skill

### Community 43 - "Ovo di Onça stacked wordmark (egg-shaped"
Cohesion: 0.67
Nodes (4): Ovo di Onça stacked wordmark (egg-shaped O's, serif OVO over 'di Onça'), Logo Ovo di Onça (golden yellow variant), Logo Ovo di Onça (brown variant), Logo Ovo di Onça (cream variant)

### Community 51 - "dependencies / better-auth / pg"
Cohesion: 0.67
Nodes (3): dependencies, better-auth, pg

### Community 52 - "Fase 9 (cobranca, pausa, reposicao, roti"
Cohesion: 1.00
Nodes (3): Fase 9 (cobranca, pausa, reposicao, rotina diaria), gerar_cobranca (SQL), processar_rotina_diaria (SQL)

### Community 53 - "Roomify case study: AI search and web-to"
Cohesion: 0.67
Nodes (3): Roomify case study: AI search and web-to-AR sync, AI-assisted global search across products, catalogs, materials, clients, Manage on web, sync, experience in mobile AR

## Ambiguous Edges - Review These
- `Ovo di Onça Design System README` → `packages/ui (@ovo/ui tokens)`  [AMBIGUOUS]
  docs/CODEBASE_MAP.md · relation: ambiguous_placeholder
- `Mustard/golden yellow brand color (logo)` → `Visual style: electric blue, black, white, glass cards, bold uppercase type`  [AMBIGUOUS]
  Ovo di Onça Design System/uploads/imagem-01.png · relation: semantically_similar_to

## Knowledge Gaps
- **477 isolated node(s):** `AvatarProps`, `sizes`, `BadgeProps`, `tones`, `ButtonProps` (+472 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 550 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **39 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Ovo di Onça Design System README` and `packages/ui (@ovo/ui tokens)`?**
  _Edge tagged AMBIGUOUS (relation: ambiguous_placeholder) - confidence is low._
- **What is the exact relationship between `Mustard/golden yellow brand color (logo)` and `Visual style: electric blue, black, white, glass cards, bold uppercase type`?**
  _Edge tagged AMBIGUOUS (relation: semantically_similar_to) - confidence is low._
- **Why does `pg` connect `assinante/eslint.config.mjs / compat / a` to `database/package.json / better-auth / do`, `assinante/src/app/api/auth/[...all]/rout`?**
  _High betweenness centrality (0.044) - this node is a cross-community bridge._
- **Why does `scripts` connect `scripts / db:limpar-teste / db:migrar / ` to `database/package.json / better-auth / do`?**
  _High betweenness centrality (0.024) - this node is a cross-community bridge._
- **Why does `comoUsuario()` connect `area-de-entrega/page.tsx / AreaDeEntrega` to `app/acoes.ts / atualizarMeusDados() / so`, `assinante/src/app/api/auth/[...all]/rout`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._
- **What connects `AvatarProps`, `sizes`, `BadgeProps` to the rest of the system?**
  _477 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `area-de-entrega/page.tsx / AreaDeEntrega` be split into smaller, more focused modules?**
  _Cohesion score 0.058355437665782495 - nodes in this community are weakly interconnected._