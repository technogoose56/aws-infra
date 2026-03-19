output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.bot.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.bot.arn
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.bot.id
}

output "instance_role_arn" {
  description = "ARN of the IAM instance role"
  value       = aws_iam_role.instance.arn
}

output "data_volume_id" {
  description = "ID of the persistent data EBS volume"
  value       = aws_ebs_volume.data.id
}
