output "github_actions_tf_role_arn" {
  description = "IAM role ARN for GitHub Actions Terraform CI/CD (set as AWS_GITHUB_ACTIONS_TF_ROLE_ARN secret)"
  value       = module.terraform_cicd_iam.role_arn
}
