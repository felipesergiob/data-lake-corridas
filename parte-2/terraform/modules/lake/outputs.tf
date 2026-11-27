output "buckets" {
  description = "Bucket de cada camada: { raw, trusted, refined }."
  value       = { for c, b in aws_s3_bucket.lake : c => b.bucket }
}

output "bucket_arns" {
  description = "ARN do bucket de cada camada."
  value       = { for c, b in aws_s3_bucket.lake : c => b.arn }
}

output "athena_results_bucket_name" {
  value = aws_s3_bucket.athena_results.bucket
}

output "athena_results_bucket_arn" {
  value = aws_s3_bucket.athena_results.arn
}

output "databases" {
  description = "Database de cada camada: { raw, trusted, refined }."
  value       = { for c, d in aws_glue_catalog_database.camada : c => d.name }
}

output "tabelas" {
  description = "Tabela de cada camada: { raw, trusted, refined }."
  value = {
    raw     = aws_glue_catalog_table.raw.name
    trusted = aws_glue_catalog_table.trusted.name
    refined = aws_glue_catalog_table.refined.name
  }
}

output "tabela_ids" {
  description = "IDs das tabelas no Glue; mudam se uma tabela for recriada."
  value       = [aws_glue_catalog_table.raw.id, aws_glue_catalog_table.trusted.id, aws_glue_catalog_table.refined.id]
}

output "workgroup_name" {
  value = aws_athena_workgroup.wg.name
}

output "workgroup_arn" {
  value = aws_athena_workgroup.wg.arn
}
