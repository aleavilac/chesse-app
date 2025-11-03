terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Asume que ejecutas 'aws configure' o usas variables de entorno
  # Se omite 'profile' para mayor flexibilidad (Req. Profesor)
}

# REQ 3: Módulo público para el bucket S3
# Este bucket guardará el archivo terraform.tfstate
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.15.1" # Se recomienda fijar la versión

  bucket = var.s3_bucket_name
  acl    = "private"

  # REQ 3: Configura el bucket para que sea privado, con versionamiento
  control_object_ownership = true
  object_ownership         = "ObjectWriter"
  block_public_acls        = true
  block_public_policy      = true
  ignore_public_acls       = true
  restrict_public_buckets  = true

  versioning = {
    enabled = true
  }
}

# REQ 3: Tabla de DynamoDB para el bloqueo de estado (state locking)
# Esto evita que dos personas ejecuten 'terraform apply' al mismo tiempo
resource "aws_dynamodb_table" "terraform_lock" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"
  
  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "Terraform State Lock"
  }
}