output "alb_dns_name" {
  description = "URL pública del ALB"
  value       = aws_lb.alb.dns_name
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}