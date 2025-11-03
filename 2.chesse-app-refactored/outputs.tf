output "alb_dns_name" {
  description = "URL pública del ALB para acceder a la app"
  value       = aws_lb.alb.dns_name
}

output "vpc_id" {
  description = "ID de la VPC creada por el módulo"
  value       = module.vpc.vpc_id  # <--- CORREGIDO
}

output "public_subnet_ids" {
  description = "IDs de las subredes públicas"
  value       = module.vpc.public_subnets # <--- CORREGIDO
}

output "private_subnet_ids" {
  description = "IDs de las subredes privadas"
  value       = module.vpc.private_subnets # <--- CORREGIDO
}