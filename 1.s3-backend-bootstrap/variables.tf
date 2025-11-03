variable "aws_region" {
  description = "Región AWS para el backend"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "nombre unico del bucket s3 para el backend de terraform"
  type        = string
  # Ejemplo: "mi-tf-state-backend-auy1103-2025"
  # Este valor DEBES pasarlo en un .tfvars
}

variable "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB para el state lock"
  type        = string
  default     = "terraform-state-lock"
}