#!/bin/bash
set -euxo pipefail

# ============================================================
# Goober-Bot EC2 Bootstrap Script
# Runs on every instance launch (including Spot replacements)
# ============================================================

REGION="${region}"
PROJECT_NAME="${project_name}"
ECR_REPO_URL="${ecr_repo_url}"
BOT_TOKEN_SSM="${bot_token_ssm_name}"
ALLOWED_IDS_SSM="${allowed_user_ids_ssm_name}"
DATA_VOLUME_TAG="${data_volume_tag}"
SWAP_SIZE_MB="${swap_size_mb}"
DOCKER_MEMORY="${docker_memory_limit}"
LOG_GROUP="${log_group_name}"

# --- System Setup ---
dnf update -y -q
dnf install -y -q docker aws-cli-2

# --- Swap (safety net for 512 MB instance) ---
dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile swap swap defaults 0 0' >> /etc/fstab

# --- Start Docker ---
systemctl enable docker
systemctl start docker

# --- Attach Persistent Data Volume ---
INSTANCE_ID=$(ec2-metadata --instance-id | awk '{print $2}')
AZ=$(ec2-metadata --availability-zone | awk '{print $2}')

# Find the data volume by tag
VOLUME_ID=$(aws ec2 describe-volumes \
  --region "$REGION" \
  --filters \
    "Name=tag:Name,Values=$DATA_VOLUME_TAG" \
    "Name=availability-zone,Values=$AZ" \
    "Name=status,Values=available" \
  --query 'Volumes[0].VolumeId' \
  --output text)

if [ "$VOLUME_ID" != "None" ] && [ -n "$VOLUME_ID" ]; then
  # Attach the volume
  aws ec2 attach-volume \
    --volume-id "$VOLUME_ID" \
    --instance-id "$INSTANCE_ID" \
    --device /dev/xvdf \
    --region "$REGION"

  # Wait for the volume to attach
  for i in $(seq 1 30); do
    if [ -b /dev/xvdf ]; then
      break
    fi
    sleep 2
  done

  # Format if new (no filesystem detected)
  if ! blkid /dev/xvdf > /dev/null 2>&1; then
    mkfs.ext4 /dev/xvdf
  fi

  mkdir -p /data
  mount /dev/xvdf /data
  echo '/dev/xvdf /data ext4 defaults,nofail 0 2' >> /etc/fstab
else
  # Volume not found — create /data on root volume as fallback
  mkdir -p /data
  echo "WARNING: Data volume not found, using root volume for /data"
fi

# --- Pull and Run Bot ---
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_REPO_URL"

BOT_TOKEN=$(aws ssm get-parameter \
  --name "$BOT_TOKEN_SSM" \
  --with-decryption \
  --query Parameter.Value \
  --output text \
  --region "$REGION")

ALLOWED_IDS=$(aws ssm get-parameter \
  --name "$ALLOWED_IDS_SSM" \
  --query Parameter.Value \
  --output text \
  --region "$REGION" 2>/dev/null || echo "")

docker pull "$ECR_REPO_URL:latest"

docker run -d \
  --name "$PROJECT_NAME" \
  --restart unless-stopped \
  --memory="$DOCKER_MEMORY" \
  --stop-timeout=30 \
  -v /data:/data \
  -e TELEGRAM_BOT_TOKEN="$BOT_TOKEN" \
  -e ALLOWED_USER_IDS="$ALLOWED_IDS" \
  --log-driver=awslogs \
  --log-opt awslogs-region="$REGION" \
  --log-opt awslogs-group="$LOG_GROUP" \
  --log-opt awslogs-stream="$INSTANCE_ID" \
  --log-opt awslogs-create-group=true \
  "$ECR_REPO_URL:latest"
