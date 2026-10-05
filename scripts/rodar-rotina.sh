#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# Dispara a rotina diária (cobranças do período, retorno de pausas, faturas
# atrasadas e, com a chave D8 ligada, cancelamento de quem não pagou a 1ª fatura).
#
# Serve a QUALQUER agendador (cron do servidor, tarefa agendada da hospedagem,
# GitHub Actions com `schedule`): ele só precisa rodar este script uma vez por dia.
#
#   URL_GESTAO=https://gestao.exemplo.com.br CRON_SECRET=... bash scripts/rodar-rotina.sh
#
# A rotina é idempotente (rodar duas vezes não duplica nada) e serializada por
# um bloqueio no banco. Falha com código ≠ 0 se a resposta não for 200, para o
# agendador avisar. O segredo NUNCA vai na URL (só no cabeçalho) nem é impresso.
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

: "${URL_GESTAO:?Defina URL_GESTAO (endereço público do painel, ex.: https://gestao.exemplo.com.br)}"
: "${CRON_SECRET:?Defina CRON_SECRET (o mesmo valor configurado no painel)}"

case "$URL_GESTAO" in
  https://*|http://localhost*|http://127.0.0.1*) ;;
  *) echo "✘ URL_GESTAO precisa ser https:// (ou localhost, em teste)." >&2; exit 2 ;;
esac

corpo="$(mktemp)"
trap 'rm -f "$corpo"' EXIT

codigo="$(curl --silent --show-error --max-time 120 \
  --output "$corpo" --write-out '%{http_code}' \
  --request POST \
  --header "Authorization: Bearer ${CRON_SECRET}" \
  "${URL_GESTAO%/}/api/rotina")"

if [ "$codigo" != "200" ]; then
  echo "✘ Rotina diária falhou (HTTP $codigo)." >&2
  # Corpo de erro da própria rota é curto e sem segredo.
  head -c 500 "$corpo" >&2 || true
  echo >&2
  exit 1
fi

echo "✔ Rotina diária executada:"
cat "$corpo"
echo
