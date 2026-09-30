variable "regiao" {
  type        = string
  default     = "us-east-1"
  description = "Regiao obrigatoria da disciplina: N. Virginia."

  validation {
    condition     = var.regiao == "us-east-1"
    error_message = "Use somente us-east-1 (N. Virginia)."
  }
}

variable "turma" {
  type        = string
  default     = "eda262"
  description = "Turma usada nas tags obrigatorias."
}

variable "grupo" {
  type        = string
  default     = "g11"
  description = "Grupo no formato gNN."

  validation {
    condition     = can(regex("^g[0-9]{2}$", var.grupo))
    error_message = "Use o formato gNN, por exemplo g11."
  }
}

variable "projeto" {
  type        = string
  default     = "engenharia-de-dados"
  description = "Nome do projeto usado nas tags obrigatorias."
}

variable "trusted_prefix" {
  type        = string
  default     = "trusted/corridas/"
  description = "Prefixo S3 da tabela trusted. AV1 nao usa particionamento."

  validation {
    condition     = can(regex("^[A-Za-z0-9/_-]+/$", var.trusted_prefix))
    error_message = "O prefixo deve conter apenas letras, numeros, /, _ e -, terminando com /."
  }
}

variable "teto_bytes" {
  type        = number
  default     = 268435456
  description = "BytesScannedCutoffPerQuery do workgroup do Athena."

  validation {
    condition     = var.teto_bytes >= 10485760
    error_message = "O Athena exige teto de pelo menos 10485760 bytes."
  }
}
