variable "aws_region" {
  description = "Región AWS"
  type        = string
  default     = "us-east-1"
}

# REQ 1: Variable 'environment'
variable "environment" {
  description = "Entorno de despliegue (dev o prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "El entorno debe ser 'dev' o 'prod'."
  }
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# REQ 1.5: Mapa para los tipos de instancia
variable "instance_types_map" {
  description = "Mapa de tipos de instancia por entorno"
  type        = map(string)
  default = {
    "dev"  = "t2.micro"
    "prod" = "t3.small"
  }
}

variable "allowed_ssh_cidr" {
  description = "Tu IP pública en /32 para SSH"
  type        = string
  # No hay default, debe ser proveída por seguridad
}

variable "aws_key_name" {
  description = "Nombre del Key Pair existente en EC2 para SSH"
  type        = string
  default     = ""
}

variable "cheese_images" {
  description = "Imágenes Docker para cada instancia (en orden)"
  type        = list(string)
  default = [
    "errm/cheese:wensleydale",
    "errm/cheese:cheddar",
    "errm/cheese:stilton"
  ]
  validation {
    condition     = length(var.cheese_images) == 3
    error_message = "cheese_images debe tener exactamente 3 elementos."
  }
}