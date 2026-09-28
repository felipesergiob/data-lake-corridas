# Data Lake de corridas em Terraform

Projeto · Parte 1 (AV1) do grupo 11 da disciplina **Engenharia de Dados** (CESAR School),
baseado no cenário de corridas urbanas.

## Estrutura

- `parte-1/terraform/` — Terraform modular, backend remoto S3 e workspace `av1`
- `parte-1/dados/gerar-corridas.py` — gerador dos eventos JSON Lines
- `parte-1/consultas/pergunta-negocio.sql` — consulta Athena da pergunta de negócio
- `DECISOES.md` — decisões de engenharia da AV1
- `verificacao/verifica.sh` — aceite automático da AV1
- `evidencias/` — saídas da verificação e da consulta Athena
- `apresentacao-parte-1-g11.html` e `apresentacao-parte-1-g11.pdf` — apresentação da AV1

Região obrigatória: `us-east-1` (N. Virginia).
