#!/usr/bin/env python3
"""Ingere os precos de gasolina e etanol da ANP nas camadas raw, trusted e refined.

Cada mes vira uma particao ano=AAAA/mes=MM com nome de arquivo fixo.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import shutil
import sys
import urllib.request
from collections import Counter
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

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

SCHEMA_TRUSTED = pa.schema([
    ("cnpj", pa.string()),
    ("produto", pa.string()),
    ("data_coleta", pa.date32()),
    ("valor_venda", pa.float64()),
    ("bandeira", pa.string()),
    ("revenda", pa.string()),
    ("regiao", pa.string()),
    ("uf", pa.string()),
    ("municipio", pa.string()),
    ("bairro", pa.string()),
])
SCHEMA_REFINED = pa.schema([
    ("uf", pa.string()),
    ("produto", pa.string()),
    ("tipo_bandeira", pa.string()),
    ("coletas", pa.int64()),
    ("soma_valor", pa.float64()),
    ("preco_min", pa.float64()),
    ("preco_max", pa.float64()),
])


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


def particao(mes: str) -> str:
    ano, mm = mes.split("-")
    return f"ano={ano}/mes={mm}"


def baixa(url: str, destino: Path) -> None:
    destino.parent.mkdir(parents=True, exist_ok=True)
    tmp = destino.with_suffix(".part")
    req = urllib.request.Request(url, headers={"User-Agent": "eda262-ingestao/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp, tmp.open("wb") as fh:
        while bloco := resp.read(1 << 20):
            fh.write(bloco)
    tmp.replace(destino)


def preco(texto: str) -> float | None:
    try:
        return float(texto.strip().replace(",", "."))
    except ValueError:
        return None


def data_coleta(texto: str) -> dt.date | None:
    try:
        return dt.datetime.strptime(texto.strip(), "%d/%m/%Y").date()
    except ValueError:
        return None


def limpa(bruto: Path, mes: str) -> tuple[list[dict], Counter]:
    c: Counter = Counter()
    por_chave: dict[tuple, dict] = {}
    conflito: set[tuple] = set()
    with bruto.open(encoding="utf-8-sig", newline="") as fh:
        linhas = csv.reader(fh, delimiter=";")
        cab = next(linhas)
        if cab != CABECALHO:
            raise SystemExit(f"{bruto}: cabecalho diferente do esperado: {cab}")

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
            data = data_coleta(reg["Data da Coleta"])
            if data is None or data.strftime("%Y-%m") != mes:
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
                conflito.add(chave)
                del por_chave[chave]
                c["descarte_conflito"] += 2

    linhas = sorted(por_chave.values(),
                    key=lambda e: (e["uf"], e["produto"], e["data_coleta"], e["cnpj"]))
    c["linhas_trusted"] = len(linhas)
    return linhas, c


def agrega(linhas: list[dict]) -> list[dict]:
    grupos: dict[tuple, dict] = {}
    for e in linhas:
        tipo = "BRANCA" if e["bandeira"] == "BRANCA" else "BANDEIRA"
        g = grupos.setdefault((e["uf"], e["produto"], tipo), {
            "uf": e["uf"], "produto": e["produto"], "tipo_bandeira": tipo,
            "coletas": 0, "soma_valor": 0.0, "preco_min": e["valor_venda"],
            "preco_max": e["valor_venda"],
        })
        g["coletas"] += 1
        g["soma_valor"] += e["valor_venda"]
        g["preco_min"] = min(g["preco_min"], e["valor_venda"])
        g["preco_max"] = max(g["preco_max"], e["valor_venda"])
    for g in grupos.values():
        g["soma_valor"] = round(g["soma_valor"], 2)
    return [grupos[k] for k in sorted(grupos)]


def grava_parquet(linhas: list[dict], schema: pa.Schema, pasta: Path) -> int:
    if pasta.exists():
        shutil.rmtree(pasta)
    pasta.mkdir(parents=True)
    tabela = pa.Table.from_pylist(linhas, schema=schema)
    destino = pasta / "part-0.parquet"
    pq.write_table(tabela, destino, compression="snappy")
    return destino.stat().st_size


def processa_mes(mes: str, url: str, saida: Path, rebaixar: bool) -> Counter:
    part = particao(mes)
    bruto = saida / "raw" / "anp" / part / "precos.csv"
    if rebaixar or not bruto.exists():
        print(f"{mes}  baixando {url}", file=sys.stderr)
        baixa(url, bruto)

    linhas, c = limpa(bruto, mes)
    refined = agrega(linhas)
    c["bytes_raw"] = bruto.stat().st_size
    c["bytes_trusted"] = grava_parquet(linhas, SCHEMA_TRUSTED, saida / "trusted" / "precos" / part)
    c["bytes_refined"] = grava_parquet(refined, SCHEMA_REFINED,
                                       saida / "refined" / "precos_uf_mes" / part)
    c["linhas_refined"] = len(refined)

    contagens = saida / "contagens" / f"{mes}.json"
    contagens.parent.mkdir(parents=True, exist_ok=True)
    contagens.write_text(json.dumps(dict(sorted(c.items())), indent=2) + "\n", encoding="utf-8")
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
        c = processa_mes(mes, fontes[mes], args.saida, args.rebaixar)
        total.update(c)
        print(f"{mes}  raw={fmt(c['linhas_raw'])}  trusted={fmt(c['linhas_trusted'])}  "
              f"descartes={fmt(c['linhas_raw'] - c['linhas_trusted'])}  "
              f"refined={fmt(c['linhas_refined'])}")

    raw = total["linhas_raw"] or 1
    print()
    print(f"meses ................... {len(lista)} ({lista[0]} a {lista[-1]})")
    print(f"raw (CSV) ............... {fmt(total['linhas_raw'])} linhas  {fmt(total['bytes_raw'])} bytes")
    print(f"trusted (Parquet) ....... {fmt(total['linhas_trusted'])} linhas  {fmt(total['bytes_trusted'])} bytes")
    print(f"refined (Parquet) ....... {fmt(total['linhas_refined'])} linhas  {fmt(total['bytes_refined'])} bytes")
    print("sujeira encontrada (nao descarta):")
    for k in ("virgula_decimal", "cnpj_com_espaco", "texto_corrompido", "valor_compra_preenchido"):
        print(f"  {k:<28} {fmt(total[k]):>10}  ({100 * total[k] / raw:.2f}%)")
    print("descartes:")
    descartes = sorted(k for k in total if k.startswith("descarte_"))
    for k in descartes:
        print(f"  {k:<28} {fmt(total[k]):>10}  ({100 * total[k] / raw:.3f}%)")
    if not descartes:
        print("  nenhum")
    return 0


if __name__ == "__main__":
    sys.exit(main())
