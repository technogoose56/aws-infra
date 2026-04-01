# ============================================================
# Production — goober-bot variable values
# ============================================================

# --- General ---
aws_region   = "us-east-1"
project_name = "goober-bot"
environment  = "prod"

# --- Networking ---
vpc_cidr           = "10.0.0.0/24"
public_subnet_cidr = "10.0.0.0/26"

# --- Compute ---
instance_type       = "t4g.nano"
spot_instance_types = ["t4g.nano", "t4g.micro", "t3a.nano", "t3.nano"]
root_volume_size    = 8
data_volume_size    = 1
swap_size_mb        = 256
docker_memory_limit = "256m"
asg_health_check_grace_period = 300

# --- ECR / CI/CD ---
github_actions_repo = "technogoose56/goober-bot"
ecr_max_image_count = 5

# --- Monitoring ---
log_retention_days = 7
budget_limit_usd   = "5"
alert_email        = "cam.loren56@gmail.com"

# --- Secrets (SSM parameter names — values are set manually) ---
telegram_bot_token_ssm_name = "/goober-bot/telegram-bot-token"
allowed_user_ids_ssm_name   = "/goober-bot/allowed-user-ids"
