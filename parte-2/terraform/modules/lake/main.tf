locals {
  prefixo = "eda262-${var.grupo}"
  camadas = toset(["raw", "trusted", "refined"])
}

# ---------------------------------------------------------------------------
# Buckets: um por camada (eda262-gNN-lake-<camada>) + resultados do Athena
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "lake" {
  for_each      = local.camadas
  bucket        = "${local.prefixo}-lake-${each.key}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lake" {
  for_each                = local.camadas
  bucket                  = aws_s3_bucket.lake[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  for_each = local.camadas
  bucket   = aws_s3_bucket.lake[each.key].id

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

# ---------------------------------------------------------------------------
# Catalogo: um database por camada, para o Lake Formation conceder por camada
# ---------------------------------------------------------------------------

resource "aws_glue_catalog_database" "camada" {
  for_each    = local.camadas
  name        = "eda262_${var.grupo}_${each.key}"
  description = "Camada ${each.key} do grupo ${var.grupo}: precos de combustiveis da ANP."
}

# ---------------------------------------------------------------------------
# Athena
# ---------------------------------------------------------------------------

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
