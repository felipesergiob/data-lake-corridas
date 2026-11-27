data "aws_caller_identity" "atual" {}

data "aws_partition" "atual" {}

data "aws_iam_session_context" "atual" {
  arn = data.aws_caller_identity.atual.arn
}

locals {
  prefixo  = "eda262-${var.grupo}"
  operador = data.aws_iam_session_context.atual.issuer_arn
  conta    = data.aws_caller_identity.atual.account_id

  acesso = {
    engenharia = ["raw", "trusted"]
    analista   = ["refined"]
  }

  concessoes = {
    for par in flatten([for papel, camadas in local.acesso : [for c in camadas : { papel = papel, camada = c }]]) :
    "${par.papel}-${par.camada}" => { principal = aws_iam_role.papel[par.papel].arn, camada = par.camada }
  }
}

data "aws_iam_policy_document" "confia_lakeformation" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lakeformation.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "registro" {
  name               = "${local.prefixo}-lf-registro"
  assume_role_policy = data.aws_iam_policy_document.confia_lakeformation.json
}

data "aws_iam_policy_document" "registro" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = values(var.bucket_arns)
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [for arn in values(var.bucket_arns) : "${arn}/*"]
  }
}

resource "aws_iam_role_policy" "registro" {
  name   = "acesso-buckets-lake"
  role   = aws_iam_role.registro.id
  policy = data.aws_iam_policy_document.registro.json
}

resource "aws_lakeformation_resource" "bucket" {
  for_each = var.bucket_arns
  arn      = each.value
  role_arn = aws_iam_role.registro.arn

  depends_on = [aws_iam_role_policy.registro]
}

resource "aws_lakeformation_permissions" "local_operador" {
  for_each    = var.bucket_arns
  principal   = local.operador
  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = aws_lakeformation_resource.bucket[each.key].arn
  }
}

resource "terraform_data" "revoga_iam_allowed" {
  triggers_replace = [var.databases, var.tabelas, var.tabela_ids]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "\"${path.module}/revoga-iam-allowed.sh\" \"${var.regiao}\" ${join(" ", [for c, db in var.databases : "${db}.${var.tabelas[c]}"])}"
  }

  depends_on = [aws_lakeformation_resource.bucket]
}

data "aws_iam_policy_document" "confia_conta" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.atual.partition}:iam::${local.conta}:root"]
    }
  }
}

resource "aws_iam_role" "papel" {
  for_each           = local.acesso
  name               = "${local.prefixo}-${each.key}"
  description        = "Papel ${each.key}: camadas ${join(", ", each.value)} via Lake Formation."
  assume_role_policy = data.aws_iam_policy_document.confia_conta.json
}

data "aws_iam_policy_document" "consulta" {
  statement {
    actions = [
      "athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults",
      "athena:StopQueryExecution", "athena:GetWorkGroup",
    ]
    resources = [var.workgroup_arn]
  }
  statement {
    actions = [
      "glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables",
      "glue:GetPartition", "glue:GetPartitions",
    ]
    resources = concat(
      ["arn:${data.aws_partition.atual.partition}:glue:${var.regiao}:${local.conta}:catalog"],
      [for db in values(var.databases) : "arn:${data.aws_partition.atual.partition}:glue:${var.regiao}:${local.conta}:database/${db}"],
      [for db in values(var.databases) : "arn:${data.aws_partition.atual.partition}:glue:${var.regiao}:${local.conta}:table/${db}/*"],
    )
  }
  statement {
    actions   = ["lakeformation:GetDataAccess"]
    resources = ["*"]
  }
  statement {
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = [var.athena_results_bucket_arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${var.athena_results_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "consulta" {
  for_each = aws_iam_role.papel
  name     = "consulta-athena"
  role     = each.value.id
  policy   = data.aws_iam_policy_document.consulta.json
}

resource "aws_lakeformation_permissions" "database" {
  for_each    = local.concessoes
  principal   = each.value.principal
  permissions = ["DESCRIBE"]

  database {
    name = var.databases[each.value.camada]
  }

  depends_on = [terraform_data.revoga_iam_allowed]
}

resource "aws_lakeformation_permissions" "tabelas" {
  for_each    = local.concessoes
  principal   = each.value.principal
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = var.databases[each.value.camada]
    wildcard      = true
  }

  depends_on = [aws_lakeformation_permissions.database]
}
