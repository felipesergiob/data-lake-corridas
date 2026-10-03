# DECISOES.md — Projeto AV1

Cenario: corridas urbanas em Recife. Pergunta de negocio: quais bairros
concentram maior receita de corridas na madrugada?

Medicao local do gerador em 2026-10-04:

- comando: `python3 parte-1/dados/gerar-corridas.py --dias 30 --taxa 12 --seed 42 --saida /private/tmp/eda-av1-medicao`
- janela: 2026-09-05 a 2026-10-04
- eventos: 518.400
- arquivo JSON Lines: 117.584.519 bytes
- `valor` com virgula decimal: 7.688 eventos, 1,48%

## DECISAO 01 — grao da tabela trusted

A tabela `corridas_trusted` tem grao de **uma linha por corrida finalizada**. O
gerador cria 30 dias x 12 eventos por minuto x 1.440 minutos = **518.400
eventos**, e cada evento recebe um `corrida_id` sequencial (`c-00000001` etc.).

Aceitamos nao modelar eventos intermediarios da corrida na AV1, como solicitacao,
aceite e cancelamento. Isso deixa a pergunta de receita por bairro direta e
mantem o escopo dentro do que foi cobrado na primeira unidade.

## DECISAO 02 — chave logica

A chave logica da tabela e `corrida_id`. `motorista_id`, `passageiro_id` e
`bairro` ficam como atributos analiticos, nao como parte da chave. No dataset
medido, o esperado e `count(*) = 518400` e `count(distinct corrida_id) =
518400`.

Consulta de comprovacao rodada no Athena:

```sql
SELECT count(*) AS linhas,
       count(distinct corrida_id) AS corridas_distintas
FROM corridas_trusted;
```

Resultado medido: **518.400 linhas e 518.400 corridas distintas**, sem
duplicata. Foram 112,14 MB examinados (117.584.519 bytes) em 1,1 s.

## DECISAO 03 — formato e schema declarado

Mantemos JSON Lines com schema declarado no Terraform, sem Crawler. O schema tem
9 colunas: `corrida_id`, `motorista_id`, `passageiro_id`, `bairro`,
`data_corrida`, `fim`, `distancia_km`, `duracao_min` e `valor`.

`valor` foi declarado como `double` para permitir soma direta na pergunta de
negocio. O custo aceito e que os **7.688 eventos (1,48%)** em que o produtor
envia decimal com virgula virem `null` no Athena. Preferimos esse custo medido a
obrigar todo SQL a fazer `cast(replace(valor, ',', '.') as double)`.

Medido no Athena: sem configuracao extra, a consulta **falhou** com `BAD_DATA`
(`Error parsing column 'valor' with value '13,61'`, QueryExecutionId
`823ee85e-9d3a-4378-9131-14732b1782b7`). Com `use.null.for.invalid.data = true`
na tabela (declarado no Terraform), `count(*) = 518.400` e
`count(valor) = 510.712`, ou seja, **7.688 nulls**, exatamente os 1,48%
medidos no gerador.

## DECISAO 04 — sem particionamento na AV1

A AV1 fica sem particao no Glue e sem pastas `dt=`, porque o guia declara
particionamento como fora de escopo da Parte 1. Todos os dados ficam em
`s3://eda262-g11-lake-trusted/trusted/corridas/`.

O custo aceito e que a consulta por madrugada varra o arquivo inteiro de
**117.584.519 bytes**. Medido no Athena, a consulta da pergunta de negocio
examinou **117.587.268 bytes** (o arquivo inteiro, sem poda), a um custo de
**US$ 0,00053472** usando US$ 5/TB.

## DECISAO 05 — teto de custo no Athena

O workgroup usa `BytesScannedCutoffPerQuery = 268435456` bytes (256 MiB). Esse
teto e maior que o dataset medido (**117.584.519 bytes**), entao a pergunta de
negocio passa, mas ainda impede consultas acidentais muito acima do volume
esperado da AV1.

Medido na consulta da pergunta de negocio (`evidencias/consulta-athena-av1.txt`):

- `QueryExecutionId`: `34753c1e-c6cc-46a6-8790-a14567e37774`
- `DataScannedInBytes`: **117.587.268** (43,8% do teto de 268.435.456)
- tempo de execucao: 1,8 s
- custo: `117587268 / 1099511627776 * 5` = **US$ 0,00053472**

Resposta: Boa Viagem lidera a receita de madrugada (8.564 corridas, R$ 138.210,00),
seguida de Pina (R$ 55.760,10) e Recife Antigo (R$ 46.907,49).
