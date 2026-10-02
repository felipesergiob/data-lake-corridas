#!/usr/bin/env bash
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TFDIR="${TFDIR:-$RAIZ/parte-1/terraform}"
DECISOES="${DECISOES:-$RAIZ/DECISOES.md}"
REGIAO="${AWS_REGION:-us-east-1}"
POS=0
[ "${1:-}" = "--pos-destroy" ] && POS=1

G=$'\e[32m'; R=$'\e[31m'; D=$'\e[2m'; B=$'\e[1m'; X=$'\e[0m'
notas=0
total=0

linha() { printf '%s\n' "----------------------------------------------------------------"; }
pass() { notas=$((notas + $2)); total=$((total + $2)); printf "${G}PASSA${X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
fail() { total=$((total + $2)); printf "${R}FALHA${X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
info() { printf "${D}       %s${X}\n" "$1"; }

tfout() { terraform -chdir="$TFDIR" output -raw "$1" 2>/dev/null || true; }
tfvar() {
  local nome="$1"
  awk -F'"' -v n="$nome" '$0 ~ "^[[:space:]]*" n "[[:space:]]*=" { print $2; exit }' "$TFDIR/terraform.tfvars" 2>/dev/null
}

GRUPO="${GRUPO:-$(tfvar grupo)}"
[ -z "$GRUPO" ] && GRUPO="g11"
PREFIXO="eda262-${GRUPO}"

if [ "$REGIAO" != "us-east-1" ]; then
  echo "${R}FALHA${X}  regiao atual: $REGIAO; esperado: us-east-1 (N. Virginia)." >&2
  exit 2
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "${R}FALHA${X}  AWS CLI nao encontrado. Instale/configure antes de rodar o verificador." >&2
  exit 2
fi

if [ "$POS" != "1" ] && ! command -v terraform >/dev/null 2>&1; then
  echo "${R}FALHA${X}  Terraform nao encontrado. Instale o Terraform antes de rodar o verificador." >&2
  exit 2
fi

consulta_negocio() {
  cat <<'SQL'
SELECT
  bairro,
  count(*) AS corridas_madrugada,
  round(sum(valor), 2) AS receita_madrugada
FROM corridas_trusted
WHERE substr(data_corrida, 12, 2) BETWEEN '00' AND '05'
  AND valor IS NOT NULL
GROUP BY bairro
ORDER BY receita_madrugada DESC
LIMIT 5
SQL
}

roda_query() {
  local sql="$1"
  local db="$2"
  local wg="$3"
  local qid estado bytes motivo
  qid="$(aws athena start-query-execution --region "$REGIAO" --work-group "$wg" \
    --query-execution-context Database="$db" \
    --query-string "$sql" --query "QueryExecutionId" --output text 2>/dev/null || true)"
  [ -z "$qid" ] || [ "$qid" = "None" ] && { echo "SEM_ID|ERROR|0|nao iniciou"; return; }

  for _ in $(seq 1 45); do
    estado="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$qid" \
      --query "QueryExecution.Status.State" --output text 2>/dev/null || true)"
    case "$estado" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
    sleep 2
  done

  bytes="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$qid" \
    --query "QueryExecution.Statistics.DataScannedInBytes" --output text 2>/dev/null || true)"
  motivo="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$qid" \
    --query "QueryExecution.Status.StateChangeReason" --output text 2>/dev/null || true)"
  echo "${qid}|${estado:-UNKNOWN}|${bytes:-0}|${motivo:-}"
}

if [ "$POS" = "1" ]; then
  echo "${B}AV1 — destroy limpo (regiao $REGIAO)${X}"; linha
  orfaos="$(aws s3 ls --region "$REGIAO" 2>/dev/null | grep -E "${PREFIXO}-(lake-trusted|athena-results)\b" || true)"
  db="$(aws glue get-database --region "$REGIAO" --name "eda262_${GRUPO}" --query "Database.Name" --output text 2>/dev/null || true)"
  wg="$(aws athena list-work-groups --region "$REGIAO" --query "WorkGroups[?Name=='${PREFIXO}-athena-wg'].Name | [0]" --output text 2>/dev/null || true)"

  if [ -z "$orfaos" ] && { [ -z "$db" ] || [ "$db" = "None" ]; } && { [ -z "$wg" ] || [ "$wg" = "None" ]; }; then
    pass "5" 15 "nenhum bucket, database ou workgroup orfao da AV1."
  else
    fail "5" 15 "sobraram recursos da AV1."
    [ -n "$orfaos" ] && printf '%s\n' "$orfaos"
    [ -n "$db" ] && [ "$db" != "None" ] && info "database ainda existe: $db"
    [ -n "$wg" ] && [ "$wg" != "None" ] && info "workgroup ainda existe: $wg"
  fi
  linha
  printf "${B}Resultado pos-destroy: %s/%s${X}\n" "$notas" "$total"
  exit 0
fi

echo "${B}AV1 — verificacao do projeto (regiao $REGIAO)${X}"; linha

echo "${B}Criterio 0 — estrutura local da entrega${X}"
if [ ! -f "$TFDIR/main.tf" ]; then
  fail "0" 0 "nao achei parte-1/terraform/main.tf."; exit 2
fi
if ! grep -rqE '^\s*module\s+"' "$TFDIR"/*.tf 2>/dev/null; then
  fail "0" 0 "nao achei module na raiz Terraform."; exit 2
fi
if ! grep -rqE 'backend\s+"s3"' "$TFDIR"/*.tf 2>/dev/null; then
  fail "0" 0 "nao achei backend s3."; exit 2
fi
if grep -rqE --include='*.tf' 'aws_glue_crawler|AWS::Glue::Crawler' "$TFDIR" 2>/dev/null; then
  fail "0" 0 "ha Crawler na entrega; a AV1 pede schema declarado."; exit 2
fi
if grep -rqE --include='*.tf' 'aws_glue_partition|partition_keys' "$TFDIR" 2>/dev/null; then
  fail "0" 0 "ha particionamento no Terraform; particionamento esta fora da AV1."; exit 2
fi
pass "0" 0 "Terraform modular, backend s3, schema declarado e sem particionamento."
linha

echo "${B}Criterio 1 — workspace e backend remoto${X}"
ws="$(terraform -chdir="$TFDIR" workspace show 2>/dev/null || true)"
if [ "$ws" = "av1" ]; then
  pass "1" 10 "workspace av1 ativo."
else
  fail "1" 10 "workspace atual: ${ws:-indisponivel}; esperado: av1."
fi
if [ -f "$TFDIR/terraform.tfstate" ] && grep -q '"resources"' "$TFDIR/terraform.tfstate" 2>/dev/null; then
  fail "1b" 0 "ha terraform.tfstate local com recursos; migre para backend remoto."
else
  info "sem estado local com recursos."
fi
linha

echo "${B}Criterio 2 — outputs e nomes padronizados${X}"
BUCKET="$(tfout lake_bucket_name)"
RESULTS="$(tfout athena_results_bucket_name)"
DB="$(tfout database_name)"
TABLE="$(tfout trusted_table_name)"
WG="$(tfout workgroup_name)"
TETO="$(tfout teto_bytes)"
faltou=""
for nome in BUCKET RESULTS DB TABLE WG TETO; do
  [ -z "${!nome}" ] && faltou="$faltou $nome"
done
if [ -n "$faltou" ]; then
  fail "2" 15 "faltaram outputs:$faltou"
else
  info "bucket=$BUCKET results=$RESULTS db=$DB table=$TABLE wg=$WG teto=$TETO"
  if [ "$BUCKET" = "${PREFIXO}-lake-trusted" ] && [ "$RESULTS" = "${PREFIXO}-athena-results" ] && [ "$DB" = "eda262_${GRUPO}" ] && [ "$TABLE" = "corridas_trusted" ] && [ "$WG" = "${PREFIXO}-athena-wg" ]; then
    pass "2" 15 "outputs existem e seguem eda262-gNN."
  else
    fail "2" 15 "outputs existem, mas algum nome foge do padrao."
  fi
fi
linha

echo "${B}Criterio 3 — recursos AWS, tags e schema trusted${X}"
if [ -n "$BUCKET" ] && aws s3api head-bucket --bucket "$BUCKET" --region "$REGIAO" 2>/dev/null; then
  tag_turma="$(aws s3api get-bucket-tagging --bucket "$BUCKET" --region "$REGIAO" --query "TagSet[?Key=='turma'].Value | [0]" --output text 2>/dev/null || true)"
  tag_grupo="$(aws s3api get-bucket-tagging --bucket "$BUCKET" --region "$REGIAO" --query "TagSet[?Key=='grupo'].Value | [0]" --output text 2>/dev/null || true)"
  tag_projeto="$(aws s3api get-bucket-tagging --bucket "$BUCKET" --region "$REGIAO" --query "TagSet[?Key=='projeto'].Value | [0]" --output text 2>/dev/null || true)"
else
  tag_turma=""; tag_grupo=""; tag_projeto=""
fi

ncol="$(aws glue get-table --region "$REGIAO" --database-name "$DB" --name "$TABLE" --query "length(Table.StorageDescriptor.Columns)" --output text 2>/dev/null || true)"
location="$(aws glue get-table --region "$REGIAO" --database-name "$DB" --name "$TABLE" --query "Table.StorageDescriptor.Location" --output text 2>/dev/null || true)"
grain="$(aws glue get-table --region "$REGIAO" --database-name "$DB" --name "$TABLE" --query "Table.Parameters.grain" --output text 2>/dev/null || true)"
info "tags bucket: turma=$tag_turma grupo=$tag_grupo projeto=$tag_projeto"
info "schema: colunas=${ncol:-?} location=${location:-?} grain=${grain:-?}"
if [ "$tag_turma" = "eda262" ] && [ "$tag_grupo" = "$GRUPO" ] && [ "$tag_projeto" = "engenharia-de-dados" ] && [ "${ncol:-0}" -ge 9 ] 2>/dev/null && [ "$location" = "s3://${BUCKET}/trusted/corridas/" ]; then
  pass "3" 15 "recursos tagueados e tabela trusted com schema declarado."
else
  fail "3" 15 "tags/schema/location nao batem com o contrato da AV1."
fi
linha

echo "${B}Criterio 4 — dados, consulta e custo Athena${X}"
objs="$(aws s3 ls "s3://${BUCKET}/trusted/corridas/" --recursive --region "$REGIAO" 2>/dev/null || true)"
nobj="$(printf '%s\n' "$objs" | grep -c 'parte-.*\.json' || true)"
bytes_s3="$(printf '%s\n' "$objs" | awk '{s += $3} END {print s + 0}')"
info "objetos trusted: $nobj · bytes S3: $bytes_s3"

SQL="$(consulta_negocio)"
R="$(roda_query "$SQL" "$DB" "$WG")"
qid="$(echo "$R" | cut -d'|' -f1)"
estado="$(echo "$R" | cut -d'|' -f2)"
bytes_query="$(echo "$R" | cut -d'|' -f3)"
motivo="$(echo "$R" | cut -d'|' -f4-)"
info "query_id=$qid estado=$estado bytes=$bytes_query"

if [ "$estado" = "SUCCEEDED" ] && [ "${bytes_query:-0}" -gt 0 ] 2>/dev/null; then
  custo="$(awk -v b="$bytes_query" 'BEGIN { printf "%.8f", (b / 1099511627776) * 5 }')"
  info "custo_estimado_usd=$custo"
  aws athena get-query-results --region "$REGIAO" --query-execution-id "$qid" \
    --query "ResultSet.Rows[0:6].Data[].VarCharValue" --output table 2>/dev/null || true
  pass "4" 20 "pergunta respondida no Athena com custo medido."
else
  fail "4" 20 "consulta nao respondeu. estado=$estado motivo=${motivo:0:120}"
fi
linha

echo "${B}Criterio 6 — DECISOES.md${X}"
if [ -f "$DECISOES" ]; then
  nd="$(grep -ciE 'DECIS[ÃA]O\s*0?[1-5]' "$DECISOES" 2>/dev/null || true)"
  if [ "${nd:-0}" -ge 5 ]; then
    pass "6" 0 "encontrei $nd decisoes; conteudo e nota sao avaliados manualmente."
  else
    fail "6" 0 "DECISOES.md tem menos de 5 decisoes."
  fi
else
  fail "6" 0 "nao achei DECISOES.md na raiz."
fi
linha

echo "${B}Resumo automatico: $notas/$total pontos-percentuais${X}"
info "rode ./verifica.sh --pos-destroy depois do terraform destroy."
