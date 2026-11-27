data "aws_caller_identity" "atual" {}

data "aws_iam_session_context" "atual" {
  arn = data.aws_caller_identity.atual.arn
}

locals {
  operador = data.aws_iam_session_context.atual.issuer_arn
  script   = "${path.module}/admin-lf.sh"
}

data "external" "admin_antes" {
  program = ["bash", local.script, "consulta", var.regiao, local.operador]
}

resource "terraform_data" "admin_lf" {
  input = {
    script    = local.script
    regiao    = var.regiao
    principal = local.operador
    adicionar = data.external.admin_antes.result.admin == "true" ? "nao" : "sim"
  }

  lifecycle {
    ignore_changes = [input]
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "if [ \"${self.input.adicionar}\" = sim ]; then \"${self.input.script}\" adiciona \"${self.input.regiao}\" \"${self.input.principal}\"; else echo \"admin-lf: ${self.input.principal} ja era admin; a stack nao mexe na lista\"; fi"
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = "if [ \"${self.input.adicionar}\" = sim ]; then \"${self.input.script}\" remove \"${self.input.regiao}\" \"${self.input.principal}\"; else echo \"admin-lf: ${self.input.principal} ja era admin antes da stack; continua admin\"; fi"
  }
}
