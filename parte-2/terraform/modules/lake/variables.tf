variable "grupo" {
  type        = string
  description = "Grupo no formato gNN."
}

variable "teto_bytes" {
  type        = number
  description = "BytesScannedCutoffPerQuery do Athena."
}

variable "anos_projecao" {
  type        = string
  description = "Faixa de anos da partition projection, no formato \"inicio,fim\"."
}
