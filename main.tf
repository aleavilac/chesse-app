terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "cheese-lab"
}

# === Availability Zones disponibles (tomamos 3) ===
data "aws_availability_zones" "available" {
  state = "available"
}

# === Cálculo de subnets públicas (/24) a partir de la VPC (/16) ===
# vpc /16 -> 3 subnets /24 (newbits=8, netnum=0..2)
locals {
  public_subnet_cidrs = [for i in range(0, 3) : cidrsubnet(var.vpc_cidr, 8, i)]
}

# === VPC ===
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "cheese-vpc" }
}

# === Internet Gateway ===
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "cheese-igw" }
}

# === Subnets públicas (3 AZ) ===
resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "public-${count.index + 1}" }
}

# === Route table pública y ruta 0.0.0.0/0 -> IGW ===
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "public-rtb" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Asociar la RT pública a las 3 subnets
resource "aws_route_table_association" "public_assoc" {
  count          = 3
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public[count.index].id
}

# === Security Group del ALB: HTTP 80 abierto a Internet ===
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "HTTP 80 desde Internet"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb-sg" }
}

# === Security Group de EC2: SSH 22 solo tu IP, HTTP 80 solo desde ALB ===
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "SSH desde tu IP y HTTP solo desde ALB"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "ec2-sg" }
}

# SSH 22 desde tu IP /32
resource "aws_security_group_rule" "ec2_ssh_myip" {
  type              = "ingress"
  security_group_id = aws_security_group.ec2_sg.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_ssh_cidr]
  description       = "SSH from my IP"
}

# HTTP 80 SOLO desde el SG del ALB
resource "aws_security_group_rule" "ec2_http_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ec2_sg.id
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  description              = "HTTP from ALB"
}

# === AMI Amazon Linux 2 (más reciente) ===
data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# === ALB + Target Group + Listener: HTTP:80 ===
resource "aws_lb_target_group" "tg" {
  name     = "cheese-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id
  # Opcional: explicitar el algoritmo
  load_balancing_algorithm_type = "least_outstanding_requests" # o "least_outstanding_requests"

  # Opcional: confirmar que no hay stickiness (por defecto está desactivado)
  stickiness {
    type    = "lb_cookie"
    enabled = false
  }
  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "80"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 20
    timeout             = 5
  }

  tags = { Name = "cheese-tg" }
}

resource "aws_lb" "alb" {
  name               = "cheese-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
  enable_http2       = false # evita multiplexación del browser
  idle_timeout       = 1     # cierra la conexión rápido (solo para demo)

  tags = { Name = "cheese-alb" }
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

# === 3 EC2 (una por subnet/AZ) ===
resource "aws_instance" "web" {
  count                       = 3
  ami                         = data.aws_ami.al2.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[count.index].id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
  key_name                    = var.aws_key_name != "" ? var.aws_key_name : null

  # user_data leído desde user_data.tpl, inyectando la imagen por índice
  user_data = templatefile("${path.module}/user_data.tpl", {
    CHEESE_IMAGE = element(var.cheese_images, count.index)
  })

  tags = {
    Name      = "cheese-${count.index + 1}"
    Flavor    = element(var.cheese_images, count.index)
    IsPrimary = count.index == 0 ? "true" : "false" # Condicional: solo la 1ª
  }
}

# Registrar las 3 instancias en el Target Group
resource "aws_lb_target_group_attachment" "attach" {
  count            = 3
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}