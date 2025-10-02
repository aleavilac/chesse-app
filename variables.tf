variable "aws_region" {
  description = "Región AWS"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t2.micro"
}

variable "allowed_ssh_cidr" {
  description = "Tu IP pública en /32 para SSH"
  type        = string
}

variable "aws_key_name" {
  description = "Nombre del Key Pair existente en EC2 para SSH (opcional, pero recomendado)"
  type        = string
  default     = ""
}

variable "cheese_images" {
  description = "Imágenes Docker para cada instancia (en orden)"
  type        = list(string)
  default = [
    "errm/cheese:wensleydale", # index 0 -> IsPrimary=true
    "errm/cheese:cheddar",
    "errm/cheese:stilton"
  ]
  validation {
    condition     = length(var.cheese_images) == 3
    error_message = "cheese_images debe tener exactamente 3 elementos."
  }
}