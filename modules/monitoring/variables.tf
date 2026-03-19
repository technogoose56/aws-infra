variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name"
  type        = string
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 7
}

variable "alert_email" {
  description = "Email address for alarm notifications"
  type        = string
}

variable "asg_name" {
  description = "Name of the Auto Scaling Group to monitor"
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly budget alert threshold in USD"
  type        = string
  default     = "5"
}
