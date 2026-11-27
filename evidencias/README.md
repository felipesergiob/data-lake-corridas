# Evidências

## Parte 2 (tema atual: preços de combustíveis da ANP)

| Arquivo | Como gerar | Quando |
| --- | --- | --- |
| `verifica-parte-2.txt` | `./evidencias/coletar-evidencias.sh` | stack no ar e dados no S3 |
| `consulta-athena-parte-2.txt` | `./evidencias/coletar-evidencias.sh` | idem (QueryExecutionId, bytes, custo) |
| `medicoes-parte-2.txt` | `./evidencias/coletar-evidencias.sh` | idem (M1 a M5 do `DECISOES.md`) |
| `verifica-parte-2-pos-destroy.txt` | `./evidencias/coletar-evidencias.sh --pos-destroy` | depois do `terraform destroy` |

Ordem:

```bash
# 1. subir e carregar os dados (ver parte-2/README.md)
# 2. com a stack no ar:
./evidencias/coletar-evidencias.sh

# 3. destruir e conferir órfãos:
cd parte-2/terraform && terraform destroy -auto-approve && cd ../..
./evidencias/coletar-evidencias.sh --pos-destroy
```

Gere os arquivos na conta da disciplina; não edite à mão. Depois, copie
`DataScannedInBytes` e `QueryExecutionId` para o `DECISOES.md` (decisão 05) e
troque os itens marcados como PENDENTE.

## AV1 (tema anterior: corridas)

`verifica-av1.txt`, `consulta-athena-av1.txt` e `verifica-av1-pos-destroy.txt`
são as evidências da entrega da Parte 1 e ficam aqui como registro.
