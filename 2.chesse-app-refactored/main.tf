terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # REQ 3: Configuración del Backend Remoto (S3)
  # Después de ejecutar el proyecto 's3-backend-bootstrap',
  # rellena estos valores y ejecuta 'terraform init'
  backend "s3" {
    bucket         = "tf-state-cheese-app-tu-nombre-unico-2025" # <- REEMPLAZA
    key            = "cheese-app/terraform.tfstate" # Ruta dentro del bucket
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock" # Nombre de la tabla de bloqueo
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  # Se omite 'profile' para que use credenciales de entorno/rol IAM
}

# === DATOS ===
data "aws_availability_zones" "available" {
  state = "available"
}

# === LÓGICA LOCAL ===
locals {
  # REQ 1.5 y 5: Lógica condicional para el tipo de instancia
  # Usamos una función 'lookup' en un mapa. Es más limpio que un 'if'.
  instance_type = lookup(var.instance_types_map, var.environment, "t2.micro")

  # REQ 5: Usamos merge() para crear etiquetas comunes
  common_tags = {
    Project     = "CheeseFactory"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# REQ 2: Módulo Público para la Red (VPC)
# No usamos la VPC por defecto.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.3" # Se recomienda fijar la versión

  name = format("cheese-%s-vpc", var.environment) # REQ 5: Función format()
  cidr = var.vpc_cidr

  # REQ 2: 3 subredes públicas y 3 privadas en distintas Zonas de Disponibilidad
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = [for k, v in slice(data.aws_availability_zones.available.names, 0, 3) : cidrsubnet(var.vpc_cidr, 8, k)]
  public_subnets  = [for k, v in slice(data.aws_availability_zones.available.names, 0, 3) : cidrsubnet(var.vpc_cidr, 8, k + 10)] # +10 para evitar solapamiento

  # REQ 2 (Implicación): Las instancias en subredes privadas necesitan un NAT Gateway
  # para descargar las imágenes de Docker (acceso a Internet de salida).
  enable_nat_gateway = true
  single_nat_gateway = true # Más barato para 'dev'/'prod' no-crítico

  # REQ 2: El ALB va en las públicas
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    Type = "public-subnets"
  }
  private_subnet_tags = {
    Type = "private-subnets"
  }
  tags = local.common_tags
}

# === SEGURIDAD (Security Groups) ===

# REQ 4: Security Group del ALB (en subredes públicas)
resource "aws_security_group" "alb_sg" {
  name        = format("cheese-%s-alb-sg", var.environment)
  description = "Permite HTTP desde Internet al ALB"
  vpc_id      = module.vpc.vpc_id

  # REQ 4.1: Permitir HTTP (80) desde 0.0.0.0/0
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1" # Todo el tráfico
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = format("cheese-%s-alb-sg", var.environment) })
}

# REQ 4: Security Group de las EC2 (en subredes privadas)
resource "aws_security_group" "ec2_sg" {
  name        = format("cheese-%s-ec2-sg", var.environment)
  description = "Permite HTTP desde ALB y SSH desde IP personal"
  vpc_id      = module.vpc.vpc_id

  # REQ 4.2: Permitir HTTP (80) únicamente desde el SG del ALB
  ingress {
    description     = "Permite HTTP desde ALB"
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.alb_sg.id]
  }

  # REQ 4.3: Permitir SSH (22) únicamente desde tu IP
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Permite salida a Internet (via NAT Gateway) para descargar Docker
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = format("cheese-%s-ec2-sg", var.environment) })
}

# === COMPUTE (EC2) ===
data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "web" {
  count = 3
  
  # REQ 1.5: Lógica condicional para el tipo de instancia
  instance_type = local.instance_type
  ami           = data.aws_ami.al2.id
  
  # REQ 2: Las instancias EC2 se despliegan en las subredes PRIVADAS
  subnet_id                   = module.vpc.private_subnets[count.index]
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = false # En subred privada, no necesita IP pública

  key_name  = var.aws_key_name != "" ? var.aws_key_name : null
  user_data = templatefile("${path.module}/user_data.tpl", {
    CHEESE_IMAGE = element(var.cheese_images, count.index)
  })

  # REQ 5: Función format() y merge()
  tags = merge(local.common_tags, {
    Name   = format("cheese-%s-ec2-%s", var.environment, element(split(":", var.cheese_images[count.index]), 1))
    Flavor = element(var.cheese_images, count.index)
  })
}

# === NETWORKING (ALB) ===
resource "aws_lb" "alb" {
  name               = format("cheese-%s-alb", var.environment)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  
  # REQ 2: El ALB se despliega en las subredes PÚBLICAS
  subnets = module.vpc.public_subnets

  tags = merge(local.common_tags, { Name = format("cheese-%s-alb", var.environment) })
}

resource "aws_lb_target_group" "tg" {
  name        = format("cheese-%s-tg", var.environment)
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    path = "/"
  }
  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Adjuntar las 3 instancias al Target Group
resource "aws_lb_target_group_attachment" "tga" {
  count            = 3
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}