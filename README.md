# Data Lake de preços de combustíveis em Terraform

Projeto do grupo 11 da disciplina **Engenharia de Dados** (CESAR School).

**Cenário:** preços de gasolina e etanol nos postos do Brasil, a partir dos dados
abertos da ANP. **Pergunta de negócio:** em quais estados a gasolina comum é mais
cara, e os postos com bandeira cobram mais que os de bandeira branca?

Na unidade 2, a pedido do docente, o projeto trocou de tema. A AV1 foi entregue
com o tema de corridas urbanas e continua registrada em `parte-1/`.

## Estrutura

- `parte-2/` — projeto atual (tema ANP); ver `parte-2/README.md`
  - `terraform/` — Terraform modular, backend remoto S3 e workspace `av2`
  - `dados/ingerir-anp.py` e `dados/fontes-anp.csv` — ingestão dos CSVs mensais da ANP
  - `consultas/pergunta-negocio.sql` — consulta Athena da pergunta de negócio
- `DECISOES.md` — decisões de engenharia do tema atual
- `verificacao/verifica.sh` — aceite automático, apontando para `parte-2/`
- `evidencias/` — saídas da verificação e da consulta Athena
- `parte-1/` — AV1 entregue (tema de corridas), com o próprio `DECISOES.md`,
  e a apresentação `apresentacao-parte-1-g11.pdf` na raiz

Região obrigatória: `us-east-1` (N. Virginia).
