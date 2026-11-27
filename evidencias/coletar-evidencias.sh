#!/usr/bin/env bash
# Coleta as evidencias da parte 2 (tema: precos de combustiveis da ANP) e salva em evidencias/.
#
# Uso (com a stack no ar e os dados ja enviados ao S3):
#   ./evidencias/coletar-evidencias.sh               # verifica + consulta Athena
#
# Depois do terraform destroy:
#   ./evidencias/coletar-evidencias.sh --pos-destroy # verifica --pos-destroy
#
# Requer: aws CLI, terraform, credenciais da disciplina, regiao us-east-1.
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
EVID="$RAIZ/evidencias"
TFDIR="$RAIZ/parte-2/terraform"
SQLFILE="$RAIZ/parte-2/consultas/pergunta-negocio.sql"
REGIAO="${AWS_REGION:-us-east-1}"

if [ "$REGIAO" != "us-east-1" ]; then
  echo "Regiao atual: $REGIAO; use us-east-1." >&2
  exit 2
fi

if [ "${1:-}" = "--pos-destroy" ]; then
  "$RAIZ/verificacao/verifica.sh" --pos-destroy | tee "$EVID/verifica-parte-2-pos-destroy.txt"
  echo
  echo "Salvo: evidencias/verifica-parte-2-pos-destroy.txt"
  exit 0
fi

# 1) verifica.sh
"$RAIZ/verificacao/verifica.sh" | tee "$EVID/verifica-parte-2.txt"

# 2) consulta da pergunta de negocio com custo medido
WG="$(terraform -chdir="$TFDIR" output -raw workgroup_name)"
DB="$(terraform -chdir="$TFDIR" output -raw database_name)"
SQL="$(grep -v '^[[:space:]]*--' "$SQLFILE" | sed 's/;[[:space:]]*$//')"

QID="$(aws athena start-query-execution --region "$REGIAO" --work-group "$WG" \
  --query-execution-context Database="$DB" --query-string "$SQL" \
  --query QueryExecutionId --output text)"
[ -z "$QID" ] && { echo "Athena nao iniciou a consulta." >&2; exit 1; }

ESTADO=""
for _ in $(seq 1 60); do
  ESTADO="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$QID" \
    --query QueryExecution.Status.State --output text)"
  case "$ESTADO" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
  sleep 2
done

BYTES="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$QID" \
  --query QueryExecution.Statistics.DataScannedInBytes --output text)"
MS="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$QID" \
  --query QueryExecution.Statistics.TotalExecutionTimeInMillis --output text)"
CUSTO="$(awk -v b="$BYTES" 'BEGIN { printf "%.8f", b / 1099511627776 * 5 }')"

{
  echo "Parte 2 - consulta da pergunta de negocio (Athena)"
  echo "data ................ $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "workgroup ........... $WG"
  echo "database ............ $DB"
  echo "QueryExecutionId .... $QID"
  echo "estado .............. $ESTADO"
  echo "DataScannedInBytes .. $BYTES"
  echo "tempo (ms) .......... $MS"
  echo "custo (USD) ......... $CUSTO   # DataScannedInBytes / 1099511627776 * 5"
  echo
  echo "--- SQL ---"
  cat "$SQLFILE"
  echo
  echo "--- resultado ---"
  aws athena get-query-results --region "$REGIAO" --query-execution-id "$QID" --output text \
    --query 'ResultSet.Rows[*].Data[*].VarCharValue'
} | tee "$EVID/consulta-athena-parte-2.txt"

echo
echo "Salvos: evidencias/verifica-parte-2.txt e evidencias/consulta-athena-parte-2.txt"
echo "Copie bytes=$BYTES e QueryExecutionId=$QID para o DECISOES.md (decisao 05)."
