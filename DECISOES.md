# DECISOES.md — Projeto (tema: preços de combustíveis)

Na unidade 2, a pedido do docente, o projeto trocou de tema e de dataset.
O tema de corridas urbanas da AV1 está registrado em `parte-1/` e em
`parte-1/DECISOES.md`.

**Cenário:** preços de gasolina e etanol nos postos do Brasil, coletados pela
ANP no Levantamento de Preços de Combustíveis.

**Pergunta de negócio:** em quais estados a gasolina comum é mais cara, e os
postos com bandeira cobram mais que os de bandeira branca?

**Fonte:** ANP, "Série histórica de preços de combustíveis", com um CSV por mês
(gasolina e etanol). Os links de cada mês estão em `parte-2/dados/fontes-anp.csv`
(de 2023-01 a 2026-10, 46 meses). A lista existe porque a ANP não mantém um
padrão de nome: em 2026 há arquivos sem `.csv` e até um com `cados-abertos` no
nome.

Medição local da ingestão, feita em 2026-11-26:

- comando: `python3 parte-2/dados/ingerir-anp.py --inicio 2025-01 --fim 2025-12`
- janela: 2025-01 a 2025-12 (12 meses)
- raw: **555.836 linhas**, 95.168.702 bytes em CSV
- trusted: **555.836 linhas**, **128.703.128 bytes** em JSON Lines
- produtos: GASOLINA 212.411 · ETANOL 177.742 · GASOLINA ADITIVADA 165.683

## DECISAO 01 — grão da tabela trusted

A tabela `precos_trusted` tem grão de **uma linha por coleta de preço: posto ×
produto × dia**. É o grão do próprio arquivo da ANP: cada linha do CSV é um
preço que o pesquisador anotou num posto, para um produto, numa data.

Não agregamos na trusted (por exemplo, para preço médio por município e
semana) porque a pergunta compara bandeira branca com bandeira dentro do mesmo
estado. Agregar antes perderia a bandeira de cada posto. Em 2025, a pergunta
usa **212.411 coletas** de gasolina comum.

## DECISAO 02 — chave lógica

A chave lógica é composta: `cnpj` + `produto` + `data_coleta`. Um posto não tem
dois preços oficiais do mesmo produto no mesmo dia.

Medido localmente em 2025: **555.836 linhas e 555.836 chaves distintas**, sem
duplicata.

Medido em 2023–2024 (1.221.656 linhas), a fonte tem duplicatas reais, todas em
**2024-06**:

- **8 linhas** repetidas de forma idêntica: mantemos uma e descartamos a cópia;
- **4 pares (8 linhas)** com a mesma chave e preços diferentes: descartamos as
  duas versões, porque não há como saber qual vale.

Esses 16 descartes são **0,001%** da janela. O mês 2024-06 será o backfill da
AV2, justamente porque exercita essa regra.

Consulta de comprovação no Athena:

```sql
SELECT count(*) AS linhas,
       count(DISTINCT (cnpj, produto, data_coleta)) AS chaves_distintas
FROM precos_trusted;
```

Resultado no Athena: **PENDENTE** (rodar com a stack no ar; o esperado é 555.836 / 555.836).

## DECISAO 03 — formato, schema declarado e limpeza

A trusted continua em **JSON Lines** com schema declarado no Terraform (sem
Crawler), igual à AV1. A troca para Parquet é requisito da AV2 e entra em
seguida. São 10 colunas: `cnpj`, `produto`, `data_coleta` (date), `valor_venda`
(double), `bandeira`, `revenda`, `regiao`, `uf`, `municipio` e `bairro`.

A limpeza fica na ingestão (`ingerir-anp.py`), não no SQL. Assim, a trusted só
recebe dado válido. Sujeira medida no raw de 2025:

| Sujeira na fonte | Linhas | % | Tratamento |
| --- | ---: | ---: | --- |
| preço com vírgula decimal (`6,29`) | 555.836 | 100% | vira `double` 6.29 |
| CNPJ com espaço à esquerda e máscara | 555.836 | 100% | só os 14 dígitos |
| data em `dd/mm/aaaa` | 555.836 | 100% | vira `date` ISO |
| `Valor de Compra` vazio | 555.836 | 100% | coluna descartada |
| `Unidade de Medida` constante (`R$ / litro`) | 555.836 | 100% | coluna descartada |

Em 2023–2024 também apareceram preços sem as duas casas decimais (`5,9` e
`6`, por exemplo 917 e 79 linhas em 2024-06). O parser aceita os dois formatos.
Preço fora da faixa de R$ 1,00 a R$ 15,00 por litro é descartado: **0 linhas**
nos 36 meses medidos (1.777.476 linhas; mínimo de R$ 2,63 e máximo de R$ 9,79).

Custo aceito: o JSON ficou **35% maior** que o CSV original (128.703.128 contra
95.168.702 bytes), porque repete o nome das colunas em cada linha. A AV2 resolve
isso com Parquet.

A tabela **não** usa `use.null.for.invalid.data`, ao contrário da AV1. Como a
limpeza acontece antes, um valor inválido na trusted indica bug na ingestão, e
preferimos que o Athena falhe com `BAD_DATA` a esconder o erro como `null`.

Limitação conhecida e não tratada: o bairro é texto livre da ANP e tem erros de
digitação (por exemplo, `IMBIRIRBEIRA` ao lado de `IMBIRIBEIRA` no Recife). A
pergunta de negócio agrega por estado, então isso não afeta a resposta.

## DECISAO 04 — ainda sem particionamento

A ingestão grava **um arquivo por mês** (`trusted/precos/precos-AAAA-MM.json`),
todos no mesmo prefixo e sem partição no Glue. Rodar o mesmo mês de novo
sobrescreve o mesmo arquivo, então a carga não duplica.

O custo aceito é que toda consulta varre os 12 arquivos inteiros (**128.703.128
bytes**), mesmo que filtre um único mês. Particionar por ano e mês é o próximo
passo da AV2.

## DECISAO 05 — teto de custo no Athena

O workgroup mantém `BytesScannedCutoffPerQuery = 268435456` bytes (256 MiB). O
dataset de 2025 ocupa **47,9%** desse teto: a pergunta passa, e uma consulta
acidental muito acima do volume esperado é barrada.

Custo esperado da pergunta de negócio, sem poda:
`128703128 / 1099511627776 * 5` = **US$ 0,00058527**.

Medido no Athena (`evidencias/consulta-athena-parte-2.txt`): **PENDENTE**.

- `QueryExecutionId`: PENDENTE
- `DataScannedInBytes`: PENDENTE
- tempo de execução: PENDENTE

Resposta esperada, calculada localmente sobre a trusted: o **Acre** tem a
gasolina comum mais cara (R$ 7,671), seguido de Amazonas (R$ 7,226) e Roraima
(R$ 6,948). A bandeira nem sempre cobra mais: no Amazonas, os postos com
bandeira são **R$ 0,605 mais baratos** que os de bandeira branca. Em
Pernambuco, a média é R$ 6,330 e os postos com bandeira cobram R$ 0,076 a mais.
