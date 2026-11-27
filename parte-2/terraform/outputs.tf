output "lake_raw_bucket" {
  description = "Bucket da camada raw (CSV original da ANP)."
  value       = module.lake.buckets["raw"]
}

output "lake_trusted_bucket" {
  description = "Bucket da camada trusted (Parquet, uma linha por coleta)."
  value       = module.lake.buckets["trusted"]
}

output "lake_refined_bucket" {
  description = "Bucket da camada refined (Parquet, agregado UF x produto x bandeira x mes)."
  value       = module.lake.buckets["refined"]
}

output "athena_results_bucket_name" {
  description = "Bucket S3 dos resultados do Athena."
  value       = module.lake.athena_results_bucket_name
}

output "database_raw" {
  value = module.lake.databases["raw"]
}

output "database_trusted" {
  value = module.lake.databases["trusted"]
}

output "database_refined" {
  value = module.lake.databases["refined"]
}

output "tabela_raw" {
  value = module.lake.tabelas["raw"]
}

output "tabela_trusted" {
  value = module.lake.tabelas["trusted"]
}

output "tabela_refined" {
  value = module.lake.tabelas["refined"]
}

output "workgroup_name" {
  description = "Workgroup do Athena."
  value       = module.lake.workgroup_name
}

output "papel_engenharia_arn" {
  description = "Papel com acesso a raw e trusted via Lake Formation."
  value       = module.acesso.papeis["engenharia"]
}

output "papel_analista_arn" {
  description = "Papel com acesso so a refined via Lake Formation."
  value       = module.acesso.papeis["analista"]
}

output "papel_registro_arn" {
  description = "Papel que o Lake Formation usa para acessar os buckets registrados."
  value       = module.acesso.papel_registro_arn
}

output "operador_arn" {
  description = "Principal que rodou o apply (acesso as tres camadas)."
  value       = module.acesso.operador_arn
}

output "teto_bytes" {
  description = "Teto de bytes por consulta no workgroup."
  value       = var.teto_bytes
}

output "meta_bytes_consulta" {
  description = "Meta declarada de bytes escaneados pela pergunta de negocio."
  value       = var.meta_bytes_consulta
}

output "workspace" {
  description = "Workspace Terraform ativo."
  value       = terraform.workspace
}
