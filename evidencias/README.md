# Evidencias da AV1

Arquivos esperados nesta pasta na entrega:

| Arquivo | Como gerar | Quando |
| --- | --- | --- |
| `verifica-av1.txt` | `./evidencias/coletar-evidencias.sh` | stack no ar, dados no S3 |
| `consulta-athena-av1.txt` | `./evidencias/coletar-evidencias.sh` | idem (QueryExecutionId, bytes, custo) |
| `verifica-av1-pos-destroy.txt` | `./evidencias/coletar-evidencias.sh --pos-destroy` | depois do `terraform destroy` |

Ordem:

```bash
# 1. subir e carregar dados (ver parte-1/README.md)
# 2. com a stack no ar:
./evidencias/coletar-evidencias.sh

# 3. destruir e conferir orfaos:
cd parte-1/terraform && terraform destroy -auto-approve && cd ../..
./evidencias/coletar-evidencias.sh --pos-destroy
```

Os arquivos devem ser gerados na conta da disciplina, nao editados a mao.
Depois, copie `DataScannedInBytes` e `QueryExecutionId` para o `DECISOES.md`
(decisao 05) e para o bloco `MEDICAO` de `apresentacao-parte-1-g11.html`.
