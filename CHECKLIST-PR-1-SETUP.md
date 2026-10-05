# ✅ CHECKLIST: PR-1 CI/CD Setup & Testes SQL

**Status:** Em execução  
**Data:** 2026-10-05  
**Responsável:** Claude Haiku 4.5 (setup guiado)  

---

## 📋 O QUE ESTA PR FARÁ

- [ ] Configurar `DATABASE_TEST_URL` em `.env`
- [ ] Validar CI/CD (`.github/workflows/ci.yml` já existe e está ativo)
- [ ] Rodar 14 suites SQL e registrar baseline
- [ ] Commit com mensagem clara

---

## 🔧 PASSO 1: Preparar Ambiente Local

### 1.1 — Dependências

```bash
cd "C:\Users\jbrun\Documents\Ovo di Onça"
node --version          # Deve ser ≥ 20.11
npm install -g pnpm     # Se não tiver
pnpm --version          # Deve ser 9+
```

### 1.2 — Instalar packages

```bash
pnpm install --frozen-lockfile
```

**Resultado esperado:** Nenhum erro. Se houver conflito de versão, reportar.

---

## 🗄️ PASSO 2: Configurar Banco de Testes (DATABASE_TEST_URL)

### 2.1 — Criar branch de testes no Neon

1. Acesse [Neon Console](https://console.neon.tech)
2. Projeto: `ovodionca` (ou seu nome)
3. **Branches** → **New branch** → Nome: `teste`
4. Aguarde criação (~30s)

### 2.2 — Copiar connection string

1. Na nova branch `teste`, clique em **Connection string**
2. Role: Username: `neondb_owner`, Database: `ovodionca_teste` (ou `ovodionca`)
3. Copie a connection string completa

### 2.3 — Adicionar a `.env`

Abra `.env` na raiz:

```bash
# Copie e adapte:
DATABASE_TEST_URL=postgresql://neondb_owner:SENHA@ep-teste.sa-east-1.aws.neon.tech/ovodionca_teste?sslmode=require
```

⚠️ **NÃO committe `.env`** — já está em `.gitignore`.

### 2.4 — Validar conexão

```bash
pnpm db:migrar:teste
```

**Resultado esperado:**
```
✅ 22 migrations applied
✅ Database schema created
```

Se falhar:
- Verifique credenciais
- Verifique IP allowlist no Neon (security → IP allowlist → adicione seu IP)
- Tente novamente

---

## 🧪 PASSO 3: Rodar Testes SQL (14 suites)

Agora rode os testes para validar o baseline:

```bash
pnpm teste:banco
```

### 3.1 — Monitorar saída

Você verá:
```
> pnpm --filter @ovo/database teste:fase1
✓ teste-fase1-clientes.sql

> pnpm --filter @ovo/database teste:fase2
✓ teste-fase2-assinaturas.sql

... (10 mais testes)

> pnpm --filter @ovo/database teste:etapa2
✓ teste-etapa2-calendario.sql

✅ BASELINE: 14/14 suites passed
```

**Se falhar:** Uma suite SQL falhou. Verifique:
- O teste SQL tem um erro de lógica? Relate o erro específico.
- O banco de testes foi migrado? Verifique `pnpm db:migrar:teste`.

### 3.2 — Registrar resultado

```bash
# Capture a saída:
pnpm teste:banco > BASELINE-TESTES-SQL-2026-10-05.txt

# Ou no PowerShell:
pnpm teste:banco | Out-File -Encoding UTF8 BASELINE-TESTES-SQL-2026-10-05.txt
```

---

## 🔐 PASSO 4: Varredura de Segredos (CI simulation)

Rode a verificação que o CI vai rodar:

```bash
bash scripts/verificar-segredos.sh
```

**Resultado esperado:**
```
✅ Nenhum secret encontrado em commits
✅ .env não está rastreado
✅ Nenhuma chave privada no histórico
```

Se falhar: Um secret vazou. Instruções em `scripts/verificar-segredos.sh`.

---

## 🏗️ PASSO 5: TypeCheck & Lint (CI simulation)

```bash
pnpm typecheck
pnpm lint
```

**Resultado esperado:** Sem erros críticos.

---

## 📝 PASSO 6: Criar Commit

Quando tudo passar:

```bash
git add .env.example
git commit -m "feat(ci): configure DATABASE_TEST_URL e baseline de testes SQL

- Atualiza .env.example com exemplo de DATABASE_TEST_URL
- Valida 14 suites SQL (fase1..10, etapa1..2)
- CI já configurado (.github/workflows/ci.yml ativo)
- Baseline registrado: $(date)

Testes rodados:
✓ teste-fase1-clientes.sql
✓ teste-fase2-assinaturas.sql
✓ teste-fase3-entregas.sql
✓ teste-fase4-faturas.sql
✓ teste-fase5-ciclo.sql
✓ teste-fase6-auditoria.sql
✓ teste-fase7-assinante.sql
✓ teste-fase8-cadastro-site.sql
✓ teste-fase9-operacao.sql
✓ teste-fase10-estabilidade.sql
✓ teste-etapa1-estrutura.sql
✓ teste-etapa2-calendario.sql
✓ teste-autorizacao.sql
✓ lei1-estrutura.sql"
```

Ou use seu próprio commit message (padrão: "feat", "fix", "chore").

---

## ✅ VALIDAÇÃO FINAL

Antes de fazer push/PR, confirme:

| Item | Status |
|------|--------|
| `DATABASE_TEST_URL` configurado em `.env` | ☐ |
| `pnpm db:migrar:teste` rodou com sucesso | ☐ |
| `pnpm teste:banco` passou 14/14 suites | ☐ |
| `bash scripts/verificar-segredos.sh` passou | ☐ |
| `pnpm typecheck` sem erros | ☐ |
| `pnpm lint` sem erros críticos | ☐ |
| Commit criado com mensagem clara | ☐ |
| `.env` NÃO foi commitado (apenas `.env.example`) | ☐ |

---

## 🚀 PASSO 7: Push & PR

```bash
git push origin main
# ou crie uma branch:
git checkout -b ci/setup-database-tests
git push -u origin ci/setup-database-tests
# Depois abra PR no GitHub
```

CI vai rodar automaticamente:
- Varredura de segredos ✓
- TypeScript check ✓
- Lint ✓
- Testes SQL (se DATABASE_TEST_URL em GitHub Secrets) ✓

---

## ❓ TROUBLESHOOTING

### Erro: `password authentication failed for user 'neondb_owner'`
- DATABASE_TEST_URL está vazio ou errado
- Verifique credenciais Neon (role: `neondb_owner`)
- Verifique IP allowlist

### Erro: `database 'ovodionca_teste' does not exist`
- Branch `teste` criada mas banco não inicializado
- Rode `pnpm db:migrar:teste` para criar schema

### Erro: Test SQL suite falhou (ex: `teste-fase1-clientes.sql`)
- Verifique a query SQL no arquivo
- Verifique triggers e policies no banco
- Report o erro específico no teste

### Erro: Secret encontrado em commits antigos
- `scripts/verificar-segredos.sh` detectou algo
- Se for falso positivo, adicione a `.gitignore`
- Se for real, reescrever histórico com `git filter-repo`

---

## 📞 QUANDO PEDIR AJUDA

Se não conseguir passar neste checklist:
1. Anote qual passo falhou
2. Cole a mensagem de erro completa
3. Rode `git status` e passe a saída
4. Confirme: PostgreSQL 16+, Node 20.11+, pnpm 9+

---

**Próximo:** Quando PR-1 passar CI e testar baseline, começar **PR-2: SEGURANCA.md**

---

**Criado por:** Claude Haiku 4.5  
**Data:** 2026-10-05
