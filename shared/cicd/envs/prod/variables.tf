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
  default     = "terraform-state-533267126082-us-east-1-an"
}

variable "tf_lock_table" {
  description = "DynamoDB table name used for Terraform state locking"
  type        = string
  default     = "terraform-state-lock"
}
