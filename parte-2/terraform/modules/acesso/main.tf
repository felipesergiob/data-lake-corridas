# Controle de acesso por camada com Lake Formation.
#
#   papel          raw   trusted   refined
#   engenharia     sim   sim       nao
#   analista       nao   nao       sim
#   operador*      sim   sim       sim     (* quem roda o terraform apply/verifica)
#
# Os buckets sao registrados no Lake Formation com um papel proprio da stack
# (nao o service-linked role da conta), para o destroy nao deixar nada para tras.
# Depois de criadas as tabelas, a permissao padrao IAM_ALLOWED_PRINCIPALS e
# revogada: sem isso, qualquer usuario com IAM para Glue/S3 leria tudo e as
# permissoes do Lake Formation nao teriam efeito.

data "aws_caller_identity" "atual" {}

data "aws_partition" "atual" {}

# Converte um assumed-role (arn:aws:sts::...:assumed-role/X/sessao) no ARN do
# papel IAM (arn:aws:iam::...:role/X), que e o que o Lake Formation aceita.
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

  # Pares (principal, camada) que recebem DESCRIBE no database e
  # SELECT + DESCRIBE em todas as tabelas da camada.
  concessoes = merge(
    { for par in flatten([for papel, camadas in local.acesso : [for c in camadas : { papel = papel, camada = c }]]) :
      "${par.papel}-${par.camada}" => { principal = aws_iam_role.papel[par.papel].arn, camada = par.camada }
    },
    { for c in keys(var.databases) : "operador-${c}" => { principal = local.operador, camada = c } },
  )
}

# ---------------------------------------------------------------------------
# Administradores do Lake Formation (opcional, desligado por padrao)
# ---------------------------------------------------------------------------
# CUIDADO: aws_lakeformation_data_lake_settings SUBSTITUI a lista de admins da
# conta inteira, e o destroy dele zera a lista. Numa conta compartilhada isso
# tira o acesso de outros grupos e do docente. So ligue (gerenciar_admins_lf =
# true) numa conta exclusiva do grupo. Com o padrao (false), quem roda o apply
# ja precisa ser admin do Lake Formation.

resource "aws_lakeformation_data_lake_settings" "admins" {
  count  = var.gerenciar_admins_lf ? 1 : 0
  admins = distinct(concat([local.operador], var.admins_lf_extras))
}

# ---------------------------------------------------------------------------
# Papel usado pelo Lake Formation para ler/escrever nos buckets registrados
# ---------------------------------------------------------------------------

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

  depends_on = [aws_iam_role_policy.registro, aws_lakeformation_data_lake_settings.admins]
}

# O operador precisa de DATA_LOCATION_ACCESS para alterar tabelas que apontam
# para locais registrados (por exemplo, num apply futuro que mude o schema).
resource "aws_lakeformation_permissions" "local_operador" {
  for_each    = var.bucket_arns
  principal   = local.operador
  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = aws_lakeformation_resource.bucket[each.key].arn
  }
}

# ---------------------------------------------------------------------------
# Revoga IAM_ALLOWED_PRINCIPALS dos databases e tabelas da stack
# ---------------------------------------------------------------------------
# Nao ha recurso Terraform que revogue uma permissao que ele nao criou, entao
# isto roda a AWS CLI. Reexecuta se algum database ou tabela for recriado.

resource "terraform_data" "revoga_iam_allowed" {
  triggers_replace = [var.databases, var.tabelas, var.tabela_ids]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "\"${path.module}/revoga-iam-allowed.sh\" \"${var.regiao}\" ${join(" ", [for c, db in var.databases : "${db}.${var.tabelas[c]}"])}"
  }

  depends_on = [aws_lakeformation_resource.bucket, aws_lakeformation_data_lake_settings.admins]
}

# ---------------------------------------------------------------------------
# Papeis por camada e concessoes
# ---------------------------------------------------------------------------

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

# IAM so libera o caminho (Athena, Glue, resultados). Quem decide que dado o
# papel enxerga e o Lake Formation: o acesso aos buckets do lake vem do
# lakeformation:GetDataAccess, nunca de s3:GetObject direto.
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
