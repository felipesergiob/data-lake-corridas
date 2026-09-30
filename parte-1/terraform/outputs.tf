output "lake_bucket_name" {
  description = "Bucket S3 que armazena a tabela trusted."
  value       = module.lake.lake_bucket_name
}

output "athena_results_bucket_name" {
  description = "Bucket S3 dos resultados do Athena."
  value       = module.lake.athena_results_bucket_name
}

output "database_name" {
  description = "Database no Glue Data Catalog."
  value       = module.lake.database_name
}

output "trusted_table_name" {
  description = "Tabela trusted de corridas."
  value       = module.lake.trusted_table_name
}

output "workgroup_name" {
  description = "Workgroup do Athena."
  value       = module.lake.workgroup_name
}

output "teto_bytes" {
  description = "Teto de bytes por consulta."
  value       = var.teto_bytes
}

output "workspace" {
  description = "Workspace Terraform ativo."
  value       = terraform.workspace
}

output "athena_console_url" {
  description = "URL do editor do Athena em us-east-1."
  value       = "https://us-east-1.console.aws.amazon.com/athena/home?region=us-east-1#/query-editor"
}
