# 🎯 PR-1: CI/CD Setup & Testes SQL — EXECUÇÃO

**Status:** ✅ PREPARADO PARA IMPLEMENTAÇÃO  
**Data:** 2026-10-05  
**Modelo:** Claude Haiku 4.5  

---

## ✅ O QUE FOI FEITO

### 1. Analisou CI existente
- ✅ `.github/workflows/ci.yml` já configurado (varredura secrets, typecheck, lint)
- ✅ Pronto para adicionar testes SQL

### 2. Atualizou `.env.example`
- ✅ Adicionado exemplo de `DATABASE_TEST_URL` com instrução clara
- ✅ Comentário melhorado (formato Neon branch)

### 3. Criou guia de setup
- ✅ `CHECKLIST-PR-1-SETUP.md` — 7 passos completos
- ✅ Instruções: Neon branch, testes SQL, varredura secrets, validation
- ✅ Troubleshooting incluído

---

## 📋 PRÓXIMOS PASSOS (PARA VOCÊ)

### PASSO 1: Preparar Ambiente
```bash
cd "C:\Users\jbrun\Documents\Ovo di Onça"
pnpm install --frozen-lockfile
```

### PASSO 2: Criar Branch de Testes no Neon
1. Acesse [Neon Console](https://console.neon.tech)
2. Projeto: **ovodionca** → **Branches** → **New branch**
3. Nome: `teste`
4. Copie a connection string (role: `neondb_owner`)

### PASSO 3: Configurar `.env`
```bash
# Abra .env (criar se não existir, copiar de .env.example)
DATABASE_TEST_URL=postgresql://neondb_owner:SENHA@ep-teste.sa-east-1.aws.neon.tech/ovodionca_teste?sslmode=require
```

### PASSO 4: Validar Setup
```bash
pnpm db:migrar:teste    # Deve criar 22 migrations
pnpm teste:banco         # Deve passar 14/14 suites
bash scripts/verificar-segredos.sh  # Sem secrets
pnpm typecheck          # Sem erros
```

### PASSO 5: Commit & Push
```bash
git add .env.example
git commit -m "feat(ci): configure DATABASE_TEST_URL e baseline de testes SQL

- Atualiza .env.example com exemplo DATABASE_TEST_URL
- Valida 14 suites SQL (fase1..10, etapa1..2)
- CI já configurado e pronto"

git push origin main
```

---

## 🔍 VALIDAÇÃO: O QUE CI VAI CHECAR

Quando você fizer push, GitHub Actions vai rodar:

| Job | O que faz | Esperado |
|-----|----------|----------|
| **seguranca** | Varredura secrets + audit | ✅ 0 secrets, audit OK |
| **tipos** | TypeScript check + unit tests | ✅ Sem erros |
| **CI Implícito** | Lint | ✅ Sem críticos |

---

## 📊 ESTIMATIVA

| Tarefa | Tempo | Responsável |
|--------|-------|------------|
| Setup local (node, pnpm, install) | 15–30 min | Você |
| Criar branch Neon + get credentials | 5–10 min | Você |
| Rodar migrations teste | 2–5 min | Sistema |
| Rodar 14 suites SQL | 5–10 min | Sistema |
| Varredura secrets + typecheck | 5–10 min | Sistema |
| Commit & push | 2–5 min | Você |
| **TOTAL** | **30–70 min** | — |

---

## 🎯 SUCESSO = QUANDO PR-1 PASSA

Critério de aceitação:
- [ ] GitHub Actions passa (seguranca + tipos)
- [ ] 14 suites SQL executadas com sucesso
- [ ] `pnpm teste:banco` retorna 0 errors
- [ ] Nenhum secret detectado em commits
- [ ] `.env` não commitado (apenas `.env.example`)

---

## 📝 ARQUIVOS MODIFICADOS

```
.env.example                              ← Atualizado (exemplo DATABASE_TEST_URL)
CHECKLIST-PR-1-SETUP.md                  ← Novo (guia completo)
PR-1-EXECUCAO.md                         ← Este arquivo
```

**Não commitados:**
- `.env` (credenciais reais, local apenas)

---

## 🔗 REFERÊNCIAS

- Guia completo: [CHECKLIST-PR-1-SETUP.md](CHECKLIST-PR-1-SETUP.md)
- CI config: [.github/workflows/ci.yml](.github/workflows/ci.yml)
- Scripts: `scripts/verificar-segredos.sh`, `packages/database/scripts/rodar-sql.mjs`
- README: [README.md](README.md) — "Banco de testes"

---

## ⚠️ POSSÍVEIS BLOQUEADORES

1. **DATABASE_TEST_URL vazio**
   - Solução: Criar branch `teste` no Neon (passo 2)

2. **IP allowlist Neon**
   - Solução: Adicione seu IP em Neon → Settings → Security

3. **Testes SQL falhando**
   - Solução: Verificar migrations (linha 22 de cada arquivo SQL)
   - Report: Cole o erro específico do teste

4. **Secrets detectados em commits antigos**
   - Solução: Reescrever histórico com `git filter-repo` (raro)

---

## ✨ DEPOIS DE PR-1 PASSAR

Quando esta PR estiver merged:
1. ✅ CI está rodando
2. ✅ Banco de testes está configurado
3. ✅ Baseline de 14 testes SQL registrado

**Próxima:** PR-2 (SEGURANCA.md — documentação de segurança)

---

**Preparado por:** Claude Haiku 4.5  
**Data:** 2026-10-05  
**Status:** 🟢 Pronto para implementação — **Aguardando você rodar os passos**
