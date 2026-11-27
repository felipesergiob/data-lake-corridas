# Tres tabelas, todas com schema declarado aqui (sem Crawler) e particionadas
# por ano/mes com partition projection: o Athena calcula as particoes a partir
# dos parametros da tabela, entao nao ha MSCK REPAIR nem aws_glue_partition, e
# carregar a mesma particao de novo nao muda o catalogo.

locals {
  # Parametros comuns de projection. "$${...}" vira "${...}" literal no Glue.
  projecao = {
    "projection.enabled"    = "true"
    "projection.ano.type"   = "integer"
    "projection.ano.range"  = var.anos_projecao
    "projection.mes.type"   = "integer"
    "projection.mes.range"  = "1,12"
    "projection.mes.digits" = "2"
  }

  local_raw     = "s3://${aws_s3_bucket.lake["raw"].bucket}/anp/"
  local_trusted = "s3://${aws_s3_bucket.lake["trusted"].bucket}/precos/"
  local_refined = "s3://${aws_s3_bucket.lake["refined"].bucket}/precos_uf_mes/"

  colunas_raw = [
    "regiao_sigla", "estado_sigla", "municipio", "revenda", "cnpj_revenda",
    "nome_rua", "numero_rua", "complemento", "bairro", "cep", "produto",
    "data_coleta", "valor_venda", "valor_compra", "unidade_medida", "bandeira",
  ]

  colunas_trusted = [
    { nome = "cnpj", tipo = "string", comentario = "CNPJ do posto, so digitos (14)" },
    { nome = "produto", tipo = "string", comentario = "GASOLINA, GASOLINA ADITIVADA ou ETANOL" },
    { nome = "data_coleta", tipo = "date", comentario = "dia da coleta de preco pela ANP" },
    { nome = "valor_venda", tipo = "double", comentario = "preco ao consumidor em R$ por litro" },
    { nome = "bandeira", tipo = "string", comentario = "distribuidora do posto; BRANCA = sem bandeira" },
    { nome = "revenda", tipo = "string", comentario = "razao social do posto" },
    { nome = "regiao", tipo = "string", comentario = "sigla da regiao (N, NE, CO, SE, S)" },
    { nome = "uf", tipo = "string", comentario = "sigla do estado" },
    { nome = "municipio", tipo = "string", comentario = "municipio do posto" },
    { nome = "bairro", tipo = "string", comentario = "bairro do posto, como informado pela ANP" },
  ]

  colunas_refined = [
    { nome = "uf", tipo = "string", comentario = "sigla do estado" },
    { nome = "produto", tipo = "string", comentario = "GASOLINA, GASOLINA ADITIVADA ou ETANOL" },
    { nome = "tipo_bandeira", tipo = "string", comentario = "BRANCA ou BANDEIRA" },
    { nome = "coletas", tipo = "bigint", comentario = "quantidade de coletas no mes" },
    { nome = "soma_valor", tipo = "double", comentario = "soma dos precos; media = sum(soma_valor) / sum(coletas)" },
    { nome = "preco_min", tipo = "double", comentario = "menor preco coletado no mes" },
    { nome = "preco_max", tipo = "double", comentario = "maior preco coletado no mes" },
  ]
}

# --- raw: CSV original da ANP, tudo string ---------------------------------

resource "aws_glue_catalog_table" "raw" {
  name          = "precos_raw"
  database_name = aws_glue_catalog_database.camada["raw"].name
  table_type    = "EXTERNAL_TABLE"
  description   = "CSV mensal da ANP como baixado (separador ;, decimal com virgula)."

  parameters = merge(local.projecao, {
    classification              = "csv"
    "skip.header.line.count"    = "1"
    grain                       = "uma linha do CSV da ANP"
    fonte                       = "ANP - serie historica de precos de combustiveis"
    "storage.location.template" = "${local.local_raw}ano=$${ano}/mes=$${mes}/"
  })

  partition_keys {
    name = "ano"
    type = "string"
  }
  partition_keys {
    name = "mes"
    type = "string"
  }

  storage_descriptor {
    location      = local.local_raw
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"
      parameters = {
        separatorChar = ";"
        quoteChar     = "\""
      }
    }

    dynamic "columns" {
      for_each = local.colunas_raw
      content {
        name = columns.value
        type = "string"
      }
    }
  }
}

# --- trusted: uma linha por coleta, limpa, Parquet -------------------------

resource "aws_glue_catalog_table" "trusted" {
  name          = "precos"
  database_name = aws_glue_catalog_database.camada["trusted"].name
  table_type    = "EXTERNAL_TABLE"
  description   = "Precos de gasolina e etanol coletados pela ANP, limpos e sem duplicata."

  parameters = merge(local.projecao, {
    classification              = "parquet"
    "parquet.compression"       = "SNAPPY"
    grain                       = "uma linha por coleta de preco: posto x produto x dia"
    chave                       = "cnpj, produto, data_coleta"
    "storage.location.template" = "${local.local_trusted}ano=$${ano}/mes=$${mes}/"
  })

  partition_keys {
    name = "ano"
    type = "string"
  }
  partition_keys {
    name = "mes"
    type = "string"
  }

  storage_descriptor {
    location      = local.local_trusted
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.colunas_trusted
      content {
        name    = columns.value.nome
        type    = columns.value.tipo
        comment = columns.value.comentario
      }
    }
  }
}

# --- refined: agregado UF x produto x tipo de bandeira x mes, Parquet ------

resource "aws_glue_catalog_table" "refined" {
  name          = "precos_uf_mes"
  database_name = aws_glue_catalog_database.camada["refined"].name
  table_type    = "EXTERNAL_TABLE"
  description   = "Agregado mensal por UF, produto e tipo de bandeira (BRANCA ou BANDEIRA)."

  parameters = merge(local.projecao, {
    classification              = "parquet"
    "parquet.compression"       = "SNAPPY"
    grain                       = "uma linha por uf x produto x tipo_bandeira x mes"
    chave                       = "uf, produto, tipo_bandeira, ano, mes"
    "storage.location.template" = "${local.local_refined}ano=$${ano}/mes=$${mes}/"
  })

  partition_keys {
    name = "ano"
    type = "string"
  }
  partition_keys {
    name = "mes"
    type = "string"
  }

  storage_descriptor {
    location      = local.local_refined
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.colunas_refined
      content {
        name    = columns.value.nome
        type    = columns.value.tipo
        comment = columns.value.comentario
      }
    }
  }
}
