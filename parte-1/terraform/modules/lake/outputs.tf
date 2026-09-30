output "lake_bucket_name" {
  value = aws_s3_bucket.lake_trusted.bucket
}

output "athena_results_bucket_name" {
  value = aws_s3_bucket.athena_results.bucket
}

output "database_name" {
  value = aws_glue_catalog_database.db.name
}

output "trusted_table_name" {
  value = aws_glue_catalog_table.corridas_trusted.name
}

output "workgroup_name" {
  value = aws_athena_workgroup.wg.name
}
