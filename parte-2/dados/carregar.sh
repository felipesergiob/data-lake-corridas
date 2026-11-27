#!/usr/bin/env bash
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
DADOS="$RAIZ/parte-2/dados"
TFDIR="${TFDIR:-$RAIZ/parte-2/terraform}"
REGIAO="${AWS_REGION:-us-east-1}"
PY="${PYTHON:-python3}"
"$PY" --version >/dev/null 2>&1 || PY=python

[ $# -ge 1 ] || { echo "uso: $0 AAAA-MM [AAAA-MM]" >&2; exit 2; }
INICIO="$1"
FIM="${2:-$1}"
[[ "$INICIO" =~ ^[0-9]{4}-[0-9]{2}$ && "$FIM" =~ ^[0-9]{4}-[0-9]{2}$ ]] || { echo "use AAAA-MM" >&2; exit 2; }

"$PY" "$DADOS/ingerir-anp.py" --inicio "$INICIO" --fim "$FIM"

RAW="$(terraform -chdir="$TFDIR" output -raw lake_raw_bucket)"
TRUSTED="$(terraform -chdir="$TFDIR" output -raw lake_trusted_bucket)"
REFINED="$(terraform -chdir="$TFDIR" output -raw lake_refined_bucket)"

sobe() {
  local local_dir="$1" destino="$2"
  aws s3 rm "$destino" --recursive --region "$REGIAO" --only-show-errors </dev/null
  aws s3 cp "$local_dir" "$destino" --recursive --region "$REGIAO" --only-show-errors </dev/null
}

ano=$((10#${INICIO%-*})); mes=$((10#${INICIO#*-}))
ano_fim=$((10#${FIM%-*})); mes_fim=$((10#${FIM#*-}))
while (( ano * 100 + mes <= ano_fim * 100 + mes_fim )); do
  part="$(printf 'ano=%04d/mes=%02d' "$ano" "$mes")"
  sobe "$DADOS/saida/raw/anp/$part/"               "s3://$RAW/anp/$part/"
  sobe "$DADOS/saida/trusted/precos/$part/"        "s3://$TRUSTED/precos/$part/"
  sobe "$DADOS/saida/refined/precos_uf_mes/$part/" "s3://$REFINED/precos_uf_mes/$part/"
  echo "carregado $part nas tres camadas"
  if (( mes == 12 )); then ano=$((ano + 1)); mes=1; else mes=$((mes + 1)); fi
done
