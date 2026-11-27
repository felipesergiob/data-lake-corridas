#!/usr/bin/env bash
set -euo pipefail

acao="$1"
regiao="$2"
principal="$3"

PY=python3
"$PY" --version >/dev/null 2>&1 || PY=python

configuracao="$(aws lakeformation get-data-lake-settings --region "$regiao" --query DataLakeSettings --output json </dev/null)"

e_admin() {
  printf '%s' "$configuracao" | "$PY" -c '
import json, sys
c = json.load(sys.stdin)
sys.exit(0 if any(a["DataLakePrincipalIdentifier"] == sys.argv[1] for a in c.get("DataLakeAdmins", [])) else 1)
' "$principal"
}

grava() {
  local operacao="$1" nova
  nova="$(printf '%s' "$configuracao" | "$PY" -c '
import json, sys
c = json.load(sys.stdin)
admins = [a for a in c.get("DataLakeAdmins", []) if a["DataLakePrincipalIdentifier"] != sys.argv[2]]
if sys.argv[1] == "adiciona":
    admins.append({"DataLakePrincipalIdentifier": sys.argv[2]})
c["DataLakeAdmins"] = admins
print(json.dumps(c))
' "$operacao" "$principal")"
  aws lakeformation put-data-lake-settings --region "$regiao" --data-lake-settings "$nova" </dev/null
}

case "$acao" in
  consulta)
    if e_admin; then printf '{"admin":"true"}'; else printf '{"admin":"false"}'; fi
    ;;
  adiciona)
    if e_admin; then
      echo "admin-lf: $principal ja e admin do Lake Formation"
    else
      grava adiciona
      echo "admin-lf: $principal adicionado aos admins do Lake Formation"
    fi
    ;;
  remove)
    if e_admin; then
      grava remove
      echo "admin-lf: $principal removido dos admins do Lake Formation"
    else
      echo "admin-lf: $principal ja nao e admin do Lake Formation"
    fi
    ;;
  *)
    echo "uso: $0 consulta|adiciona|remove <regiao> <principal>" >&2
    exit 2
    ;;
esac
