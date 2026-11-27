# Data Lake de preços de combustíveis em Terraform

Projeto do grupo 11 da disciplina **Engenharia de Dados** (CESAR School).

**Cenário:** preços de gasolina e etanol nos postos do Brasil, a partir dos dados
abertos da ANP. **Pergunta de negócio:** em quais estados a gasolina comum é mais
cara, e os postos com bandeira cobram mais que os de bandeira branca?

Na unidade 2 o projeto trocou de tema: o docente pediu a troca porque o dataset
de corridas era o mesmo usado nos exercícios em sala. A AV1 continua registrada
na tag `av1-entrega` e em `parte-1/`.

## Estrutura

- `parte-2/` — AV2 (tema ANP); deploy, carga e destroy em `parte-2/README.md`
  - `terraform/` — módulos `lake` (3 camadas S3, Glue e Athena) e `acesso`
    (Lake Formation), backend remoto S3 e workspace `av2`
  - `dados/carregar.sh`, `dados/ingerir-anp.py` e `dados/fontes-anp.csv` —
    ingestão idempotente dos CSVs mensais da ANP para raw, trusted e refined
  - `consultas/pergunta-negocio.sql` e `consultas/medicoes.sql` — consultas Athena
- `DECISOES.md` — decisões de engenharia do tema atual
- `verificacao/verifica.sh` — aceite automático, apontando para `parte-2/`
- `evidencias/` — saídas da verificação e da consulta Athena
- `parte-1/` — AV1 entregue (tema de corridas), com o próprio `DECISOES.md`,
  e a apresentação `apresentacao-parte-1-g11.pdf` na raiz

Região obrigatória: `us-east-1` (N. Virginia).
