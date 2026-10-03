# Parte 1 - AV1

Data Lake da AV1 do grupo 11 para o cenário de corridas urbanas.

## O que sobe

- Bucket S3 `eda262-g11-lake-trusted` para os dados da tabela trusted.
- Bucket S3 `eda262-g11-athena-results` para resultados do Athena.
- Glue database `eda262_g11`.
- Glue table `corridas_trusted`, com schema declarado no Terraform e sem Crawler.
- Athena workgroup `eda262-g11-athena-wg`, com teto de bytes por consulta.
- Backend remoto Terraform em S3 com trava DynamoDB, configurado por `backend.hcl`.

Região obrigatória: `us-east-1` (N. Virginia).

## Pré-requisitos

- AWS CLI v2 instalada.
- Terraform >= 1.5 instalado.
- Credenciais programáticas da disciplina configuradas localmente.
- Região `us-east-1`.

## Credenciais

Use o arquivo de acesso programático fornecido pelo professor apenas no seu terminal.
Não copie credenciais para o repositório.

```bash
aws configure --profile eda-av1
aws configure set region us-east-1 --profile eda-av1

export AWS_PROFILE=eda-av1
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

aws sts get-caller-identity
```

Se houver token de sessão no arquivo do professor:

```bash
aws configure set aws_session_token "VALOR_DO_ARQUIVO" --profile eda-av1
```

## Backend remoto

```bash
cd parte-1/terraform
cp backend.hcl.example backend.hcl
aws sts get-caller-identity --query Account --output text
```

O bucket de estado do grupo (`eda262-g11-tfstate`) nao faz parte da stack e precisa existir antes do `init`; a tabela de lock `eda-tflock` e compartilhada da disciplina. Para criar o bucket:

```bash
aws s3api create-bucket --bucket eda262-g11-tfstate --region us-east-1
aws s3api put-bucket-versioning --bucket eda262-g11-tfstate --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket eda262-g11-tfstate --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Conteudo do `backend.hcl`:

```hcl
bucket         = "eda262-g11-tfstate"
key            = "parte-1/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "eda-tflock"
encrypt        = true
```

`backend.hcl` é local e está no `.gitignore`.

## Deploy

```bash
cd parte-1/terraform
terraform init -backend-config=backend.hcl
terraform workspace new av1 || terraform workspace select av1
terraform fmt -check -recursive
terraform validate
terraform apply -auto-approve
```

## Gerar e subir dados

```bash
cd ../dados
python3 gerar-corridas.py --dias 30 --taxa 12 --seed 42 --saida ./saida

cd ../terraform
BUCKET=$(terraform output -raw lake_bucket_name)
aws s3 cp ../dados/saida/trusted/corridas/ "s3://$BUCKET/trusted/corridas/" --recursive --region us-east-1
```

## Consulta da pergunta de negócio

```bash
cd ../..
cat parte-1/consultas/pergunta-negocio.sql
```

A consulta responde: quais bairros concentram maior receita de corridas na madrugada?

Com `--dias 30 --taxa 12 --seed 42`, a medição local em 2026-10-04 gerou:

- 518.400 eventos
- 117.584.519 bytes em JSON Lines
- 7.688 eventos com `valor` em texto com vírgula decimal (1,48%)

Para medir custo, rode a consulta no Athena usando o workgroup
`eda262-g11-athena-wg` e registre `DataScannedInBytes`.

Cálculo:

```text
custo_usd = DataScannedInBytes / 1099511627776 * 5
```

## Verificação

```bash
cd verificacao
./verifica.sh | tee ../evidencias/verifica-av1.txt
```

O arquivo `evidencias/verifica-av1.txt` deve ser commitado depois que a AWS responder com sucesso.

## Destroy limpo

Depois do destroy:

```bash
cd ../parte-1/terraform
terraform destroy -auto-approve

cd ../../verificacao
./verifica.sh --pos-destroy | tee ../evidencias/verifica-av1-pos-destroy.txt
```

O arquivo `evidencias/verifica-av1-pos-destroy.txt` também deve ser commitado.


## Entrega

- `parte-1/terraform/`
- `DECISOES.md`
- `verificacao/verifica.sh`
- `README.md` e este README
- `evidencias/`
- `apresentacao-parte-1-g11.pdf`
