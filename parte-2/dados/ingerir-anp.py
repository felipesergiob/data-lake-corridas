#!/usr/bin/env python3
"""Ingere a serie historica de precos de combustiveis da ANP (gasolina e etanol).

Para cada mes do intervalo pedido:

1. baixa o CSV mensal listado em fontes-anp.csv para saida/raw/anp/ (o arquivo
   original, sem alteracao; se ja existir, reaproveita);
2. limpa e grava saida/trusted/precos/precos-AAAA-MM.json (JSON Lines).

Rodar de novo para o mesmo mes sobrescreve o mesmo arquivo trusted: nao duplica.

A lista de URLs fica em fontes-anp.csv porque a ANP nao segue um padrao de
nome entre anos (em 2026 ha nomes sem .csv e ate "cados-abertos").
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
import urllib.request
from collections import Counter
from pathlib import Path

AQUI = Path(__file__).resolve().parent

CABECALHO = [
    "Regiao - Sigla", "Estado - Sigla", "Municipio", "Revenda", "CNPJ da Revenda",
    "Nome da Rua", "Numero Rua", "Complemento", "Bairro", "Cep", "Produto",
    "Data da Coleta", "Valor de Venda", "Valor de Compra", "Unidade de Medida", "Bandeira",
]
UNIDADE = "R$ / litro"
PRECO_MIN = 1.00
PRECO_MAX = 15.00
CORROMPIDO = "�"


def le_fontes(arquivo: Path) -> dict[str, str]:
    with arquivo.open(encoding="utf-8", newline="") as fh:
        return {f"{r['ano']}-{r['mes']}": r["url"] for r in csv.DictReader(fh)}


def meses(inicio: str, fim: str) -> list[str]:
    a, m = map(int, inicio.split("-"))
    af, mf = map(int, fim.split("-"))
    saida = []
    while (a, m) <= (af, mf):
        saida.append(f"{a:04d}-{m:02d}")
        a, m = (a + 1, 1) if m == 12 else (a, m + 1)
    return saida


def baixa(url: str, destino: Path) -> None:
    destino.parent.mkdir(parents=True, exist_ok=True)
    tmp = destino.with_suffix(".part")
    req = urllib.request.Request(url, headers={"User-Agent": "eda262-ingestao/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp, tmp.open("wb") as fh:
        while bloco := resp.read(1 << 20):
            fh.write(bloco)
    tmp.replace(destino)


def preco(texto: str) -> float | None:
    """'6,29' -> 6.29. Aceita '5,9' e '6'. Devolve None se nao for numero."""
    try:
        return float(texto.strip().replace(",", "."))
    except ValueError:
        return None


def data_iso(texto: str) -> str | None:
    """'31/01/2025' -> '2025-01-31'."""
    partes = texto.strip().split("/")
    if len(partes) != 3 or not all(p.isdigit() for p in partes):
        return None
    d, m, a = partes
    return f"{a}-{m.zfill(2)}-{d.zfill(2)}"


def limpa_mes(bruto: Path, destino: Path, mes: str) -> Counter:
    c: Counter = Counter()
    with bruto.open(encoding="utf-8-sig", newline="") as fh:
        linhas = csv.reader(fh, delimiter=";")
        cab = next(linhas)
        if cab != CABECALHO:
            raise SystemExit(f"{bruto.name}: cabecalho diferente do esperado: {cab}")

        por_chave: dict[tuple[str, str, str], dict] = {}
        conflito: set[tuple[str, str, str]] = set()
        for r in linhas:
            c["linhas_raw"] += 1
            if len(r) != len(CABECALHO):
                c["descarte_largura"] += 1
                continue
            reg = dict(zip(CABECALHO, r))
            if reg["Valor de Compra"].strip():
                c["valor_compra_preenchido"] += 1
            if "," in reg["Valor de Venda"]:
                c["virgula_decimal"] += 1
            if reg["CNPJ da Revenda"] != reg["CNPJ da Revenda"].strip():
                c["cnpj_com_espaco"] += 1
            if any(CORROMPIDO in v for v in r):
                c["texto_corrompido"] += 1

            if reg["Unidade de Medida"].strip() != UNIDADE:
                c["descarte_unidade"] += 1
                continue
            valor = preco(reg["Valor de Venda"])
            if valor is None or not (PRECO_MIN <= valor <= PRECO_MAX):
                c["descarte_preco_fora_faixa"] += 1
                continue
            data = data_iso(reg["Data da Coleta"])
            if data is None or not data.startswith(mes):
                c["descarte_data"] += 1
                continue
            cnpj = "".join(ch for ch in reg["CNPJ da Revenda"] if ch.isdigit())
            if len(cnpj) != 14:
                c["descarte_cnpj"] += 1
                continue

            evento = {
                "cnpj": cnpj,
                "produto": reg["Produto"].strip().upper(),
                "data_coleta": data,
                "valor_venda": round(valor, 2),
                "bandeira": reg["Bandeira"].strip().upper(),
                "revenda": reg["Revenda"].strip().upper(),
                "regiao": reg["Regiao - Sigla"].strip().upper(),
                "uf": reg["Estado - Sigla"].strip().upper(),
                "municipio": reg["Municipio"].strip().upper(),
                "bairro": reg["Bairro"].strip().upper(),
            }
            chave = (evento["cnpj"], evento["produto"], evento["data_coleta"])
            if chave in conflito:
                c["descarte_conflito"] += 1
                continue
            anterior = por_chave.get(chave)
            if anterior is None:
                por_chave[chave] = evento
            elif anterior == evento:
                c["descarte_duplicata_identica"] += 1
            else:
                # Mesmo posto, produto e dia com precos diferentes: nao ha como
                # saber qual vale, entao as duas versoes saem da trusted.
                conflito.add(chave)
                del por_chave[chave]
                c["descarte_conflito"] += 2

    destino.parent.mkdir(parents=True, exist_ok=True)
    tmp = destino.with_suffix(".part")
    with tmp.open("w", encoding="utf-8", newline="\n") as fh:
        for evento in por_chave.values():
            linha = json.dumps(evento, ensure_ascii=False, separators=(",", ":")) + "\n"
            c["bytes_trusted"] += len(linha.encode("utf-8"))
            fh.write(linha)
    tmp.replace(destino)
    c["linhas_trusted"] = len(por_chave)
    c["bytes_raw"] = bruto.stat().st_size
    return c


def fmt(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Ingere precos de gasolina/etanol da ANP.")
    p.add_argument("--inicio", required=True, help="primeiro mes, AAAA-MM")
    p.add_argument("--fim", help="ultimo mes, AAAA-MM (padrao: igual a --inicio)")
    p.add_argument("--saida", type=Path, default=AQUI / "saida")
    p.add_argument("--fontes", type=Path, default=AQUI / "fontes-anp.csv")
    p.add_argument("--rebaixar", action="store_true", help="baixa de novo mesmo se o raw existir")
    args = p.parse_args(argv)

    fontes = le_fontes(args.fontes)
    lista = meses(args.inicio, args.fim or args.inicio)
    faltam = [m for m in lista if m not in fontes]
    if faltam:
        p.error(f"meses sem URL em {args.fontes.name}: {', '.join(faltam)}")

    total: Counter = Counter()
    for mes in lista:
        bruto = args.saida / "raw" / "anp" / f"precos-{mes}.csv"
        if args.rebaixar or not bruto.exists():
            print(f"{mes}  baixando {fontes[mes]}", file=sys.stderr)
            baixa(fontes[mes], bruto)
        c = limpa_mes(bruto, args.saida / "trusted" / "precos" / f"precos-{mes}.json", mes)
        total.update(c)
        print(f"{mes}  raw={fmt(c['linhas_raw'])}  trusted={fmt(c['linhas_trusted'])}  "
              f"descartes={fmt(c['linhas_raw'] - c['linhas_trusted'])}")

    raw = total["linhas_raw"]
    print()
    print(f"meses ................... {len(lista)} ({lista[0]} a {lista[-1]})")
    print(f"linhas raw .............. {fmt(raw)}  ({fmt(total['bytes_raw'])} bytes CSV)")
    print(f"linhas trusted .......... {fmt(total['linhas_trusted'])}  ({fmt(total['bytes_trusted'])} bytes JSON Lines)")
    print("sujeira encontrada (nao descarta):")
    for k in ("virgula_decimal", "cnpj_com_espaco", "texto_corrompido", "valor_compra_preenchido"):
        print(f"  {k:<28} {fmt(total[k]):>10}  ({100 * total[k] / raw:.2f}%)")
    print("descartes:")
    for k in sorted(k for k in total if k.startswith("descarte_")):
        print(f"  {k:<28} {fmt(total[k]):>10}  ({100 * total[k] / raw:.3f}%)")
    print()
    print("suba com:")
    print("  aws s3 cp saida/trusted/precos/ s3://BUCKET/trusted/precos/ --recursive --region us-east-1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
