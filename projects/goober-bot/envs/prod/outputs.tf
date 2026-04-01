# --- Networking ---

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.vpc.public_subnet_id
}

# --- ECR ---

output "ecr_repository_url" {
  description = "URL of the ECR repository (use for docker push)"
  value       = module.ecr.repository_url
}

# --- CI/CD ---

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions to assume (set as AWS_GITHUB_ACTIONS_ROLE_ARN secret)"
  value       = module.github_actions_iam.role_arn
}

# --- Compute ---

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.compute.asg_name
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = module.compute.launch_template_id
}

output "data_volume_id" {
  description = "ID of the persistent data EBS volume"
  value       = module.compute.data_volume_id
}

# --- Monitoring ---

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = module.monitoring.log_group_name
}

output "sns_topic_arn" {
  description = "ARN of the alerts SNS topic"
  value       = module.monitoring.sns_topic_arn
}
