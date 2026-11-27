output "operador_arn" {
  description = "Principal que roda o apply."
  value       = local.operador
}

output "adicionado_pela_stack" {
  description = "sim se a stack acrescentou o operador aos admins do Lake Formation."
  value       = terraform_data.admin_lf.output.adicionar
}
