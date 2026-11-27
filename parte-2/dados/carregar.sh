#!/usr/bin/env bash
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
DADOS="$RAIZ/parte-2/dados"
TFDIR="${TFDIR:-$RAIZ/parte-2/terraform}"
REGIAO="${AWS_REGION:-us-east-1}"
PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || PY=python

[ $# -ge 1 ] || { echo "uso: $0 AAAA-MM [AAAA-MM]" >&2; exit 2; }
INICIO="$1"
FIM="${2:-$1}"

"$PY" "$DADOS/ingerir-anp.py" --inicio "$INICIO" --fim "$FIM"

RAW="$(terraform -chdir="$TFDIR" output -raw lake_raw_bucket)"
TRUSTED="$(terraform -chdir="$TFDIR" output -raw lake_trusted_bucket)"
REFINED="$(terraform -chdir="$TFDIR" output -raw lake_refined_bucket)"

MESES="$("$PY" -c "
import sys
a, m = map(int, sys.argv[1].split('-')); af, mf = map(int, sys.argv[2].split('-'))
while (a, m) <= (af, mf):
    print(f'{a:04d} {m:02d}'); a, m = (a + 1, 1) if m == 12 else (a, m + 1)
" "$INICIO" "$FIM")"

sobe() {
  local local_dir="$1" destino="$2"
  aws s3 rm "$destino" --recursive --region "$REGIAO" --only-show-errors
  aws s3 cp "$local_dir" "$destino" --recursive --region "$REGIAO" --only-show-errors
}

while read -r ano mes; do
  part="ano=$ano/mes=$mes"
  sobe "$DADOS/saida/raw/anp/$part/"                  "s3://$RAW/anp/$part/"
  sobe "$DADOS/saida/trusted/precos/$part/"           "s3://$TRUSTED/precos/$part/"
  sobe "$DADOS/saida/refined/precos_uf_mes/$part/"    "s3://$REFINED/precos_uf_mes/$part/"
  echo "carregado $ano-$mes nas tres camadas"
done <<< "$MESES"
