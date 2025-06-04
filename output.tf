output "alb_dns_name" {
  description = "Application Load Balancer DNS"
  value       = aws_lb.web_alb.dns_name
}

output "vpc_id" {
  value = aws_vpc.testvpc.id
}

output "private_subnets" {
  value = aws_subnet.private[*].id
}

output "public_subnets" {
  value = aws_subnet.public[*].id
}
