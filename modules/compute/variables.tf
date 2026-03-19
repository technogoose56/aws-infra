variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment label"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

# --- Networking ---

variable "subnet_id" {
  description = "Subnet ID to launch instances in"
  type        = string
}

variable "subnet_az" {
  description = "Availability zone of the subnet"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs for the instances"
  type        = list(string)
}

# --- Instance ---

variable "instance_type" {
  description = "Primary EC2 instance type"
  type        = string
  default     = "t4g.nano"
}

variable "spot_instance_types" {
  description = "Instance types for Spot diversity"
  type        = list(string)
  default     = ["t4g.nano", "t4g.micro", "t3a.nano", "t3.nano"]
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 8
}

variable "data_volume_size" {
  description = "Data EBS volume size in GiB"
  type        = number
  default     = 1
}

variable "swap_size_mb" {
  description = "Swap file size in MB"
  type        = number
  default     = 256
}

variable "docker_memory_limit" {
  description = "Docker container memory limit"
  type        = string
  default     = "256m"
}

variable "health_check_grace_period" {
  description = "ASG health check grace period in seconds"
  type        = number
  default     = 300
}

# --- ECR ---

variable "ecr_repo_url" {
  description = "ECR repository URL for the bot image"
  type        = string
}

variable "ecr_repo_arn" {
  description = "ECR repository ARN"
  type        = string
}

# --- Secrets ---

variable "bot_token_ssm_name" {
  description = "SSM parameter name for the Telegram bot token"
  type        = string
}

variable "allowed_user_ids_ssm_name" {
  description = "SSM parameter name for allowed user IDs"
  type        = string
}

# --- Logging ---

variable "log_group_name" {
  description = "CloudWatch log group name"
  type        = string
}
