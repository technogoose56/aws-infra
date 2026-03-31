variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# --- Terraform CI/CD ---

variable "github_actions_tf_repo" {
  description = "GitHub repository in org/repo format granted Terraform plan/apply access via OIDC"
  type        = string
  default     = "technogoose56/aws-infra"
}

variable "tf_state_bucket" {
  description = "S3 bucket name holding Terraform state (used to scope CI/CD IAM permissions)"
  type        = string
  default     = "goober-bot-terraform-state"
}

variable "tf_state_key_prefix" {
  description = "S3 key prefix for Terraform state files"
  type        = string
  default     = "prod/"
}

variable "tf_lock_table" {
  description = "DynamoDB table name used for Terraform state locking"
  type        = string
  default     = "terraform-state-lock"
}
