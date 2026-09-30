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
  description = "Database da AV1 do grupo ${var.grupo}."
}

resource "aws_glue_catalog_table" "corridas_trusted" {
  name          = "corridas_trusted"
  database_name = aws_glue_catalog_database.db.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification              = "json"
    grain                       = "uma linha por corrida finalizada"
    "use.null.for.invalid.data" = "true"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.lake_trusted.bucket}/${var.trusted_prefix}"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"

      parameters = {
        "ignore.malformed.json"     = "true"
        "use.null.for.invalid.data" = "true"
      }
    }

    columns {
      name = "corrida_id"
      type = "string"
    }
    columns {
      name = "motorista_id"
      type = "string"
    }
    columns {
      name = "passageiro_id"
      type = "string"
    }
    columns {
      name = "bairro"
      type = "string"
    }
    columns {
      name = "data_corrida"
      type = "string"
    }
    columns {
      name = "fim"
      type = "string"
    }
    columns {
      name = "distancia_km"
      type = "double"
    }
    columns {
      name = "duracao_min"
      type = "double"
    }
    columns {
      name = "valor"
      type = "double"
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
