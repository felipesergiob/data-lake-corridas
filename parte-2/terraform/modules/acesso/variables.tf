variable "grupo" {
  type        = string
  description = "Grupo no formato gNN."
}

variable "regiao" {
  type        = string
  description = "Regiao AWS (usada nos ARNs do Glue e na AWS CLI)."
}

variable "bucket_arns" {
  type        = map(string)
  description = "ARN do bucket de cada camada: { raw, trusted, refined }."
}

variable "databases" {
  type        = map(string)
  description = "Database de cada camada: { raw, trusted, refined }."
}

variable "tabelas" {
  type        = map(string)
  description = "Tabela de cada camada: { raw, trusted, refined }."
}

variable "tabela_ids" {
  type        = list(string)
  description = "IDs das tabelas no Glue; mudam se uma tabela for recriada."
}

variable "workgroup_arn" {
  type        = string
  description = "Workgroup do Athena que os papeis podem usar."
}

variable "athena_results_bucket_arn" {
  type        = string
  description = "Bucket de resultados do Athena."
}

variable "gerenciar_admins_lf" {
  type        = bool
  description = "Se true, define os admins do Lake Formation da CONTA INTEIRA. So use em conta exclusiva."
}

variable "admins_lf_extras" {
  type        = list(string)
  description = "ARNs que continuam admins do Lake Formation quando gerenciar_admins_lf = true."
}
