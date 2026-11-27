#!/usr/bin/env bash
# Revoga a permissao padrao IAM_ALLOWED_PRINCIPALS de databases e tabelas.
#
# Uso: revoga-iam-allowed.sh <regiao> <database.tabela> [<database.tabela> ...]
#
# Idempotente: se a permissao ja nao existir, o Lake Formation responde com
# erro de "nao encontrado" e o script segue. Qualquer outro erro falha o apply.
set -uo pipefail

regiao="$1"; shift

if ! command -v aws >/dev/null 2>&1; then
  echo "revoga-iam-allowed: AWS CLI nao encontrada; ela e necessaria para o apply." >&2
  exit 1
fi

revoga() {
  local recurso="$1" descricao="$2" saida
  if saida="$(aws lakeformation revoke-permissions --region "$regiao" \
      --principal DataLakePrincipalIdentifier=IAM_ALLOWED_PRINCIPALS \
      --permissions ALL --resource "$recurso" 2>&1)"; then
    echo "revogado IAM_ALLOWED_PRINCIPALS em $descricao"
  elif printf '%s' "$saida" | grep -qiE 'no permissions revoked|has no permissions|not found'; then
    echo "ja sem IAM_ALLOWED_PRINCIPALS em $descricao"
  else
    echo "falha ao revogar em $descricao: $saida" >&2
    return 1
  fi
}

falhas=0
for alvo in "$@"; do
  db="${alvo%%.*}"
  tabela="${alvo#*.}"
  revoga "{\"Database\":{\"Name\":\"$db\"}}" "database $db" || falhas=$((falhas + 1))
  revoga "{\"Table\":{\"DatabaseName\":\"$db\",\"Name\":\"$tabela\"}}" "tabela $db.$tabela" || falhas=$((falhas + 1))
done

exit "$falhas"
