# DIAGNÓSTICO — Limpeza Estrutural do Projeto Ovo di Onça

**Data:** 2026-10-05  
**Status:** DIAGNÓSTICO COMPLETO (SEM ALTERAÇÕES)  
**Autorização necessária:** SIM — antes de qualquer remoção/movimento

---

## 1. ESTADO ATUAL

### 1.1 Git

```
Branch: main
Commit atual: c35550c (Initial commit)
Alterações locais: nenhuma
Arquivos não rastreados: siteesistema/ (pasta)
```

### 1.2 Estrutura Atual (RAiz)

```
C:\Users\jbrun\Documents\Ovo di Onça\
├── .claude/                          ✔ Configuração do Claude Code
│   └── skills/graphify/              ✔ Skill do graphify
├── CLAUDE.md                         ✔ Instruções do projeto
├── graphify-out/                     ✔ Saída do graphify (649 KB)
└── siteesistema/                     ⚠️ PASTA NÃO RASTREADA
    ├── .git                          ⚠️ Repo Git próprio
    ├── .gitattributes
    ├── Gestão/                       ❌ PASTA VAZIA
    ├── PROMPT_EXECUCAO_BLOCOS.md     ⚠️ Doc antiga/duplicada
    ├── CHECKLIST-EXECUCAO-*          ⚠️ Doc antiga/duplicada
    ├── README.md                     ⚠️ Doc duplicada
    ├── banner.png                    ? Imagem
    ├── _tmp_20_*                     ❌ TEMP - 6 pastas vazias
    ├── _tmp_21_*                     ❌ TEMP
    ├── _tmp_32_*                     ❌ TEMP - 3 arquivos vazios
    └── sistema/                      ✔ PROJETO REAL
        ├── apps/
        │   ├── assinante/
        │   ├── gestao/
        │   └── site/
        ├── packages/
        │   ├── config/
        │   ├── database/
        │   └── ui/
        ├── Ovo di Onça Design System/ ✔ Importante, já ignorado
        ├── docs/
        ├── scripts/
        ├── .env                       ✔ Protegido
        ├── .env.example               ✔ Seguro
        ├── .gitignore                 ✔ Bem configurado
        ├── README.md                  ✔ Documentação real
        ├── CLAUDE.md                  ✔ Instruções reais
        ├── DECISOES.md                ✔ Crítico — decisões de negócio
        ├── PROGRESSO.md               ✔ Crítico — status das fases
        ├── VERIFICACAO-SEGURANCA-*    ✔ Histórico importante
        ├── CHECKLIST-EXECUCAO-*       ✔ Histórico importante
        ├── FUNCIONALIDADES-SITE.md    ✔ Documentação de negócio
        ├── node_modules/              ✔ Gerado (não rastreado)
        ├── .next/                     ✔ Gerado (não rastreado)
        ├── graphify-out/              ✔ Gerado (649 KB)
        └── pnpm-lock.yaml             ✔ Necessário
```

---

## 2. PROBLEMAS ENCONTRADOS

### 2.1 Estrutura Confusa — CRÍTICO

| Problema | Descrição | Risco | Impacto |
|---|---|---|---|
| **Dois repositórios aninhados** | Raiz tem um `.git`, `siteesistema/` tem outro `.git` próprio | ALTO | Dificulta manutenção; confunde submódulos |
| **Projeto está aninhado 2 níveis** | Estrutura real: `siteesistema/sistema/`, não na raiz | ALTO | Break em scripts, CI/CD, referências relativas |
| **Documentação duplicada** | Docs em 2 lugares; qual é a verdade? | MÉDIO | Confusão sobre o que está atualizado |
| **Pasta vazia `Gestão/`** | Sem conteúdo | BAIXO | Apenas bagunça visual |

### 2.2 Arquivos Temporários — SUSPEITOS

| Localização | Tipo | Qtd | Tamanho | Última mod | Ação |
|---|---|---|---|---|---|
| `siteesistema/_tmp_20_*` | pasta vazia | 1 | 0 | 28/09 08:26 | ❌ REMOVER |
| `siteesistema/_tmp_21_*` | pasta vazia | 3 | 0 | 28/09 08:31 | ❌ REMOVER |
| `siteesistema/_tmp_32_*` | arquivos vazios | 3 | 0 | 28/09 08:31 | ❌ REMOVER |
| `siteesistema/sistema/apps/*/..next/cache/webpack/*.old` | cache antigo | vários | desconhecido | ? | ❌ REMOVER |

**Conclusão:** São artefatos de teste/debug. Devem ter sido criados durante desenvolvimento e esquecidos.

### 2.3 Documentação Duplicada

| Arquivo | Localização | Versão | Status | Recomendação |
|---|---|---|---|---|
| `README.md` | `siteesistema/` | antiga | DESATUALIZADA | ❌ REMOVER |
| `README.md` | `siteesistema/sistema/` | atual | ATUAL | ✔ MANTER |
| `PROMPT_EXECUCAO_BLOCOS.md` | `siteesistema/` | 28/09 | HISTÓRICA | 📦 ARQUIVAR |
| `CHECKLIST-EXECUCAO-*.md` | `siteesistema/` | 29/09 | HISTÓRICA | 📦 ARQUIVAR |
| `CHECKLIST-EXECUCAO-*.md` | `siteesistema/sistema/` | 29/09 | HISTÓRICA | 📦 ARQUIVAR |

**Conclusão:** Documentação em `siteesistema/` é histórica de um processo anterior. Pode ser arquivada.

### 2.4 Arquivos Gerados (Corretamente Ignorados)

| Pasta | Tamanho | Status | Notas |
|---|---|---|---|
| `node_modules/` | 454 MB | ✔ Ignorado | Regenerado por `pnpm install` |
| `.next/` | desconhecido | ✔ Ignorado | Regenerado por build |
| `graphify-out/` | 649 KB | ✔ Monitorado | Saída do graphify; pode ser regenerada |
| `dist/`, `build/` | — | ✔ Ignorado | Vazio (nenhum executado ainda) |

---

## 3. ARQUIVOS PARA REMOVER

### 3.1 Arquivos Temporários — Baixo Risco

| Caminho | Tipo | Motivo | Evidência | Risco |
|---|---|---|---|---|
| `siteesistema/_tmp_20_3364d89b/` | pasta | Artefato de teste | Vazia, criada 28/09 08:26 | MUITO BAIXO |
| `siteesistema/_tmp_21_12d79074/` | pasta | Artefato de teste | Vazia, criada 28/09 08:11 | MUITO BAIXO |
| `siteesistema/_tmp_21_1df5aa0d/` | pasta | Artefato de teste | Vazia, criada 28/09 08:31 | MUITO BAIXO |
| `siteesistema/_tmp_21_26f2bfb7/` | pasta | Artefato de teste | Vazia, criada 28/09 08:12 | MUITO BAIXO |
| `siteesistema/_tmp_32_48cfa458ce6f26aa6418b339924e8097` | arquivo | Artefato de teste | Vazio, criado 28/09 08:12 | MUITO BAIXO |
| `siteesistema/_tmp_32_ed30bc5a59d697e1642ac354f99cfa8e` | arquivo | Artefato de teste | Vazio, criado 28/09 08:31 | MUITO BAIXO |
| `siteesistema/_tmp_32_fe97edd60bb350ee02bbecee33938d79` | arquivo | Artefato de teste | Vazio, criado 28/09 08:26 | MUITO BAIXO |

### 3.2 Documentação Histórica — Baixo Risco

| Caminho | Tipo | Motivo | Evidência | Risco |
|---|---|---|---|---|
| `siteesistema/README.md` | arquivo | Duplicada, versão antiga | Data: 24/09. Raiz real tem versão atualizada em 30/09 | BAIXO |
| `siteesistema/PROMPT_EXECUCAO_BLOCOS.md` | arquivo | Documentação histórica de um processo anterior | Refere-se a "Fase 0 → Fase 1" como futuro; hoje estamos em Fase 8–9 | BAIXO |
| `siteesistema/CHECKLIST-EXECUCAO-20260929.md` | arquivo | Histórico de execução anterior | Data: 29/09. PROGRESSO.md + DECISOES.md substituem | BAIXO |
| `siteesistema/Gestão/` | pasta | Vazia, sem purpose | Não contém nada | MUITO BAIXO |

### 3.3 Arquivos de Cache — Risco Mínimo

| Caminho | Tipo | Motivo | Evidência | Risco |
|---|---|---|---|---|
| `siteesistema/sistema/apps/*/..next/cache/webpack/*.old` | arquivo | Artefatos de cache antigos | Nome `.old`, gerados durante build | MUITO BAIXO |

---

## 4. ARQUIVOS PARA MOVER

### 4.1 Projeto Fora do Lugar — CRÍTICO

| Origem | Destino | Motivo | Risco | Ação |
|---|---|---|---|---|
| `siteesistema/sistema/` | `./` (raiz) | Projeto está aninhado desnecessariamente. Deve estar na raiz | CRÍTICO | Mover toda a estrutura. Preservar `.git` da raiz |

**Detalhes:**

Atualmente:
```
Ovo di Onça/
└── siteesistema/
    ├── .git (repo próprio — DELETAR)
    ├── sistema/
    │   ├── .git (repo real — PRESERVAR)
    │   ├── apps/, packages/, docs/
    │   ├── DECISOES.md, PROGRESSO.md, etc.
    │   └── ...
```

Deveria ser:
```
Ovo di Onça/
├── .git (repo único)
├── CLAUDE.md
├── .claude/
├── graphify-out/
├── apps/, packages/, docs/
├── Ovo di Onça Design System/
├── DECISOES.md, PROGRESSO.md, etc.
└── ...
```

---

## 5. ARQUIVOS DUPLICADOS

| Arquivo | Localização A | Localização B | Conteúdo | Recomendação |
|---|---|---|---|---|
| `README.md` | `siteesistema/` | `siteesistema/sistema/` | DIFERENTE — versão A é antiga | Manter B, deletar A |
| `CHECKLIST-EXECUCAO-20260929.md` | `siteesistema/` | `siteesistema/sistema/` | MESMO — cópia | Manter apenas em `sistema/` |

---

## 6. ARQUIVOS SUSPEITOS (Sem Verdade Certa)

| Arquivo | Localização | Dúvida | O que confirmar | Ação recomendada |
|---|---|---|---|---|
| `siteesistema/banner.png` | `siteesistema/` | Pertence ao projeto? Qual versão? | Comparar com `siteesistema/sistema` se houver lá | REVISAR ANTES DE DELETAR |
| `siteesistema/.gitattributes` | `siteesistema/` | Necessário? Duplicado? | Comparar com `siteesistema/sistema/.gitattributes` | REVISAR |
| `siteesistema/.npmrc` | `siteesistema/` | Duplicado do projeto real? | Verificar se é necessário | REVISAR |

---

## 7. DOCUMENTAÇÃO — Classificação

### 7.1 DOCUMENTAÇÃO CRÍTICA — MANTER EM LOCAL ÚNICO

| Arquivo | Localização | Status | Motivo |
|---|---|---|---|
| `DECISOES.md` | `siteesistema/sistema/` | ✔ MANTER | Fonte de verdade de regras de negócio |
| `PROGRESSO.md` | `siteesistema/sistema/` | ✔ MANTER | Status atual das Fases |
| `README.md` | `siteesistema/sistema/` | ✔ MANTER | Instruções de setup e estrutura |
| `CLAUDE.md` | `siteesistema/sistema/` | ✔ MANTER | Guia técnico do projeto |
| `FUNCIONALIDADES-SITE.md` | `siteesistema/sistema/` | ✔ MANTER | Especificação de negócio |
| `VERIFICACAO-SEGURANCA-FASE7-*.md` | `siteesistema/sistema/` | ✔ MANTER | Histórico de verificações |

### 7.2 DOCUMENTAÇÃO HISTÓRICA — PODE SER ARQUIVADA

| Arquivo | Localização | Status | Motivo | Ação |
|---|---|---|---|---|
| `PROMPT_EXECUCAO_BLOCOS.md` | `siteesistema/` | 📦 HISTÓRICA | Refere-se a processo anterior (Fase 0→1, hoje Fase 8–9) | ARQUIVAR em `docs/historico/` ou deletar |
| `CHECKLIST-EXECUCAO-*.md` | ambas | 📦 HISTÓRICA | Registros de execução passada | Manter apenas versão mais recente em `sistema/` |

### 7.3 DOCUMENTAÇÃO NA PASTA `docs/`

```
docs/
├── CODEBASE_MAP.md          ✔ Mapa da base (atualizado Fase 8)
├── DIAGNOSTICO-20260930.md  ? Investigar se está obsoleto
└── REGRAS-DE-NEGOCIO-20260930.md ? Investigar se está obsoleto
```

**Ação necessária:** Verificar se `DIAGNOSTICO-*.md` e `REGRAS-*.md` duplicam informação de `DECISOES.md` ou se são complementares.

---

## 8. TESTES E SCRIPTS — TODOS LEGÍTIMOS

| Localização | Tipo | Status | Evidência |
|---|---|---|---|
| `apps/assinante/tests/` | testes SQL | ✔ MANTER | Fazem parte do projeto (banco-teste, cache-publico, seguranca, whatsapp) |
| `packages/database/tests/` | testes SQL estruturais | ✔ MANTER | Críticos para garantir integridade do banco (teste-fase*.sql) |
| `packages/database/scripts/` | scripts de setup | ✔ MANTER | Necessários para rodar o banco de testes |

---

## 9. CONFIGURAÇÕES — TODAS NECESSÁRIAS

| Arquivo | Status | Motivo |
|---|---|---|
| `.gitignore` (em `sistema/`) | ✔ BEM CONFIGURADO | Bloqueia `.env*` corretamente, libera `.env.example` |
| `.env` | ✔ PROTEGIDO | Ignorado pelo Git |
| `.env.example` | ✔ SEGURO | Permite documentar padrão sem expor secrets |
| `.npmrc` | ✔ NECESSÁRIO | Configuração do pnpm |
| `.gitattributes` | ✔ MANTER | Preserva normalização de linha |
| `pnpm-workspace.yaml` | ✔ NECESSÁRIO | Define monorepo |
| `tsconfig.base.json` | ✔ NECESSÁRIO | Configuração TypeScript |

---

## 10. DEPENDÊNCIAS — SEM SUSPEITAS

| Categoria | Status |
|---|---|
| `package.json` raiz | ✔ Bem estruturado (scripts de test, build, lint, seguranca) |
| Dependências em `apps/` | ✔ Padrão (Next.js, React, TypeScript) |
| Dependências em `packages/` | ✔ Apropriadas (database, config, ui) |
| `pnpm-lock.yaml` | ✔ Preservar — lockfile crítico |

---

## 11. MIGRATIONS E BANCO

| Verificação | Status | Detalhes |
|---|---|---|
| Migrations aplicadas | ✔ SEGURAS | 12 migrations em `packages/database/migrations/` |
| Histórico | ✔ CRÍTICO | Nada de `cascade`; tudo `restrict` |
| Testes SQL | ✔ EXISTEM | Suites completas para cada fase |
| Scripts de teste | ✔ EXISTEM | `banco-teste.mjs`, `limpar-dados-teste.sql`, etc. |

**Ação:** NÃO TOCAR — migrations são históricas e críticas.

---

## 12. DESIGN SYSTEM

| Pasta | Tamanho | Status | Necessidade |
|---|---|---|---|
| `Ovo di Onça Design System/` | 85 MB | ✔ Ignorado em `.gitignore` | Referência visual/técnica; não utilizado direto pelos apps |

**Conclusão:** Mantém aí mesmo. Já ignorado do Git.

---

## 13. GRAPHIFY

| Item | Status | Ação |
|---|---|---|
| `graphify-out/graph.json` | ✔ Existe | Regenerável com `graphify update .` |
| `graphify-out/GRAPH_REPORT.md` | ✔ Existe | Regenerável |
| `graphify-out/cache/` | ✔ Cache | Pode ser deletado e regenerado |
| `.claude/skills/graphify/` | ✔ Skill | Manter |

---

## 14. RAIZ DO PROJETO — ANÁLISE

### Atual

```
Ovo di Onça/
├── .claude/                    ✔ Config — MANTER
├── CLAUDE.md                   ✔ Docs — MANTER
├── graphify-out/               ✔ Gerado — OK como está
└── siteesistema/               ❌ ESTRUTURA ERRADA
```

### Recomendado (após limpeza)

```
Ovo di Onça/
├── .claude/                    ✔ Config
├── CLAUDE.md                   ✔ Docs
├── graphify-out/               ✔ Gerado
├── apps/                       ✔ Projeto (vem de siteesistema/sistema/apps/)
├── packages/                   ✔ Projeto
├── docs/                       ✔ Projeto
├── Ovo di Onça Design System/  ✔ Referência
├── scripts/                    ✔ Projeto
├── .env                        ✔ Variáveis (não rastreado)
├── .env.example                ✔ Template
├── .gitignore                  ✔ Regras de ignora
├── README.md                   ✔ Docs
├── DECISOES.md                 ✔ Decisões críticas
├── PROGRESSO.md                ✔ Status
├── package.json                ✔ Monorepo root
└── pnpm-lock.yaml              ✔ Lockfile
```

---

## 15. CLASSIFICAÇÃO FINAL DOS ARQUIVOS

### A — MANTER (Críticos ou Necessários)

- `siteesistema/sistema/` **→ Trazer para raiz**
- `apps/`, `packages/`, `docs/` (em `sistema/`)
- Todas as migrations
- Todos os testes
- `DECISOES.md`, `PROGRESSO.md`, `README.md`, `CLAUDE.md`
- `.env.example`, `.gitignore`, `pnpm-workspace.yaml`
- `.claude/skills/graphify/`
- `Ovo di Onça Design System/`

### B — MOVER

- `siteesistema/sistema/*` → mover para raiz

### C — ARQUIVAR (Histórico)

- `siteesistema/PROMPT_EXECUCAO_BLOCOS.md` → `docs/historico/`
- `siteesistema/CHECKLIST-EXECUCAO-*.md` → `docs/historico/`

### D — REMOVER (Desnecessários)

- `siteesistema/_tmp_20_*` (6 pastas vazias)
- `siteesistema/_tmp_21_*` (3 pastas vazias)
- `siteesistema/_tmp_32_*` (3 arquivos vazios)
- `siteesistema/Gestão/` (pasta vazia)
- `siteesistema/.git` (repo próprio — manter `.git` da raiz)
- `siteesistema/README.md` (versão antiga)
- Arquivos `.old` em `.next/cache/webpack/`

### E — REVISAR (Incerteza)

- `siteesistema/banner.png` - confirmar se duplica
- `siteesistema/.gitattributes` - confirmar necessidade
- `siteesistema/.npmrc` - confirmar duplicação
- `docs/DIAGNOSTICO-20260930.md` - confirmar se está obsoleto
- `docs/REGRAS-DE-NEGOCIO-20260930.md` - confirmar se duplica DECISOES.md

### F — NÃO TOCAR (Críticos/Sensíveis)

- Todas as migrations em `packages/database/migrations/`
- `pnpm-lock.yaml` (lockfile)
- `.env` (secrets)
- `siteesistema/sistema/.git` (histórico importante)

---

## 16. RISCOS IDENTIFICADOS

| Risco | Severidade | Como mitigar |
|---|---|---|
| **Estrutura aninhada confunde build/deploy scripts** | CRÍTICO | Mover projeto para raiz; atualizar paths em CI/CD |
| **Dois `.git` podem confundir git commands** | CRÍTICO | Deletar `.git` de `siteesistema/` com cuidado |
| **Documentação duplicada causa desatualização** | MÉDIO | Manter uma única fonte (em `sistema/`) |
| **Arquivos temporários deixam bagunça** | BAIXO | Deletar — sem impacto no funcionamento |
| **`.env` ou secrets ficarem expostos** | CRÍTICO | Verificar `.gitignore` antes (já feito — OK) |

---

## 17. PLANO DE AÇÃO (ORDEM)

### Fase 1: Preparação (SEM ALTERAR NADA)

- ✔ Backup do repositório (localmente, `git clone`)
- ✔ Listar todos os arquivos a remover (feito neste diagnóstico)
- ✔ Você aprova este relatório

### Fase 2: Movimentação (COM CUIDADO)

1. **Mover o projeto para a raiz**
   - Copiar conteúdo de `siteesistema/sistema/*` para raiz
   - Preservar `.git` original (não o de `siteesistema/`)
   - Atualizar referências em scripts/docs

2. **Remover estrutura antiga**
   - Deletar `siteesistema/` inteira com seu `.git` próprio
   - Commitr `"Remove nested project folder"`

### Fase 3: Limpeza (REMOÇÕES)

1. Remover todos `_tmp_*`
2. Remover documentação duplicada
3. Remover arquivos `.old` de cache
4. Remover `Gestão/` se confirmado vazio
5. Commitr `"Clean up temporary and stale files"`

### Fase 4: Arquivo Histórico (OPCIONAL)

1. Criar `docs/historico/`
2. Mover documentação histórica
3. Commitr `"Archive historical documentation"`

### Fase 5: Validação

- `git status` — sem surpresas
- `pnpm install` — sem erros
- `pnpm lint` — sem erros
- `pnpm typecheck` — sem erros
- `pnpm test` — sem erros

---

## 18. RESUMO PARA APROVAÇÃO

### Será Removido:

```
❌ siteesistema/_tmp_20_3364d89b/
❌ siteesistema/_tmp_21_12d79074/
❌ siteesistema/_tmp_21_1df5aa0d/
❌ siteesistema/_tmp_21_26f2bfb7/
❌ siteesistema/_tmp_32_48cfa458ce6f26aa6418b339924e8097
❌ siteesistema/_tmp_32_ed30bc5a59d697e1642ac354f99cfa8e
❌ siteesistema/_tmp_32_fe97edd60bb350ee02bbecee33938d79
❌ siteesistema/Gestão/
❌ siteesistema/README.md
❌ siteesistema/.git (repo próprio)
❌ apps/*/..next/cache/webpack/*.old
```

### Será Movido:

```
→ siteesistema/sistema/* para raiz
```

### Será Mantido:

```
✔ Toda a estrutura em siteesistema/sistema/
✔ Todas as migrations
✔ Todos os testes
✔ Toda documentação crítica
✔ Design System
✔ Scripts
```

### Será Arquivado (Opcional):

```
📦 siteesistema/PROMPT_EXECUCAO_BLOCOS.md → docs/historico/
📦 siteesistema/CHECKLIST-EXECUCAO-*.md → docs/historico/
```

---

## 19. PRÓXIMOS PASSOS

1. **Revise este diagnóstico**
2. **Confirme as ações**
3. **Responda:**
   - Aprova remover os `_tmp_*`?
   - Aprova mover o projeto para raiz?
   - Aprova arquivar documentação histórica?
   - Quer revisão adicional de arquivos específicos?

Após aprovação, executarei a limpeza em etapas cuidadosas, com verificação após cada passo.

---

**Diagnóstico feito por:** Claude Haiku 4.5  
**Data:** 2026-10-05  
**Status:** PRONTO PARA REVISÃO
