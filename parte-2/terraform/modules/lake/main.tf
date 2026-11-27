locals {
  prefixo = "eda262-${var.grupo}"
}

resource "aws_s3_bucket" "lake_trusted" {
  bucket        = "${local.prefixo}-lake-trusted"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lake_trusted" {
  bucket                  = aws_s3_bucket.lake_trusted.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake_trusted" {
  bucket = aws_s3_bucket.lake_trusted.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "athena_results" {
  bucket        = "${local.prefixo}-athena-results"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_glue_catalog_database" "db" {
  name        = "eda262_${var.grupo}"
  description = "Database do projeto do grupo ${var.grupo}: precos de combustiveis da ANP."
}

resource "aws_glue_catalog_table" "precos_trusted" {
  name          = "precos_trusted"
  database_name = aws_glue_catalog_database.db.name
  table_type    = "EXTERNAL_TABLE"
  description   = "Precos de gasolina e etanol coletados pela ANP, limpos na ingestao."

  parameters = {
    classification = "json"
    grain          = "uma linha por coleta de preco: posto x produto x dia"
    chave          = "cnpj, produto, data_coleta"
    fonte          = "ANP - serie historica de precos de combustiveis"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.lake_trusted.bucket}/${var.trusted_prefix}"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name    = "cnpj"
      type    = "string"
      comment = "CNPJ do posto, so digitos (14)"
    }
    columns {
      name    = "produto"
      type    = "string"
      comment = "GASOLINA, GASOLINA ADITIVADA ou ETANOL"
    }
    columns {
      name    = "data_coleta"
      type    = "date"
      comment = "dia da coleta de preco pela ANP"
    }
    columns {
      name    = "valor_venda"
      type    = "double"
      comment = "preco ao consumidor em R$ por litro"
    }
    columns {
      name    = "bandeira"
      type    = "string"
      comment = "distribuidora do posto; BRANCA = sem bandeira"
    }
    columns {
      name    = "revenda"
      type    = "string"
      comment = "razao social do posto"
    }
    columns {
      name    = "regiao"
      type    = "string"
      comment = "sigla da regiao (N, NE, CO, SE, S)"
    }
    columns {
      name    = "uf"
      type    = "string"
      comment = "sigla do estado"
    }
    columns {
      name    = "municipio"
      type    = "string"
      comment = "municipio do posto"
    }
    columns {
      name    = "bairro"
      type    = "string"
      comment = "bairro do posto, como informado pela ANP"
    }
  }
}

resource "aws_athena_workgroup" "wg" {
  name          = "${local.prefixo}-athena-wg"
  state         = "ENABLED"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.teto_bytes

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/athena-results/"
    }
  }
}
