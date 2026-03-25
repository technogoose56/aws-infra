variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "goober-bot"
}

variable "environment" {
  description = "Environment label (e.g. prod, dev)"
  type        = string
  default     = "prod"
}

# --- Networking ---

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/24"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.0.0/26"
}

# --- Compute ---

variable "instance_type" {
  description = "Primary EC2 instance type"
  type        = string
  default     = "t4g.nano"
}

variable "spot_instance_types" {
  description = "Instance types for Spot diversity (including primary)"
  type        = list(string)
  default     = ["t4g.nano", "t4g.micro", "t3a.nano", "t3.nano"]
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 8
}

variable "data_volume_size" {
  description = "Data EBS volume size in GiB (for SQLite persistence)"
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

variable "asg_health_check_grace_period" {
  description = "ASG health check grace period in seconds"
  type        = number
  default     = 300
}

# --- ECR / CI/CD ---

variable "github_actions_repo" {
  description = "GitHub repository in org/repo format granted ECR push access via OIDC"
  type        = string
  default     = "technogoose56/goober-bot"
}

variable "ecr_max_image_count" {
  description = "Maximum number of untagged images to retain in ECR"
  type        = number
  default     = 5
}

# --- Monitoring ---

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 7
}

variable "budget_limit_usd" {
  description = "Monthly budget alert threshold in USD"
  type        = string
  default     = "5"
}

variable "alert_email" {
  description = "Email address for alarm and budget notifications"
  type        = string
}

# --- Secrets (SSM parameter names — values are created manually) ---

variable "telegram_bot_token_ssm_name" {
  description = "SSM Parameter Store name for the Telegram bot token"
  type        = string
  default     = "/goober-bot/telegram-bot-token"
}

variable "allowed_user_ids_ssm_name" {
  description = "SSM Parameter Store name for allowed Telegram user IDs"
  type        = string
  default     = "/goober-bot/allowed-user-ids"
}
