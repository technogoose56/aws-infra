# ============================================================
# Production CI/CD Environment
# ============================================================
# Manages IAM for GitHub Actions Terraform CI/CD.
#
# The GitHub OIDC provider is owned by envs/prod/goober-bot
# (created via the github-actions-iam module). It is looked
# up here via a data source to avoid duplication.
# ============================================================

data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

module "terraform_cicd_iam" {
  source = "../../../modules/terraform-cicd-iam"

  github_repo         = var.github_actions_tf_repo
  oidc_provider_arn   = data.aws_iam_openid_connect_provider.github.arn
  tf_state_bucket     = var.tf_state_bucket
  tf_state_key_prefix = var.tf_state_key_prefix
  tf_lock_table       = var.tf_lock_table
}
