# ============================================================
# Production Environment — Module Composition
# ============================================================

locals {
  log_group_name = "/${var.project_name}/application"
}

# --- Networking ---

module "vpc" {
  source = "../../../../modules/vpc"

  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
}

# --- Container Registry ---

module "ecr" {
  source = "../../../../modules/ecr"

  repository_name = var.project_name
  max_image_count = var.ecr_max_image_count
}

# --- CI/CD (GitHub Actions OIDC) ---

module "github_actions_iam" {
  source = "../../../../modules/github-actions-iam"

  project_name = var.project_name
  github_repo  = var.github_actions_repo
  ecr_repo_arn = module.ecr.repository_arn
}

# --- Compute (EC2 Spot via ASG) ---

module "compute" {
  source = "../../../../modules/compute"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  # Networking
  subnet_id          = module.vpc.public_subnet_id
  subnet_az          = module.vpc.public_subnet_az
  security_group_ids = [module.vpc.instance_security_group_id]

  # Instance configuration
  instance_type             = var.instance_type
  spot_instance_types       = var.spot_instance_types
  root_volume_size          = var.root_volume_size
  data_volume_size          = var.data_volume_size
  swap_size_mb              = var.swap_size_mb
  docker_memory_limit       = var.docker_memory_limit
  health_check_grace_period = var.asg_health_check_grace_period

  # ECR
  ecr_repo_url = module.ecr.repository_url
  ecr_repo_arn = module.ecr.repository_arn

  # Secrets
  bot_token_ssm_name        = var.telegram_bot_token_ssm_name
  allowed_user_ids_ssm_name = var.allowed_user_ids_ssm_name

  # Logging
  log_group_name = local.log_group_name
}

# --- Monitoring & Alerts ---

module "monitoring" {
  source = "../../../../modules/monitoring"

  project_name       = var.project_name
  log_group_name     = local.log_group_name
  log_retention_days = var.log_retention_days
  alert_email        = var.alert_email
  asg_name           = module.compute.asg_name
  budget_limit_usd   = var.budget_limit_usd
}
