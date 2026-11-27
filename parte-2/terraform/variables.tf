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

variable "anos_projecao" {
  type        = string
  default     = "2023,2026"
  description = "Anos cobertos pela partition projection (\"inicio,fim\"); a fonte da ANP tem 2023-01 a 2026-10."

  validation {
    condition     = can(regex("^[0-9]{4},[0-9]{4}$", var.anos_projecao))
    error_message = "Use o formato AAAA,AAAA, por exemplo 2023,2026."
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

variable "meta_bytes_consulta" {
  type        = number
  default     = 1048576
  description = "Meta declarada de DataScannedInBytes da pergunta de negocio (1 MiB). Conferida pelo verifica.sh."
}
