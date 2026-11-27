output "papeis" {
  description = "ARN de cada papel por camada: { engenharia, analista }."
  value       = { for p, r in aws_iam_role.papel : p => r.arn }
}

output "papel_registro_arn" {
  value = aws_iam_role.registro.arn
}

output "operador_arn" {
  description = "Principal que roda o apply e recebe acesso as tres camadas."
  value       = local.operador
}
