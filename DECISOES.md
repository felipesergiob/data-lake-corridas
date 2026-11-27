# DECISOES.md — Projeto (tema: preços de combustíveis)

Na unidade 2 o projeto trocou de tema e de dataset: o docente pediu a troca
porque o dataset de corridas era o mesmo usado nos exercícios em sala. A AV1
continua registrada na tag `av1-entrega` e em `parte-1/` (decisões da AV1 em
`parte-1/DECISOES.md`).

**Cenário:** preços de gasolina e etanol nos postos do Brasil, coletados pela
ANP no Levantamento de Preços de Combustíveis.

**Pergunta de negócio:** em quais estados a gasolina comum é mais cara, e os
postos com bandeira cobram mais que os de bandeira branca?

**Fonte:** ANP, "Série histórica de preços de combustíveis", com um CSV por mês
(gasolina e etanol). Os links de cada mês estão em `parte-2/dados/fontes-anp.csv`
(de 2023-01 a 2026-10, 46 meses). A lista existe porque a ANP não mantém um
padrão de nome: em 2026 há arquivos sem `.csv` e até um com `cados-abertos` no
nome.

**Carga medida** (local, 2026-11-26, `parte-2/dados/carregar.sh`):

| Carga | Meses | Raw (CSV) | Trusted (Parquet) | Refined (Parquet) |
| --- | --- | ---: | ---: | ---: |
| base | 2025-01 a 2025-12 | 555.836 linhas · 95.168.702 B | 555.836 linhas · 5.936.460 B | 1.931 linhas · 63.972 B |
| backfill | 2024-06 | 49.974 linhas · 8.547.371 B | 49.958 linhas · 559.024 B | 160 linhas · 5.371 B |

Os números do Athena saem de `parte-2/consultas/medicoes.sql` (M1 a M5), que o
`evidencias/coletar-evidencias.sh` roda e salva em
`evidencias/medicoes-parte-2.txt`.

## Arquitetura em três camadas

| Camada | Bucket | Tabela | Formato | Grão |
| --- | --- | --- | --- | --- |
| raw | `eda262-g11-lake-raw` | `eda262_g11_raw.precos_raw` | CSV original da ANP | uma linha do CSV |
| trusted | `eda262-g11-lake-trusted` | `eda262_g11_trusted.precos` | Parquet + Snappy | uma coleta: posto × produto × dia |
| refined | `eda262-g11-lake-refined` | `eda262_g11_refined.precos_uf_mes` | Parquet + Snappy | UF × produto × tipo de bandeira × mês |

As três são particionadas por `ano=AAAA/mes=MM/`, com partition projection
declarada no Terraform.

## DECISAO 01 — grão de cada camada

- **raw:** uma linha do CSV, sem tocar no arquivo. É a prova do que a ANP
  publicou e permite refazer a trusted se uma regra de limpeza mudar.
- **trusted:** uma linha por coleta de preço (posto × produto × dia). É o grão
  da fonte depois da limpeza. Não agregamos aqui porque outras perguntas (por
  município, por distribuidora) precisam da coleta individual.
- **refined:** uma linha por UF × produto × tipo de bandeira (`BRANCA` ou
  `BANDEIRA`) × mês, já no formato da pergunta de negócio. Guarda `coletas` e
  `soma_valor` em vez da média, para que a média de vários meses seja exata:
  `sum(soma_valor) / sum(coletas)`. A média das médias mensais daria peso igual
  a meses com poucas coletas.

Medido: 2025 tem **555.836 coletas na trusted** e **1.931 linhas na refined**
(**288 vezes menos**). Conferimos localmente que a refined dá a mesma resposta
que a trusted, até a terceira casa (Acre R$ 7,671 nas duas).

Raw contra trusted no mês do backfill (M5 e M4 no Athena): esperado 49.974 contra
49.958. Medido: **PENDENTE**.

## DECISAO 02 — chaves

- **trusted:** `cnpj` + `produto` + `data_coleta`. Um posto não tem dois preços
  oficiais do mesmo produto no mesmo dia.
- **refined:** `uf` + `produto` + `tipo_bandeira` + `ano` + `mes`.

A fonte tem duplicatas reais, todas em **2024-06** (49.974 linhas):

- **8 linhas** repetidas de forma idêntica: mantemos uma e descartamos a cópia;
- **4 pares (8 linhas)** com a mesma chave e preços diferentes: descartamos as
  duas versões, porque não há como saber qual vale.

Esses 16 descartes são **0,032%** do mês. Em 2025 não há nenhuma duplicata: a
trusted tem **555.836 linhas e 555.836 chaves distintas** (medido localmente).

Comprovação no Athena (M1, trusted inteira): **PENDENTE** (esperado 605.794
linhas = 605.794 chaves, somando 2025 e o backfill).

## DECISAO 03 — formato

**raw em CSV, como baixado.** Separador `;`, vírgula decimal, BOM e CRLF ficam
como a ANP publicou. A tabela `precos_raw` lê tudo como `string`
(OpenCSVSerde), porque o raw não pode falhar por causa de um valor mal formado.

**trusted e refined em Parquet com Snappy.** Medido em 2025:

| Formato da trusted | Bytes | Comparação |
| --- | ---: | --- |
| CSV original (raw) | 95.168.702 | base |
| JSON Lines (como na migração da AV1) | 128.703.128 | +35% |
| **Parquet + Snappy** | **5.936.460** | **−93,8% contra o CSV, −95,4% contra o JSON** |

Além de menor, o Parquet é colunar. Numa partição da trusted (2025-01, 498.856
B), as colunas que a pergunta usa (`uf`, `produto`, `bandeira` e `valor_venda`)
ocupam **84.159 B (17%)**; `revenda`, `cnpj` e `bairro` respondem pela maior
parte do resto. O Athena lê só as colunas da consulta.

A limpeza acontece na ingestão (`ingerir-anp.py`), entre raw e trusted. Sujeira
medida no raw de 2025:

| Sujeira na fonte | Linhas | % | Tratamento na trusted |
| --- | ---: | ---: | --- |
| preço com vírgula decimal (`6,29`) | 555.836 | 100% | `double` 6.29 |
| CNPJ com espaço à esquerda e máscara | 555.836 | 100% | só os 14 dígitos |
| data em `dd/mm/aaaa` | 555.836 | 100% | `date` |
| `Valor de Compra` vazio | 555.836 | 100% | coluna descartada |
| `Unidade de Medida` constante (`R$ / litro`) | 555.836 | 100% | coluna descartada |

Em 2023–2024 também apareceram preços sem as duas casas decimais (`5,9` e
`6`: 917 e 79 linhas em 2024-06), e o parser aceita os dois formatos. Preço fora
da faixa de R$ 1,00 a R$ 15,00 por litro é descartado: **0 linhas** em 36 meses
medidos (1.777.476 linhas; mínimo de R$ 2,63 e máximo de R$ 9,79).

Limitação conhecida e não tratada: o bairro é texto livre da ANP e tem erros de
digitação (por exemplo, `IMBIRIRBEIRA` ao lado de `IMBIRIBEIRA` no Recife). A
pergunta agrega por estado, então isso não afeta a resposta.

## DECISAO 04 — partição e ingestão idempotente

**Partição `ano=AAAA/mes=MM`, igual nas três camadas.** O mês é a unidade de
publicação da ANP: um arquivo por mês. Assim, uma partição corresponde a um
arquivo da fonte, e o backfill de um mês mexe em uma única partição.
Alternativas descartadas, com números de 2025:

- **por dia:** a ANP coleta de 20 a 26 dias por mês (medido em 2024-06,
  2025-01 e 2026-10), o que daria partições de uns 20 a 25 KB na trusted. É
  arquivo pequeno demais, com mais custo de listagem que de leitura.
- **só por ano:** o backfill de um mês obrigaria a regravar o ano inteiro (12
  meses e 5,9 MB).

Cada partição da trusted tem de **498.856 a 559.024 B** (um arquivo
`part-0.parquet`).

**Partition projection** no Glue (`projection.ano.range = 2023,2026`, `mes` de
01 a 12): o Athena calcula as partições a partir dos parâmetros da tabela. Não
há Crawler, `MSCK REPAIR` nem `aws_glue_partition`, e carregar uma partição de
novo não muda o catálogo.

**Ingestão idempotente**, em duas etapas com nome de arquivo fixo:

1. `ingerir-anp.py` apaga a partição local e regrava `part-0.parquet`. Rodar o
   mesmo mês duas vezes gera arquivos byte a byte iguais (MD5 de 2025-03 na
   trusted: `137198eb…` nas duas execuções; na refined: `cf59bc23…` nas duas).
2. `carregar.sh` faz `aws s3 rm --recursive` no prefixo da partição e depois o
   `cp`. Não sobra arquivo antigo, então não duplica.

**Backfill:** 2024-06 é carregado depois da base de 2025, com
`carregar.sh 2024-06`. Escolhemos esse mês porque é o único com duplicatas na
fonte, e por isso ele também testa a regra da decisão 02. O `verifica.sh`
(critério 6) recarrega o mês e confere que o `count(*)` continua **49.958**.
Medido no Athena: **PENDENTE**.

A poda de partição só acontece se o filtro for na coluna de partição. Por isso
a consulta usa `ano = '2025'`, não `data_coleta`. Comparação no Athena (M2 com
`ano`, M3 só com `data_coleta`): **PENDENTE**.

## DECISAO 05 — meta de custo por consulta

**Meta declarada: a pergunta de negócio escaneia no máximo 1 MiB (1.048.576
bytes).** Ela fica no Terraform (`meta_bytes_consulta`), e o `verifica.sh`
(critério 5) reprova se for ultrapassada.

Por que a meta é alcançável: a pergunta roda na refined, filtra `ano = '2025'`
e lê 5 das 7 colunas. Medido localmente, essas 5 colunas somam cerca de 2,5 KB
por partição, ou seja, uns **30 KB em 12 meses**: mais de 30 vezes abaixo da
meta.

| Versão | Bytes escaneados pela pergunta |
| --- | ---: |
| migração (JSON, sem partição, sem refined) | 128.703.128 (estimado: varre tudo) |
| meta da AV2 | ≤ 1.048.576 |
| AV2 medida no Athena | **PENDENTE** |

O Athena cobra no mínimo 10 MB por consulta, então o custo cobrado fica em
`10485760 / 1099511627776 * 5` = **US$ 0,0000477** por consulta, contra US$
0,00058527 na versão em JSON. A redução de bytes escaneados é bem maior que a
de custo, por causa desse mínimo.

O workgroup mantém `BytesScannedCutoffPerQuery = 268435456` (256 MiB) como
proteção contra consultas acidentais, como um `SELECT *` sem filtro de partição
no raw. O raw de 2025 tem 95,2 MB.

Medido no Athena (`evidencias/consulta-athena-parte-2.txt`): **PENDENTE**.

- `QueryExecutionId`: PENDENTE
- `DataScannedInBytes`: PENDENTE
- tempo de execução: PENDENTE

Resposta esperada, calculada localmente sobre a refined: o **Acre** tem a
gasolina comum mais cara (R$ 7,671), seguido de Amazonas (R$ 7,226) e Roraima
(R$ 6,948). A bandeira nem sempre cobra mais: no Amazonas, os postos com
bandeira são **R$ 0,605 mais baratos** que os de bandeira branca. Em
Pernambuco, a média é R$ 6,330 e os postos com bandeira cobram R$ 0,076 a mais.

## Controle de acesso por camada (Lake Formation)

| Papel | raw | trusted | refined |
| --- | :---: | :---: | :---: |
| `eda262-g11-engenharia` | SELECT | SELECT | — |
| `eda262-g11-analista` | — | — | SELECT |
| operador (quem roda o apply) | SELECT | SELECT | SELECT |

- Os 3 buckets são registrados no Lake Formation com o papel
  `eda262-g11-lf-registro`, criado pela stack e não com o service-linked role
  da conta. Assim, o `destroy` remove tudo.
- A permissão padrão `IAM_ALLOWED_PRINCIPALS` é revogada dos databases e das
  tabelas. Sem isso, qualquer usuário com IAM para Glue e S3 leria tudo, e as
  concessões acima não teriam efeito.
- Os papéis não têm `s3:GetObject` nos buckets do lake. O dado só chega pelo
  `lakeformation:GetDataAccess`, que obedece à matriz.
- A lista de admins do Lake Formation **não** é gerenciada por padrão
  (`gerenciar_admins_lf = false`). `aws_lakeformation_data_lake_settings`
  substitui a lista da conta inteira, e o `destroy` dele a zera. Numa conta
  compartilhada, isso tiraria o acesso de outros grupos e do docente.

Prova prática (`verifica.sh`, critério 8): o papel analista consulta a refined e
é barrado na trusted. Medido: **PENDENTE**.
