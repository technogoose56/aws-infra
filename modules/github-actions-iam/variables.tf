variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in org/repo format (e.g. technogoose56/goober-bot)"
  type        = string
}

variable "ecr_repo_arn" {
  description = "ARN of the ECR repository to grant push access to"
  type        = string
}
