#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# Varredura de segredos. Rode antes de cada commit e no CI.
#   bash scripts/verificar-segredos.sh
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail
cd "$(dirname "$0")/.."

falhas=0
aviso() { printf '  ✘ %s\n' "$1"; falhas=$((falhas + 1)); }
ok()    { printf '  ✔ %s\n' "$1"; }

echo ""
echo "── 1. Conexão administrativa fora do lugar ──"
# DATABASE_ADMIN_URL ignora toda a RLS. Só o pacote de banco pode lê-la.
# .next/ fica de fora: é código compilado que embute o pacote de banco (o
# nome da variável aparece lá por tabela); o que importa nele é a checagem 8.
encontrados=$(grep -rlnE 'DATABASE_ADMIN_URL|APP_SERVIDOR_SENHA' \
  --include='*.ts' --include='*.tsx' --include='*.js' --include='*.mjs' \
  --exclude-dir='.next' --exclude-dir='node_modules' \
  apps packages 2>/dev/null \
  | grep -v 'packages/database/src/acesso.ts' \
  | grep -v 'packages/database/src/auth/better-auth.ts' \
  | grep -v 'packages/database/scripts/' || true)
if [ -n "$encontrados" ]; then
  aviso "conexão administrativa referenciada fora do pacote de banco:"
  printf '       %s\n' $encontrados
else
  ok "DATABASE_ADMIN_URL só aparece onde deve"
fi

echo ""
echo "── 2. Segredo com prefixo público ──"
suspeitos=$(grep -rhoE 'NEXT_PUBLIC_[A-Z0-9_]+' \
  --include='*.ts' --include='*.tsx' --include='*.mjs' --include='*.example' \
  apps packages .env.example 2>/dev/null \
  | sort -u | grep -E 'SECRET|PRIVATE|SERVICE|PASSWORD|SENHA|TOKEN|DATABASE|ADMIN' || true)
if [ -n "$suspeitos" ]; then
  aviso "variável pública com cara de segredo:"
  printf '       %s\n' $suspeitos
else
  ok "nenhuma variável NEXT_PUBLIC_ com nome de segredo"
fi

echo ""
echo "── 3. comoAdmin() em Client Component ──"
arquivos=$(grep -rl 'comoAdmin' --include='*.ts' --include='*.tsx' apps 2>/dev/null || true)
ruins=""
for arq in $arquivos; do
  if head -5 "$arq" | grep -q "['\"]use client['\"]"; then ruins="$ruins $arq"; fi
done
if [ -n "$ruins" ]; then
  aviso "comoAdmin() usado em arquivo marcado 'use client':$ruins"
else
  ok "comoAdmin() não aparece em nenhum Client Component"
fi

echo ""
echo "── 4. comoAdmin() sem conferir o papel antes ──"
# Lei 7: quem usa a conexão administrativa confere o papel na mesma função.
ruins=""
for arq in $(grep -rl 'comoAdmin' --include='*.ts' --include='*.tsx' apps 2>/dev/null || true); do
  if ! grep -q 'exigirDono\|exigirPapel' "$arq"; then ruins="$ruins $arq"; fi
done
if [ -n "$ruins" ]; then
  aviso "usa comoAdmin() sem exigirDono/exigirPapel no mesmo arquivo:$ruins"
else
  ok "todo uso de comoAdmin() tem checagem de papel junto"
fi

echo ""
echo "── 5. .env versionado ──"
if git rev-parse --git-dir >/dev/null 2>&1; then
  rastreados=$(git ls-files | grep -E '(^|/)\.env' | grep -v '\.env\.example$' || true)
  if [ -n "$rastreados" ]; then
    aviso "arquivo .env rastreado pelo Git:"
    printf '       %s\n' $rastreados
  else
    ok "nenhum .env rastreado"
  fi

  echo ""
  echo "── 6. .env no histórico ──"
  no_historico=$(git log --all --full-history --name-only --pretty=format: -- '*.env' '*.env.*' 2>/dev/null \
    | sort -u | grep -v '^$' | grep -v '\.env\.example$' || true)
  if [ -n "$no_historico" ]; then
    aviso "houve .env no histórico. Rotacione as senhas PRIMEIRO, depois reescreva o histórico:"
    printf '       %s\n' $no_historico
  else
    ok "nenhum .env no histórico"
  fi
else
  echo "  · fora de um repositório Git — itens 5 e 6 pulados"
fi

echo ""
echo "── 7. .gitignore protegendo os segredos ──"
if grep -qx '\.env\*' .gitignore && grep -qx '!\.env\.example' .gitignore; then
  ok ".gitignore tem .env* e !.env.example"
else
  aviso ".gitignore precisa conter exatamente as linhas '.env*' e '!.env.example'"
fi

echo ""
echo "── 8. Senha ou URL de banco na saída de build ──"
saidas=$(find apps -type d \( -name '.next' -o -name 'dist' \) 2>/dev/null || true)
if [ -n "$saidas" ]; then
  if grep -rqE 'postgresql://[^ "]*:[^ "@]+@' $saidas 2>/dev/null; then
    aviso "URL DE BANCO COM SENHA ENCONTRADA NA SAÍDA DE BUILD — vazou"
  else
    ok "nenhuma URL de banco com senha na saída de build"
  fi
else
  echo "  · sem build gerado — rode 'pnpm build' e repita"
fi

echo ""
echo "── 9. comoPagamentos() fora do webhook ──"
# O papel app_pagamentos baixa fatura. Só o webhook, DEPOIS de conferir o pagamento no provedor, pode usá-lo.
ruins=""
for arq in $(grep -rl 'comoPagamentos' --include='*.ts' --include='*.tsx' apps 2>/dev/null || true); do
  case "$arq" in
    apps/assinante/src/app/api/pagamento/webhook/route.ts) ;;
    *) ruins="$ruins $arq" ;;
  esac
done
if [ -n "$ruins" ]; then
  aviso "comoPagamentos() usado fora do webhook de pagamento:$ruins"
else
  ok "comoPagamentos() só aparece no webhook de pagamento"
fi

echo ""
if [ "$falhas" -gt 0 ]; then
  echo "✘ $falhas problema(s) de segredo. Não faça commit assim."
  exit 1
fi
echo "✔ Varredura de segredos limpa."
