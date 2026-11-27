# Parte 2 — preços de combustíveis (ANP)

Data Lake do grupo 11 com o novo tema da unidade 2: preços de gasolina e etanol
coletados pela ANP nos postos do Brasil.

**Pergunta de negócio:** em quais estados a gasolina comum é mais cara, e os
postos com bandeira cobram mais que os de bandeira branca?

Esta pasta começa como a migração da Parte 1 para o novo tema, com a mesma
infraestrutura. Os requisitos da AV2 (camadas raw/trusted/refined, Parquet
particionado, ingestão idempotente com backfill e Lake Formation) entram aqui
em seguida.

## O que sobe

- Bucket S3 `eda262-g11-lake-trusted` para os dados da tabela trusted.
- Bucket S3 `eda262-g11-athena-results` para os resultados do Athena.
- Glue database `eda262_g11`.
- Glue table `precos_trusted`, com 10 colunas declaradas no Terraform e sem Crawler.
- Athena workgroup `eda262-g11-athena-wg`, com teto de 256 MiB por consulta.
- Backend remoto do Terraform em S3, com trava no DynamoDB, configurado por `backend.hcl`.

Região obrigatória: `us-east-1` (N. Virginia).

Os nomes dos recursos são os mesmos da Parte 1. Se a stack da Parte 1 ainda
estiver no ar, faça o `destroy` dela antes.

## Pré-requisitos

- AWS CLI v2, Terraform >= 1.5 e Python >= 3.9 (só biblioteca padrão).
- Credenciais da disciplina no terminal (veja `parte-1/README.md`, seção Credenciais).

## Backend remoto

```bash
cd parte-2/terraform
cp backend.hcl.example backend.hcl
```

O estado usa o mesmo bucket `eda262-g11-tfstate` da Parte 1, com outra chave:
`parte-2/terraform.tfstate`. Se o bucket não existir, crie-o como descrito em
`parte-1/README.md`.

## Deploy

```bash
cd parte-2/terraform
terraform init -backend-config=backend.hcl
terraform workspace new av2 || terraform workspace select av2
terraform fmt -check -recursive
terraform validate
terraform apply -auto-approve
```

## Ingerir e subir os dados

```bash
cd ../dados
python3 ingerir-anp.py --inicio 2025-01 --fim 2025-12

cd ../terraform
BUCKET=$(terraform output -raw lake_bucket_name)
aws s3 cp ../dados/saida/trusted/precos/ "s3://$BUCKET/trusted/precos/" --recursive --region us-east-1
```

O script baixa um CSV por mês para `saida/raw/anp/`, usando os links de
`fontes-anp.csv`, e grava a versão limpa em `saida/trusted/precos/precos-AAAA-MM.json`.
Rodar de novo para o mesmo mês sobrescreve o mesmo arquivo. A medição de
2025-01 a 2025-12 foi de 555.836 linhas e 128.703.128 bytes. As regras de
limpeza estão no `DECISOES.md` (decisão 03).

## Consulta da pergunta de negócio

`consultas/pergunta-negocio.sql`. Rode no workgroup `eda262-g11-athena-wg` e
registre `DataScannedInBytes`:

```text
custo_usd = DataScannedInBytes / 1099511627776 * 5
```

## Verificação, evidências e destroy

Na raiz do repositório:

```bash
./evidencias/coletar-evidencias.sh                # verifica.sh + consulta Athena com custo

cd parte-2/terraform && terraform destroy -auto-approve && cd ../..
./evidencias/coletar-evidencias.sh --pos-destroy  # confere que nao sobrou recurso
```
