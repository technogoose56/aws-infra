output "role_arn" {
  description = "ARN of the IAM role for GitHub Actions Terraform CI/CD to assume"
  value       = aws_iam_role.terraform_cicd.arn
}
