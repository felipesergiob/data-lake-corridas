# Parte 2 (AV2) — preços de combustíveis (ANP)

Data Lake do grupo 11 com o tema da unidade 2: preços de gasolina e etanol
coletados pela ANP nos postos do Brasil.

**Pergunta de negócio:** em quais estados a gasolina comum é mais cara, e os
postos com bandeira cobram mais que os de bandeira branca?

## O que sobe

Módulo `lake` (`terraform/modules/lake/`):

- Buckets `eda262-g11-lake-raw`, `eda262-g11-lake-trusted`,
  `eda262-g11-lake-refined` e `eda262-g11-athena-results`.
- Um Glue database por camada (`eda262_g11_raw`, `_trusted` e `_refined`) com
  as tabelas `precos_raw` (CSV), `precos` (Parquet) e `precos_uf_mes`
  (Parquet). Todas têm schema declarado e partição `ano`/`mes` por partition
  projection.
- Athena workgroup `eda262-g11-athena-wg`, com teto de 256 MiB por consulta.

Módulo `acesso` (`terraform/modules/acesso/`):

- Os 3 buckets registrados no Lake Formation, com o papel `eda262-g11-lf-registro`.
- `IAM_ALLOWED_PRINCIPALS` revogado dos databases e tabelas da stack, via AWS CLI.
- Papéis `eda262-g11-engenharia` (raw e trusted) e `eda262-g11-analista`
  (só refined), com SELECT concedido pelo Lake Formation.

Região obrigatória: `us-east-1` (N. Virginia). As decisões e os números estão
no `DECISOES.md`.

## Antes do primeiro apply: Lake Formation

1. **Quem roda o apply precisa ser admin do Lake Formation** na conta (console
   do Lake Formation → Administrative roles and tasks). Sem isso, o registro
   dos buckets e as concessões falham.
2. **Não ligue `gerenciar_admins_lf`** se a conta for compartilhada com outros
   grupos ou com o docente. Esse recurso substitui a lista de admins da conta
   inteira, e o `destroy` dele zera a lista. Ele existe só para conta exclusiva:

   ```hcl
   # terraform.tfvars, SO em conta exclusiva do grupo
   gerenciar_admins_lf = true
   admins_lf_extras    = ["arn:aws:iam::<conta>:role/<admin-que-deve-continuar>"]
   ```
3. O apply roda `modules/acesso/revoga-iam-allowed.sh` com `bash` e a AWS CLI.
   No Windows, rode o Terraform pelo Git Bash.

## Pré-requisitos

- AWS CLI v2, Terraform >= 1.5, bash.
- Python >= 3.9 com `pyarrow`: `pip install -r parte-2/dados/requirements.txt`.
- Credenciais da disciplina no terminal (veja `parte-1/README.md`, seção Credenciais).

## Backend remoto

```bash
cd parte-2/terraform
cp backend.hcl.example backend.hcl
```

O estado usa o mesmo bucket `eda262-g11-tfstate` da Parte 1, com a chave
`parte-2/terraform.tfstate`. Se a stack da Parte 1 ainda estiver no ar, faça o
`destroy` dela antes, porque o bucket `eda262-g11-lake-trusted` e o workgroup
têm o mesmo nome.

O bucket de estado e a tabela de lock não fazem parte da stack. Numa conta
limpa, crie os dois antes do `init` (pule o que já existir):

```bash
aws s3api create-bucket --bucket eda262-g11-tfstate --region us-east-1
aws s3api put-bucket-versioning --bucket eda262-g11-tfstate --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket eda262-g11-tfstate --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws dynamodb create-table --table-name eda-tflock --region us-east-1 \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
```

## Deploy

```bash
cd parte-2/terraform
terraform init -backend-config=backend.hcl
terraform workspace new av2 || terraform workspace select av2
terraform fmt -check -recursive
terraform validate
terraform apply -auto-approve
```

## Carga base e backfill

Na raiz do repositório:

```bash
./parte-2/dados/carregar.sh 2025-01 2025-12   # carga base: 12 particoes
./parte-2/dados/carregar.sh 2024-06           # backfill de uma particao
```

Para cada mês, o `carregar.sh`:

1. roda `ingerir-anp.py`, que baixa o CSV da ANP (ou reaproveita o que já foi
   baixado) e monta localmente `saida/{raw,trusted,refined}/.../ano=AAAA/mes=MM/`;
2. em cada camada, apaga o prefixo da partição no S3 e copia a partição local.

Rodar de novo o mesmo mês deixa os mesmos objetos, sem duplicar.

## Consultas

- `consultas/pergunta-negocio.sql`: a pergunta de negócio, rodada na refined
  (database `eda262_g11_refined`).
- `consultas/medicoes.sql`: as medições M1 a M5 citadas no `DECISOES.md`.

```text
custo_usd = DataScannedInBytes / 1099511627776 * 5
```

## Verificação, evidências e destroy

```bash
./evidencias/coletar-evidencias.sh                # verifica.sh + pergunta + medicoes

cd parte-2/terraform && terraform destroy -auto-approve && cd ../..
./evidencias/coletar-evidencias.sh --pos-destroy  # confere que nao sobrou recurso
```

O `verifica.sh` recarrega 2024-06 para testar a idempotência, o que precisa de
Python, `pyarrow` e acesso à internet. Para pular essa etapa, use
`./verificacao/verifica.sh --sem-recarga`.
