variable "github_repo" {
  description = "GitHub repository in org/repo format (e.g. technogoose56/aws-infra)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the existing GitHub Actions OIDC provider"
  type        = string
}

variable "tf_state_bucket" {
  description = "S3 bucket name that holds Terraform state"
  type        = string
}

variable "tf_state_key_prefix" {
  description = "S3 key prefix for Terraform state files (e.g. prod/)"
  type        = string
}

variable "tf_lock_table" {
  description = "DynamoDB table name used for Terraform state locking"
  type        = string
}
