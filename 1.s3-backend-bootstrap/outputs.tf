output "s3_bucket_name" {
  description = "Nombre del bucket S3 creado"
  value       = module.s3_bucket.s3_bucket_id
}

output "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB creada"
  value       = aws_dynamodb_table.terraform_lock.name
}