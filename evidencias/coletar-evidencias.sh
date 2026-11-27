#!/usr/bin/env bash
# Coleta as evidencias da Parte 2 (tema: precos de combustiveis da ANP) em evidencias/.
#
# Uso (com a stack no ar e os dados carregados com parte-2/dados/carregar.sh):
#   ./evidencias/coletar-evidencias.sh               # verifica + pergunta + medicoes
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
MEDFILE="$RAIZ/parte-2/consultas/medicoes.sql"
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

WG="$(terraform -chdir="$TFDIR" output -raw workgroup_name)"
database_da_camada() { terraform -chdir="$TFDIR" output -raw "database_$1"; }

# executa ROTULO DATABASE SQL -> imprime um bloco com id, bytes, custo e resultado
executa() {
  local rotulo="$1" db="$2" sql="$3" qid estado bytes ms custo
  qid="$(aws athena start-query-execution --region "$REGIAO" --work-group "$WG" \
    --query-execution-context Database="$db" --query-string "$sql" \
    --query QueryExecutionId --output text)"
  [ -z "$qid" ] && { echo "Athena nao iniciou: $rotulo" >&2; return 1; }
  for _ in $(seq 1 60); do
    estado="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$qid" \
      --query QueryExecution.Status.State --output text)"
    case "$estado" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
    sleep 2
  done
  bytes="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$qid" \
    --query QueryExecution.Statistics.DataScannedInBytes --output text)"
  ms="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$qid" \
    --query QueryExecution.Statistics.TotalExecutionTimeInMillis --output text)"
  custo="$(awk -v b="$bytes" 'BEGIN { printf "%.8f", b / 1099511627776 * 5 }')"

  echo "=== $rotulo"
  echo "database ............ $db"
  echo "QueryExecutionId .... $qid"
  echo "estado .............. $estado"
  echo "DataScannedInBytes .. $bytes"
  echo "tempo (ms) .......... $ms"
  echo "custo (USD) ......... $custo   # DataScannedInBytes / 1099511627776 * 5"
  echo "--- SQL ---"
  echo "$sql"
  echo "--- resultado ---"
  if [ "$estado" = "SUCCEEDED" ]; then
    aws athena get-query-results --region "$REGIAO" --query-execution-id "$qid" --output text \
      --query 'ResultSet.Rows[*].Data[*].VarCharValue'
  else
    aws athena get-query-execution --region "$REGIAO" --query-execution-id "$qid" \
      --query QueryExecution.Status.StateChangeReason --output text
  fi
  echo
}

# 1) verifica.sh
"$RAIZ/verificacao/verifica.sh" | tee "$EVID/verifica-parte-2.txt"

# 2) pergunta de negocio na refined
SQL="$(grep -v '^[[:space:]]*--' "$SQLFILE" | sed 's/;[[:space:]]*$//')"
{
  echo "Parte 2 - pergunta de negocio (Athena) · $(date -u +%Y-%m-%dT%H:%M:%SZ) · workgroup $WG"
  echo
  executa "pergunta de negocio" "$(database_da_camada refined)" "$SQL"
} | tee "$EVID/consulta-athena-parte-2.txt"

# 3) medicoes do DECISOES.md: cada bloco de medicoes.sql comeca com
#    "-- Mn (...) ... Database: eda262_gNN_<camada>"
{
  echo "Parte 2 - medicoes do DECISOES.md · $(date -u +%Y-%m-%dT%H:%M:%SZ) · workgroup $WG"
  echo
  bloco=""; rotulo=""; camada=""
  while IFS= read -r l || [ -n "$l" ]; do
    if [[ "$l" =~ ^--\ (M[0-9]+.*)$ ]]; then
      rotulo="${BASH_REMATCH[1]}"
      camada="$(printf '%s' "$l" | sed -nE 's/.*Database: eda262_g[^_]+_([a-z]+).*/\1/p')"
      bloco=""
    elif [[ "$l" =~ ^[[:space:]]*-- ]] || [ -z "${l// }" ]; then
      :
    else
      bloco="$bloco$l"$'\n'
      if [[ "$l" =~ \;[[:space:]]*$ ]] && [ -n "$rotulo" ]; then
        executa "$rotulo" "$(database_da_camada "$camada")" "$(printf '%s' "$bloco" | sed 's/;[[:space:]]*$//')"
        bloco=""; rotulo=""
      fi
    fi
  done < "$MEDFILE"
} | tee "$EVID/medicoes-parte-2.txt"

echo
echo "Salvos: evidencias/verifica-parte-2.txt, consulta-athena-parte-2.txt e medicoes-parte-2.txt"
echo "Copie QueryExecutionId e DataScannedInBytes para o DECISOES.md e troque os PENDENTE."
