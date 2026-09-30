variable "grupo" {
  type        = string
  description = "Grupo no formato gNN."
}

variable "trusted_prefix" {
  type        = string
  description = "Prefixo S3 da tabela trusted."
}

variable "teto_bytes" {
  type        = number
  description = "BytesScannedCutoffPerQuery do Athena."
}
