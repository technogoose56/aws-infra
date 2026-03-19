output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "public_subnet_az" {
  description = "Availability zone of the public subnet"
  value       = aws_subnet.public.availability_zone
}

output "instance_security_group_id" {
  description = "ID of the instance security group"
  value       = aws_security_group.instance.id
}
