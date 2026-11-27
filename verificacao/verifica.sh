#!/usr/bin/env bash
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TFDIR="${TFDIR:-$RAIZ/parte-2/terraform}"
SQLFILE="${SQLFILE:-$RAIZ/parte-2/consultas/pergunta-negocio.sql}"
CARREGAR="$RAIZ/parte-2/dados/carregar.sh"
DECISOES="${DECISOES:-$RAIZ/DECISOES.md}"
REGIAO="${AWS_REGION:-us-east-1}"
aws() { command aws "$@" | tr -d '\r'; }
BACKFILL_ANO="2024"; BACKFILL_MES="06"; BACKFILL_LINHAS=49958

POS=0; RECARGA=1
for arg in "$@"; do
  case "$arg" in
    --pos-destroy) POS=1 ;;
    --sem-recarga) RECARGA=0 ;;
  esac
done

G=$'\e[32m'; R=$'\e[31m'; D=$'\e[2m'; B=$'\e[1m'; X=$'\e[0m'
notas=0
total=0

linha() { printf '%s\n' "----------------------------------------------------------------"; }
pass() { notas=$((notas + $2)); total=$((total + $2)); printf "${G}PASSA${X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
fail() { total=$((total + $2)); printf "${R}FALHA${X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
info() { printf "${D}       %s${X}\n" "$1"; }

tfout() { terraform -chdir="$TFDIR" output -raw "$1" 2>/dev/null || true; }
tfvar() {
  awk -F'"' -v n="$1" '$0 ~ "^[[:space:]]*" n "[[:space:]]*=" { print $2; exit }' "$TFDIR/terraform.tfvars" 2>/dev/null
}
vazio() { [ -z "$1" ] || [ "$1" = "None" ]; }

GRUPO="${GRUPO:-$(tfvar grupo)}"
[ -z "$GRUPO" ] && GRUPO="g11"
PREFIXO="eda262-${GRUPO}"
CAMADAS="raw trusted refined"

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
  grep -v '^[[:space:]]*--' "$SQLFILE" | sed 's/;[[:space:]]*$//'
}

roda_query() {
  local sql="$1" db="$2" wg="$3" qid estado bytes motivo
  qid="$(aws athena start-query-execution --region "$REGIAO" --work-group "$wg" \
    --query-execution-context Database="$db" \
    --query-string "$sql" --query "QueryExecutionId" --output text 2>/dev/null || true)"
  if vazio "$qid"; then echo "SEM_ID|ERROR|0|nao iniciou"; return; fi

  for _ in $(seq 1 60); do
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

valor_escalar() {
  local r qid estado
  r="$(roda_query "$1" "$2" "$3")"
  qid="$(echo "$r" | cut -d'|' -f1)"; estado="$(echo "$r" | cut -d'|' -f2)"
  [ "$estado" = "SUCCEEDED" ] || { echo ""; return; }
  aws athena get-query-results --region "$REGIAO" --query-execution-id "$qid" \
    --query "ResultSet.Rows[1].Data[0].VarCharValue" --output text 2>/dev/null || true
}

principais_select() {
  aws lakeformation list-permissions --region "$REGIAO" \
    --resource "{\"Table\":{\"DatabaseName\":\"$1\",\"TableWildcard\":{}}}" \
    --query "PrincipalResourcePermissions[?contains(Permissions,'SELECT')].Principal.DataLakePrincipalIdentifier" \
    --output text 2>/dev/null | tr '\t' '\n' || true
}

if [ "$POS" = "1" ]; then
  echo "${B}Parte 2 — destroy limpo (regiao $REGIAO)${X}"; linha
  sobras=0

  buckets="$(aws s3 ls --region "$REGIAO" 2>/dev/null | grep -E "${PREFIXO}-(lake-(raw|trusted|refined)|athena-results)\b" || true)"
  [ -n "$buckets" ] && { sobras=1; info "buckets que sobraram:"; printf '%s\n' "$buckets"; }

  for c in $CAMADAS; do
    db="$(aws glue get-database --region "$REGIAO" --name "eda262_${GRUPO}_$c" --query "Database.Name" --output text 2>/dev/null || true)"
    vazio "$db" || { sobras=1; info "database ainda existe: $db"; }
  done

  wg="$(aws athena list-work-groups --region "$REGIAO" --query "WorkGroups[?Name=='${PREFIXO}-athena-wg'].Name | [0]" --output text 2>/dev/null || true)"
  vazio "$wg" || { sobras=1; info "workgroup ainda existe: $wg"; }

  for papel in engenharia analista lf-registro; do
    r="$(aws iam get-role --role-name "${PREFIXO}-$papel" --query "Role.RoleName" --output text 2>/dev/null || true)"
    vazio "$r" || { sobras=1; info "papel IAM ainda existe: $r"; }
  done

  lf="$(aws lakeformation list-resources --region "$REGIAO" --query "ResourceInfoList[].ResourceArn" --output text 2>/dev/null \
    | tr '\t' '\n' | grep -E "${PREFIXO}-lake-(raw|trusted|refined)$" || true)"
  [ -n "$lf" ] && { sobras=1; info "local ainda registrado no Lake Formation:"; printf '%s\n' "$lf"; }

  if [ "$sobras" = "0" ]; then
    pass "9" 100 "nenhum bucket, database, workgroup, papel IAM ou registro do Lake Formation orfao."
  else
    fail "9" 100 "sobraram recursos do projeto (lista acima)."
  fi
  linha
  printf "${B}Resultado pos-destroy: %s/%s${X}\n" "$notas" "$total"
  exit 0
fi

echo "${B}Parte 2 — verificacao do projeto (regiao $REGIAO)${X}"; linha

echo "${B}Criterio 0 — estrutura local da entrega${X}"
for f in main.tf modules/lake/tabelas.tf modules/acesso/main.tf; do
  [ -f "$TFDIR/$f" ] || { fail "0" 0 "nao achei parte-2/terraform/$f."; exit 2; }
done
grep -rqE 'backend\s+"s3"' "$TFDIR"/*.tf 2>/dev/null || { fail "0" 0 "nao achei backend s3."; exit 2; }
if grep -rqE --include='*.tf' 'aws_glue_crawler' "$TFDIR" 2>/dev/null; then
  fail "0" 0 "ha Crawler na entrega; o projeto pede schema declarado."; exit 2
fi
[ -f "$SQLFILE" ] || { fail "0" 0 "nao achei a consulta em $SQLFILE."; exit 2; }
pass "0" 0 "Terraform em modulos (lake + acesso), backend s3, schema declarado, consulta versionada."
linha

echo "${B}Criterio 1 — workspace e backend remoto${X}"
ws="$(terraform -chdir="$TFDIR" workspace show 2>/dev/null || true)"
if [ "$ws" = "av2" ]; then
  pass "1" 10 "workspace av2 ativo."
else
  fail "1" 10 "workspace atual: ${ws:-indisponivel}; esperado: av2."
fi
if [ -f "$TFDIR/terraform.tfstate" ] && grep -q '"resources"' "$TFDIR/terraform.tfstate" 2>/dev/null; then
  info "ATENCAO: ha terraform.tfstate local com recursos; o estado deve ficar no backend remoto."
fi
linha

echo "${B}Criterio 2 — outputs e nomes padronizados${X}"
B_RAW="$(tfout lake_raw_bucket)"; B_TRU="$(tfout lake_trusted_bucket)"; B_REF="$(tfout lake_refined_bucket)"
RESULTS="$(tfout athena_results_bucket_name)"; WG="$(tfout workgroup_name)"
DB_RAW="$(tfout database_raw)"; DB_TRU="$(tfout database_trusted)"; DB_REF="$(tfout database_refined)"
T_RAW="$(tfout tabela_raw)"; T_TRU="$(tfout tabela_trusted)"; T_REF="$(tfout tabela_refined)"
P_ENG="$(tfout papel_engenharia_arn)"; P_ANA="$(tfout papel_analista_arn)"
META="$(tfout meta_bytes_consulta)"
faltou=""
for nome in B_RAW B_TRU B_REF RESULTS WG DB_RAW DB_TRU DB_REF T_RAW T_TRU T_REF P_ENG P_ANA META; do
  [ -z "${!nome}" ] && faltou="$faltou $nome"
done
if [ -n "$faltou" ]; then
  fail "2" 10 "faltaram outputs:$faltou"
else
  info "buckets: $B_RAW $B_TRU $B_REF $RESULTS · wg: $WG"
  info "tabelas: $DB_RAW.$T_RAW $DB_TRU.$T_TRU $DB_REF.$T_REF"
  if [ "$B_RAW" = "${PREFIXO}-lake-raw" ] && [ "$B_TRU" = "${PREFIXO}-lake-trusted" ] \
     && [ "$B_REF" = "${PREFIXO}-lake-refined" ] && [ "$RESULTS" = "${PREFIXO}-athena-results" ] \
     && [ "$WG" = "${PREFIXO}-athena-wg" ] && [ "$DB_RAW" = "eda262_${GRUPO}_raw" ] \
     && [ "$DB_TRU" = "eda262_${GRUPO}_trusted" ] && [ "$DB_REF" = "eda262_${GRUPO}_refined" ]; then
    pass "2" 10 "outputs existem e seguem eda262-gNN-lake-<camada>."
  else
    fail "2" 10 "outputs existem, mas algum nome foge do padrao."
  fi
fi
linha

echo "${B}Criterio 3 — tags, formato e particionamento das tabelas${X}"
ok3=1
for b in "$B_RAW" "$B_TRU" "$B_REF" "$RESULTS"; do
  tags="$(aws s3api get-bucket-tagging --bucket "$b" --region "$REGIAO" \
    --query "TagSet[?Key=='turma' || Key=='grupo' || Key=='projeto'].[Key,Value]" --output text 2>/dev/null | sort | tr '\t\n' '= ' || true)"
  info "$b: ${tags:-sem tags}"
  [ "$tags" = "grupo=$GRUPO projeto=engenharia-de-dados turma=eda262 " ] || ok3=0
done
for par in "$DB_RAW:$T_RAW:OpenCSVSerde" "$DB_TRU:$T_TRU:ParquetHiveSerDe" "$DB_REF:$T_REF:ParquetHiveSerDe"; do
  IFS=: read -r db t serde_esperado <<< "$par"
  dados="$(aws glue get-table --region "$REGIAO" --database-name "$db" --name "$t" \
    --query "Table.[StorageDescriptor.SerdeInfo.SerializationLibrary, join(',', PartitionKeys[].Name), Parameters.\"projection.enabled\"]" \
    --output text 2>/dev/null || true)"
  info "$db.$t: $dados"
  case "$dados" in
    *"$serde_esperado"*"ano,mes"*"true"*) ;;
    *) ok3=0 ;;
  esac
done
if [ "$ok3" = "1" ]; then
  pass "3" 10 "4 buckets com as 3 tags; raw em CSV, trusted e refined em Parquet, todas particionadas por ano/mes (projection)."
else
  fail "3" 10 "tags, formato ou particionamento nao batem com o contrato."
fi
linha

echo "${B}Criterio 4 — dados nas tres camadas${X}"
ok4=1
for par in "$B_RAW/anp:precos\.csv" "$B_TRU/precos:part-0\.parquet" "$B_REF/precos_uf_mes:part-0\.parquet"; do
  caminho="${par%%:*}"; padrao="${par#*:}"
  objs="$(aws s3 ls "s3://$caminho/" --recursive --region "$REGIAO" 2>/dev/null || true)"
  n="$(printf '%s\n' "$objs" | grep -cE "ano=[0-9]{4}/mes=[0-9]{2}/$padrao$" || true)"
  outros="$(printf '%s\n' "$objs" | grep -vE "ano=[0-9]{4}/mes=[0-9]{2}/$padrao$" | grep -c . || true)"
  bytes="$(printf '%s\n' "$objs" | awk '{s += $3} END {print s + 0}')"
  info "s3://$caminho/: $n particoes, $bytes bytes, $outros objetos fora do padrao"
  { [ "${n:-0}" -ge 1 ] && [ "${outros:-0}" = "0" ]; } || ok4=0
done
if [ "$ok4" = "1" ]; then
  pass "4" 10 "um arquivo por particao ano=AAAA/mes=MM em cada camada."
else
  fail "4" 10 "alguma camada vazia ou com arquivo fora do layout de particao."
fi
linha

echo "${B}Criterio 5 — pergunta de negocio, custo e meta${X}"
R5="$(roda_query "$(consulta_negocio)" "$DB_REF" "$WG")"
qid="$(echo "$R5" | cut -d'|' -f1)"; estado="$(echo "$R5" | cut -d'|' -f2)"
bytes_query="$(echo "$R5" | cut -d'|' -f3)"; motivo="$(echo "$R5" | cut -d'|' -f4-)"
info "query_id=$qid estado=$estado bytes=$bytes_query meta=$META"
if [ "$estado" = "SUCCEEDED" ]; then
  custo="$(awk -v b="$bytes_query" 'BEGIN { printf "%.8f", (b / 1099511627776) * 5 }')"
  info "custo_estimado_usd=$custo (o Athena cobra no minimo 10 MB por consulta)"
  aws athena get-query-results --region "$REGIAO" --query-execution-id "$qid" \
    --query "ResultSet.Rows[0:6].Data[].VarCharValue" --output table 2>/dev/null || true
  if [ "${bytes_query:-0}" -le "${META:-0}" ] 2>/dev/null; then
    pass "5" 20 "pergunta respondida na refined; $bytes_query bytes <= meta de $META bytes."
  else
    fail "5" 20 "pergunta respondida, mas $bytes_query bytes passou da meta de $META bytes."
  fi
else
  fail "5" 20 "consulta nao respondeu. estado=$estado motivo=${motivo:0:160}"
fi
linha

echo "${B}Criterio 6 — backfill e ingestao idempotente${X}"
SQL_BF="SELECT count(*) FROM $T_TRU WHERE ano = '$BACKFILL_ANO' AND mes = '$BACKFILL_MES'"
SQL_CH="SELECT count(*) FROM (SELECT cnpj, produto, data_coleta FROM $T_TRU WHERE ano = '$BACKFILL_ANO' AND mes = '$BACKFILL_MES' GROUP BY 1, 2, 3)"
antes="$(valor_escalar "$SQL_BF" "$DB_TRU" "$WG")"
info "backfill $BACKFILL_ANO-$BACKFILL_MES na trusted: ${antes:-?} linhas (esperado $BACKFILL_LINHAS)"
if [ "$RECARGA" = "1" ]; then
  info "recarregando $BACKFILL_ANO-$BACKFILL_MES com carregar.sh (apaga a particao e copia de novo)..."
  if "$CARREGAR" "$BACKFILL_ANO-$BACKFILL_MES" >/dev/null 2>&1; then
    depois="$(valor_escalar "$SQL_BF" "$DB_TRU" "$WG")"
  else
    depois="ERRO_CARGA"
  fi
else
  info "--sem-recarga: usando a contagem atual como 'depois'."
  depois="$antes"
fi
chaves="$(valor_escalar "$SQL_CH" "$DB_TRU" "$WG")"
info "depois da recarga: ${depois:-?} linhas · chaves distintas: ${chaves:-?}"
if [ "$antes" = "$BACKFILL_LINHAS" ] && [ "$depois" = "$antes" ] && [ "$chaves" = "$antes" ]; then
  pass "6" 15 "particao de backfill presente; recarregar nao mudou o count(*) e nao ha chave duplicada."
else
  fail "6" 15 "backfill ausente, recarga duplicou linhas ou ha chave repetida (antes=$antes depois=$depois chaves=$chaves)."
fi
linha

echo "${B}Criterio 7 — Lake Formation: registro e permissao por camada${X}"
ok7=1
registrados="$(aws lakeformation list-resources --region "$REGIAO" --query "ResourceInfoList[].ResourceArn" --output text 2>/dev/null | tr '\t' '\n' || true)"
for b in "$B_RAW" "$B_TRU" "$B_REF"; do
  if printf '%s\n' "$registrados" | grep -qE ":::$b$"; then info "registrado: $b"; else info "NAO registrado: $b"; ok7=0; fi
done
for par in "$DB_RAW:$T_RAW" "$DB_TRU:$T_TRU" "$DB_REF:$T_REF"; do
  db="${par%%:*}"; t="${par#*:}"
  iap="$(aws lakeformation list-permissions --region "$REGIAO" --resource "{\"Table\":{\"DatabaseName\":\"$db\",\"Name\":\"$t\"}}" \
    --query "PrincipalResourcePermissions[?Principal.DataLakePrincipalIdentifier=='IAM_ALLOWED_PRINCIPALS'] | length(@)" --output text 2>/dev/null || echo "?")"
  info "$db.$t: IAM_ALLOWED_PRINCIPALS=${iap}"
  [ "$iap" = "0" ] || ok7=0
done
for c in raw trusted refined; do
  case "$c" in raw) db="$DB_RAW" ;; trusted) db="$DB_TRU" ;; refined) db="$DB_REF" ;; esac
  ps="$(principais_select "$db")"
  tem_eng=0; tem_ana=0
  printf '%s\n' "$ps" | grep -qxF "$P_ENG" && tem_eng=1
  printf '%s\n' "$ps" | grep -qxF "$P_ANA" && tem_ana=1
  info "$c: engenharia=$tem_eng analista=$tem_ana"
  case "$c" in
    raw|trusted) [ "$tem_eng" = "1" ] && [ "$tem_ana" = "0" ] || ok7=0 ;;
    refined)     [ "$tem_ana" = "1" ] && [ "$tem_eng" = "0" ] || ok7=0 ;;
  esac
done
if [ "$ok7" = "1" ]; then
  pass "7" 15 "3 buckets registrados, sem IAM_ALLOWED_PRINCIPALS; engenharia em raw+trusted, analista so em refined."
else
  fail "7" 15 "registro, revogacao ou matriz de permissoes nao bate (detalhes acima)."
fi
linha

echo "${B}Criterio 8 — prova pratica: papel analista${X}"
cred="$(aws sts assume-role --role-arn "$P_ANA" --role-session-name verifica-analista \
  --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" --output text 2>/dev/null || true)"
if [ -z "$cred" ]; then
  fail "8" 10 "nao consegui assumir $P_ANA (sts:AssumeRole negado?)."
else
  read -r ak sk st <<< "$cred"
  como_analista() {
    ( unset AWS_PROFILE AWS_DEFAULT_PROFILE
      export AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" AWS_SESSION_TOKEN="$st"
      roda_query "$@" )
  }
  ref="$(como_analista "SELECT count(*) FROM $T_REF WHERE ano = '2025'" "$DB_REF" "$WG")"
  tru="$(como_analista "SELECT count(*) FROM $T_TRU WHERE ano = '2025'" "$DB_TRU" "$WG")"
  e_ref="$(echo "$ref" | cut -d'|' -f2)"; e_tru="$(echo "$tru" | cut -d'|' -f2)"
  info "analista na refined: $e_ref"
  info "analista na trusted: $e_tru $(echo "$tru" | cut -d'|' -f4- | cut -c1-120)"
  if [ "$e_ref" = "SUCCEEDED" ] && [ "$e_tru" != "SUCCEEDED" ]; then
    pass "8" 10 "analista le a refined e e barrado na trusted."
  else
    fail "8" 10 "esperado: refined SUCCEEDED e trusted negada."
  fi
fi
linha

echo "${B}Criterio 9 — DECISOES.md${X}"
if [ -f "$DECISOES" ]; then
  nd="$(grep -ciE '^## DECIS[ÃA]O\s*0?[1-5]' "$DECISOES" 2>/dev/null || true)"
  np="$(grep -c 'PENDENTE' "$DECISOES" 2>/dev/null || true)"
  if [ "${nd:-0}" -ge 5 ] && [ "${np:-0}" = "0" ]; then
    pass "9" 0 "$nd decisoes, nenhuma PENDENTE; conteudo e nota sao avaliados manualmente."
  else
    fail "9" 0 "DECISOES.md com $nd decisoes e $np itens PENDENTE."
  fi
else
  fail "9" 0 "nao achei DECISOES.md na raiz."
fi
linha

echo "${B}Resumo automatico: $notas/$total pontos-percentuais${X}"
info "depois do terraform destroy, rode ./verificacao/verifica.sh --pos-destroy."
