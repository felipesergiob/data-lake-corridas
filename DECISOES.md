# DECISOES.md — Projeto AV2

Na unidade 2 o docente pediu a troca de tema, porque o dataset de corridas era o
mesmo usado nos exercícios em sala. A AV1 continua em `parte-1/` e na tag
`av1-entrega`.

Cenário: preços de gasolina e etanol nos postos do Brasil, do Levantamento de
Preços de Combustíveis da ANP. Pergunta de negócio: em quais estados a gasolina
comum é mais cara, e os postos com bandeira cobram mais que os de bandeira
branca?

A ANP publica um CSV por mês. Os links estão em `parte-2/dados/fontes-anp.csv`
(2023-01 a 2026-10), porque o nome dos arquivos muda de um ano para outro.

Carga medida em 2026-11-26 (`parte-2/dados/carregar.sh`); os mesmos tamanhos
foram conferidos no S3 pelo `verifica.sh` (13 partições por camada):

| Carga | Raw (CSV) | Trusted (Parquet) | Refined (Parquet) |
| --- | ---: | ---: | ---: |
| 2025-01 a 2025-12 | 555.836 linhas, 95.168.702 B | 555.836 linhas, 5.936.460 B | 1.931 linhas, 63.972 B |
| backfill 2024-06 | 49.974 linhas, 8.547.371 B | 49.958 linhas, 559.024 B | 160 linhas, 5.371 B |

As medições no Athena são as consultas M1 a M5 de `parte-2/consultas/medicoes.sql`,
salvas em `evidencias/medicoes-parte-2.txt`.

## DECISAO 01 — grão de cada camada

| Camada | Tabela | Grão |
| --- | --- | --- |
| raw | `eda262_g11_raw.precos_raw` | uma linha do CSV da ANP, sem alteração |
| trusted | `eda262_g11_trusted.precos` | uma coleta de preço: posto x produto x dia |
| refined | `eda262_g11_refined.precos_uf_mes` | UF x produto x tipo de bandeira x mês |

O raw guarda o arquivo como veio, para poder refazer a trusted se a limpeza
mudar. A trusted fica no grão da coleta porque outras análises (por município,
por distribuidora) precisam do posto. A refined já está no formato da pergunta
e guarda `coletas` e `soma_valor` em vez da média, para que a média de vários
meses seja `sum(soma_valor) / sum(coletas)` e não uma média de médias.

Em 2025 a refined tem 1.931 linhas contra 555.836 da trusted (288 vezes menos)
e dá a mesma resposta (Acre R$ 7,671 nas duas).

Raw x trusted no mês do backfill, medido no Athena: **49.974** linhas no raw
(M5, `3f54fbc4-9c3d-437b-b535-33f04e6a8019`) e **49.958** na trusted (M4,
`a1ff6bc7-8a7c-453b-812c-b103e4a7d272`). A diferença são os 16 descartes da
decisão 02.

## DECISAO 02 — chaves

A chave da trusted é `cnpj` + `produto` + `data_coleta`: um posto não tem dois
preços do mesmo produto no mesmo dia. Na refined, a chave é `uf` + `produto` +
`tipo_bandeira` + `ano` + `mes`.

A fonte tem duplicatas só em 2024-06: 8 linhas repetidas idênticas (fica uma
cópia) e 4 pares com a mesma chave e preços diferentes (saem as duas linhas,
porque não dá para saber qual vale). São 16 descartes, 0,032% do mês. Em 2025
não há duplicata: 555.836 linhas e 555.836 chaves distintas.

Comprovação no Athena (M1, `81e8638e-38bb-40ae-8a7a-a90ee3b06e09`): **605.794
linhas e 605.794 chaves distintas** na trusted (2025 + backfill), sem duplicata.

## DECISAO 03 — formato

O raw fica em CSV, como a ANP publica (separador `;`, vírgula decimal, BOM e
CRLF). A tabela lê tudo como `string`, para o raw nunca falhar por valor mal
formado.

Trusted e refined ficam em Parquet com Snappy. Na trusted de 2025:

| Formato | Bytes |
| --- | ---: |
| CSV original | 95.168.702 |
| JSON Lines (formato da AV1) | 128.703.128 |
| Parquet + Snappy | 5.936.460 |

O Parquet ficou 93,8% menor que o CSV. Como é colunar, o Athena lê só as
colunas da consulta: numa partição de 498.856 B, as quatro colunas da pergunta
ocupam 84.159 B (17%).

A limpeza é feita no `ingerir-anp.py`, entre raw e trusted. No raw de 2025, 100%
das linhas têm preço com vírgula, CNPJ com máscara e espaço, data em
`dd/mm/aaaa`, `Valor de Compra` vazio e `Unidade de Medida` constante. As duas
últimas colunas são descartadas. Em 2024-06 também há preços como `5,9` (917
linhas) e `6` (79 linhas), que o parser aceita. Preço fora de R$ 1,00 a R$ 15,00
é descartado, mas não houve nenhum caso em 36 meses medidos (1.777.476 linhas,
de R$ 2,63 a R$ 9,79).

O bairro é texto livre e tem erros de digitação (`IMBIRIRBEIRA` e `IMBIRIBEIRA`
no Recife). Não tratamos, porque a pergunta agrega por estado.

## DECISAO 04 — partição e ingestão idempotente

As três camadas são particionadas por `ano=AAAA/mes=MM`, porque a ANP publica
um arquivo por mês: cada partição corresponde a um arquivo da fonte. Partição
por dia daria arquivos de 20 a 25 KB (a ANP coleta de 20 a 26 dias por mês); só
por ano obrigaria regravar o ano inteiro para fazer o backfill de um mês. Cada
partição da trusted tem entre 498.856 e 559.024 B.

O Glue usa partition projection (`ano` de 2023 a 2026, `mes` de 01 a 12), então
não há Crawler, `MSCK REPAIR` nem partição cadastrada à mão.

A ingestão é idempotente porque o nome do arquivo é fixo (`part-0.parquet`): o
`ingerir-anp.py` apaga a partição local antes de gravar, e o `carregar.sh` apaga
o prefixo da partição no S3 antes de copiar. Rodando 2025-03 duas vezes, os
arquivos saem iguais (MD5 `137198eb…` na trusted e `cf59bc23…` na refined).

O backfill é 2024-06, carregado depois de 2025. Escolhemos esse mês por ser o
único com duplicatas, o que também testa a decisão 02. O `verifica.sh` recarrega
o mês e confere o `count(*)`. Medido no Athena: **49.958 linhas antes e 49.958
depois** da recarga, com 49.958 chaves distintas (`evidencias/verifica-parte-2.txt`,
critério 6).

A poda só acontece com filtro na coluna de partição, por isso a pergunta filtra
`ano = '2025'` e não `data_coleta`. Medido no Athena, com 13 partições
carregadas:

| Consulta na trusted | Filtro | Bytes escaneados |
| --- | --- | ---: |
| M2 (`50ac3423-d085-4e40-bdb3-c4c20db67665`) | `ano = '2025'` | **654.971** |
| M3 (`d6a15796-3475-48c0-a7d4-fb8d56258ba4`) | só `data_coleta` | **699.950** (+6,9%) |

M3 não consegue podar partição e abre também 2024-06. A diferença é pequena
porque só há uma partição fora de 2025, e porque o Parquet ainda lê só as
colunas usadas. As duas dão a mesma resposta.

## DECISAO 05 — meta de custo por consulta

Meta: a pergunta de negócio escaneia no máximo 1 MiB (1.048.576 bytes). O valor
está no Terraform (`meta_bytes_consulta`) e o `verifica.sh` reprova se passar.

A pergunta roda na refined, com `ano = '2025'`, e lê 5 das 7 colunas. Medido
localmente, isso dá cerca de 30 KB nos 12 meses. Na versão em JSON, sem
partição e sem refined, a mesma pergunta varreria 128.703.128 bytes.

O Athena cobra no mínimo 10 MB por consulta, então o custo fica em
`10485760 / 1099511627776 * 5` = US$ 0,0000477, contra US$ 0,00058527 em JSON. O
workgroup mantém o teto de 256 MiB por consulta contra consultas acidentais.

Medido no Athena (`evidencias/consulta-athena-parte-2.txt`): **meta cumprida**.

- `QueryExecutionId`: `557ec1cd-d8f5-49dc-a8e8-d7c0b4b715df`
- `DataScannedInBytes`: **30.254** (2,9% da meta de 1.048.576; 4.254 vezes menos
  que os 128.703.128 da versão em JSON)
- tempo de execução: 884 ms

Pela tabela de preço (US$ 5/TB), 30.254 bytes custariam US$ 0,00000014, mas o
mínimo cobrado de 10 MB leva a US$ 0,0000477 por consulta.

Resposta no Athena, igual à calculada localmente: o Acre tem a gasolina comum mais cara
(R$ 7,671), seguido de Amazonas (R$ 7,226) e Roraima (R$ 6,948). A bandeira nem
sempre cobra mais: no Amazonas, os postos com bandeira são R$ 0,605 mais
baratos que os de bandeira branca. Pernambuco fica fora do top 10 da consulta;
calculado localmente, a média lá é R$ 6,330 e a bandeira cobra R$ 0,076 a mais.

## Controle de acesso por camada

| Papel | raw | trusted | refined |
| --- | :---: | :---: | :---: |
| `eda262-g11-engenharia` | SELECT | SELECT | — |
| `eda262-g11-analista` | — | — | SELECT |
| quem roda o apply | criador | criador | criador |

Os três buckets são registrados no Lake Formation com um papel criado pela
stack (`eda262-g11-lf-registro`), para o `destroy` não deixar nada. A permissão
padrão `IAM_ALLOWED_PRINCIPALS` é revogada das tabelas; sem isso, quem tivesse
IAM para Glue e S3 leria tudo. Os papéis não têm `s3:GetObject` nos buckets do
lake: o dado só chega pelo Lake Formation.

Quem roda o apply precisa ser admin do Lake Formation. Não usamos
`aws_lakeformation_data_lake_settings`, porque ele substitui a lista de admins
da conta inteira (na conta da disciplina, o admin era o `eda-grupo03`). O módulo
`admin-lf` consulta a lista no `plan`, só acrescenta quem roda o apply se ele
ainda não for admin, e guarda essa decisão no estado do Terraform. Ele é o
primeiro a subir e o último a sair: o `destroy` apaga databases e tabelas
enquanto o operador ainda é admin, e só então o tira da lista, se foi a stack
que o acrescentou.

Quem roda o apply não recebe concessão explícita: ele usa as permissões de
criador que o Lake Formation dá a quem cria o database e as tabelas. Medimos
por que isso importa. Numa versão anterior, a stack concedia `DESCRIBE` ao
operador. Isso gerava diferença em todo `plan`, porque se misturava ao `ALL`
de criador, e no `destroy` a revogação levava junto o `DROP` de criador: os 3
databases ficaram órfãos (`AccessDeniedException: Required Drop`). Sem a
concessão, o `plan` após o apply dá "No changes" e o `destroy` fica limpo.

Teste no `verifica.sh` (critério 8), medido: o analista lê a refined
(`SUCCEEDED`) e é barrado na trusted (`FAILED: Insufficient Lake Formation
permission(s): Required Describe on ...`).
