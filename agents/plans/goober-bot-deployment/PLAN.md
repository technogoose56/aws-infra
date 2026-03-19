# Goober-Bot AWS Deployment Plan

## Overview

Deploy [goober-bot](https://github.com/technogoose56/goober-bot) — a lightweight Go Telegram bot — to AWS using Terraform. The bot is a long-running, single-instance process that uses Telegram long-polling, SQLite for persistence, and makes outbound HTTPS calls to the Telegram and NOAA APIs. It has no inbound HTTP traffic requirements.

**Guiding constraint:** Get as close to free as possible. Use the cheapest viable compute option.

---

## Application Profile

| Property              | Value                                                        |
| --------------------- | ------------------------------------------------------------ |
| Language / Runtime    | Go 1.26, compiled static binary (~few MB)                    |
| Container Image       | `scratch`-based Docker image (tiny)                          |
| Database              | Embedded SQLite (`/data/schedules.db`)                       |
| Secrets               | `TELEGRAM_BOT_TOKEN` (required), `ALLOWED_USER_IDS` (optional) |
| Network – Inbound     | **None** (long-polling, no HTTP listener)                    |
| Network – Outbound    | HTTPS to `api.telegram.org`, `api.weather.gov`               |
| Concurrency           | Single-instance only (SQLite limitation)                     |
| Persistent Storage    | Required for `/data` directory                               |
| Health Check          | No HTTP endpoint; must use process-level checks              |
| Resource Needs        | <50 MB RAM, negligible CPU                                   |

---

## Architecture Decision: EC2 Spot Instance (t4g.nano) via Auto Scaling Group

### Options Evaluated

| Option | Est. Monthly Cost | Verdict | Reason |
| --- | --- | --- | --- |
| **Lambda** | N/A | Rejected | Long-running process; 15-min max execution. Polling model incompatible. |
| **App Runner** | ~$7+ | Rejected | HTTP request-driven; not a fit for long-polling. |
| **Lightsail Container** | ~$7 | Rejected | Less flexible, harder to manage with Terraform. |
| **ECS Fargate** | ~$9 | Rejected | Too expensive for a tiny bot. No servers to manage, but 5-9x the cost of Spot EC2. |
| **EC2 t4g.nano On-Demand** | ~$3.71 | Runner-up | Simple, predictable. Fallback if Spot is problematic. |
| **EC2 t4g.nano Spot** | **~$1.74** | **Selected** | Cheapest option. t4g.nano has <5% interruption rate. ASG auto-replaces interrupted instances. |

### Why EC2 Spot Works Here

1. **Ultra-low interruption risk** — nano instances have the lowest interruption rates (<5%) because AWS reclaims larger instances first.
2. **Single-instance, non-critical** — a weather bot can tolerate 2-3 minutes of downtime during replacement.
3. **Graceful shutdown** — goober-bot handles SIGTERM (stops polling, waits for cron jobs, closes SQLite).
4. **Auto Scaling Group** — ASG with min=max=desired=1 automatically launches a replacement if a Spot instance is interrupted or fails a health check.
5. **EBS persistence** — SQLite data lives on a persistent EBS volume that survives instance termination. A separate data volume is attached on boot via user data.

### Why Run Docker (Not Bare Binary)

Running the Go binary directly would save ~50-80 MB of RAM, but Docker provides:
- Identical runtime to local development (same `Dockerfile` already exists)
- `--restart unless-stopped` for automatic process recovery
- Clean isolation and reproducible deployments
- Easy rollback (just pull a different image tag)
- 512 MB is sufficient: ~80 MB kernel + ~70 MB Docker + ~30 MB app = ~180 MB used, ~330 MB free + swap

The RAM savings of bare binary don't justify losing Docker's operational benefits.

### Cost Estimate

| Resource | Specification | Est. Monthly Cost |
| --- | --- | --- |
| EC2 Spot t4g.nano | 2 vCPU (5% baseline) / 0.5 GB / 24x7 | ~$1.10 |
| EBS gp3 (root) | 8 GiB | ~$0.64 |
| EBS gp3 (data) | 1 GiB, persistent across instances | ~$0.08 |
| ECR | 1 image, <50 MB | Free tier / ~$0.00 |
| CloudWatch Logs | Minimal volume | Free tier / ~$0.00 |
| Elastic IP | Associated to running instance | $0.00 (free when attached) |
| NAT Gateway | **Not used** — public subnet | $0.00 |
| **Total** | | **~$1.82/month** |

> **vs. Fargate:** This is ~80% cheaper than the ECS Fargate approach (~$9/mo) and ~50% cheaper than on-demand EC2 (~$3.71/mo).

---

## Infrastructure Components

### Phase 1 — Minimum Viable Deployment (MVP)
Status: **Terraform Complete — Awaiting AWS Auth + Deploy**

Build the bare minimum to get goober-bot running on AWS with Spot EC2.

#### 1.1 Terraform Foundation
- [x] Terraform backend configuration (S3 + DynamoDB for state locking) — `envs/prod/backend.tf`
- [x] AWS provider configuration with version constraints — `envs/prod/providers.tf`
- [x] Variables and locals for project-wide settings — `envs/prod/variables.tf`
- [x] `.gitignore` for Terraform artifacts (`.terraform/`, `*.tfstate*`, `*.tfvars`)

#### 1.2 Networking (VPC)
- [x] VPC with a single public subnet (one AZ — non-HA bot doesn't need multi-AZ) — `modules/vpc/`
- [x] Internet Gateway
- [x] Route table associating public subnet to IGW
- [x] Security group: **all outbound allowed, all inbound denied**
  - The bot initiates all connections (Telegram long-poll, NOAA API)
  - No SSH access by default (use SSM Session Manager if debugging is needed)

#### 1.3 Container Registry (ECR)
- [x] ECR repository for `goober-bot` images — `modules/ecr/`
- [x] Lifecycle policy: keep only the last 5 images (cost saving)

#### 1.4 Secrets Management
- [ ] SSM Parameter Store `SecureString` for `TELEGRAM_BOT_TOKEN` — **manual, requires AWS auth**
- [ ] SSM Parameter Store `String` for `ALLOWED_USER_IDS` — **manual, requires AWS auth**
- [x] Note: SSM parameters are created manually (one-time); Terraform references them by name, doesn't manage the values

#### 1.5 Persistent Data Volume (EBS)
- [x] Dedicated 1 GiB gp3 EBS volume for `/data` (SQLite database) — `modules/compute/main.tf`
- [x] Volume exists independently of the EC2 instance lifecycle
- [x] Tagged for identification by user data script
- [x] User data script attaches, formats (if new), and mounts the volume on boot

> **Why a separate EBS volume instead of using the root volume?**
> The root volume is destroyed when the ASG replaces an instance. A dedicated data volume persists independently, surviving Spot interruptions and instance replacements. The user data script finds it by tag and reattaches it.

#### 1.6 Compute (EC2 Spot via ASG)
- [x] **Launch Template:** — `modules/compute/main.tf`
  - AMI: Amazon Linux 2023 ARM64 (latest, looked up via SSM parameter)
  - Instance type: `t4g.nano`
  - Spot market options: `spot` with `capacity-optimized` allocation strategy
  - Credit specification: `standard` (avoid surprise surplus credit charges)
  - Root volume: 8 GiB gp3 (sufficient for AL2023 + Docker)
  - IAM instance profile (see below)
  - Security group: outbound-only
  - Network: public subnet, auto-assign public IP
  - User data script (see below)
  - Metadata options: IMDSv2 required (security best practice)
- [x] **Auto Scaling Group:** — `modules/compute/main.tf`
  - Min / max / desired capacity: 1 / 1 / 1
  - Single AZ (must match the EBS data volume's AZ)
  - Mixed instances policy with Spot allocation:
    - Primary: `t4g.nano`
    - Overrides: `t4g.micro`, `t3a.nano`, `t3.nano` (fallback if t4g.nano Spot capacity is unavailable)
  - Health check: EC2-level (instance status checks)
  - Capacity rebalance: enabled (proactively replaces at-risk Spot instances)
  - Cooldown / grace period: 300s (allow time for Docker pull + bot startup)
  - Instance refresh: rolling update for launch template changes
- [x] **IAM Instance Profile / Role:** — `modules/compute/main.tf`
  - `ecr:GetAuthorizationToken`, `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` — pull images from ECR
  - `ssm:GetParameter` (with `kms:Decrypt`) — read bot token and allowed user IDs
  - `ec2:AttachVolume`, `ec2:DescribeVolumes` — attach the persistent data volume
  - `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` — write to CloudWatch Logs (via Docker awslogs driver)
  - `sts:GetCallerIdentity` — needed by user data script

#### 1.7 User Data Script (cloud-init)

The user data script runs on every instance launch (including Spot replacements):

```bash
#!/bin/bash
set -euxo pipefail

# --- System Setup ---
dnf update -y -q
dnf install -y -q docker aws-cli

# --- Swap (safety net for 512 MB instance) ---
dd if=/dev/zero of=/swapfile bs=1M count=256
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile swap swap defaults 0 0' >> /etc/fstab

# --- Start Docker ---
systemctl enable docker
systemctl start docker

# --- Attach Persistent Data Volume ---
REGION=$(ec2-metadata --availability-zone | sed 's/placement: //;s/.$//')
INSTANCE_ID=$(ec2-metadata --instance-id | awk '{print $2}')

# Find the data volume by tag
VOLUME_ID=$(aws ec2 describe-volumes \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=goober-bot-data" "Name=availability-zone,Values=$(ec2-metadata --availability-zone | awk '{print $2}')" \
  --query 'Volumes[0].VolumeId' --output text)

# Attach if not already attached
if [ "$VOLUME_ID" != "None" ]; then
  aws ec2 attach-volume --volume-id "$VOLUME_ID" --instance-id "$INSTANCE_ID" --device /dev/xvdf --region "$REGION" || true
  sleep 5

  # Format if new (no filesystem)
  if ! blkid /dev/xvdf; then
    mkfs.ext4 /dev/xvdf
  fi

  mkdir -p /data
  mount /dev/xvdf /data
  echo '/dev/xvdf /data ext4 defaults,nofail 0 2' >> /etc/fstab
fi

# --- Pull and Run Bot ---
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REPO"

BOT_TOKEN=$(aws ssm get-parameter --name /goober-bot/telegram-bot-token --with-decryption --query Parameter.Value --output text --region "$REGION")
ALLOWED_IDS=$(aws ssm get-parameter --name /goober-bot/allowed-user-ids --query Parameter.Value --output text --region "$REGION" 2>/dev/null || echo "")

docker pull "$ECR_REPO/goober-bot:latest"

docker run -d \
  --name goober-bot \
  --restart unless-stopped \
  --memory=256m \
  --stop-timeout=30 \
  -v /data:/data \
  -e TELEGRAM_BOT_TOKEN="$BOT_TOKEN" \
  -e ALLOWED_USER_IDS="$ALLOWED_IDS" \
  --log-driver=awslogs \
  --log-opt awslogs-region="$REGION" \
  --log-opt awslogs-group=/goober-bot/application \
  --log-opt awslogs-stream="$INSTANCE_ID" \
  --log-opt awslogs-create-group=true \
  "$ECR_REPO/goober-bot:latest"
```

#### 1.8 Monitoring & Alerts
- [x] CloudWatch log group `/goober-bot/application` with 7-day retention — `modules/monitoring/main.tf`
- [x] CloudWatch alarm: ASG `GroupInServiceInstances` < 1 for 5 minutes (detect prolonged outages) — `modules/monitoring/main.tf`
- [x] SNS topic for alarm notifications (email) — `modules/monitoring/main.tf`
- [x] Monthly budget alert ($5 threshold, 80% + 100% notifications) — `modules/monitoring/main.tf`

---

### Phase 2 — Operational Improvements (Future)
Status: **Not Started**

Improvements to make once the bot is running stably.

- [ ] CI/CD pipeline (GitHub Actions): build ARM64 image, push to ECR, trigger ASG instance refresh
- [ ] Automated image build on push to `main` in goober-bot repo
- [ ] SSM Session Manager access for debugging (connect to running instance without SSH)
- [ ] CloudWatch dashboard for basic metrics (CPU credits, memory, instance replacements)
- [ ] Spot interruption EventBridge rule + SNS notification
- [ ] Scheduled EBS snapshot for data volume backup (weekly, retain 4)

### Phase 3 — Hardening (Future)
Status: **Not Started**

Security and resilience improvements.

- [ ] Restrict IAM policies to minimum required ARNs
- [ ] Enable VPC Flow Logs
- [ ] Move to private subnet + VPC endpoints (if security posture requires it)
- [ ] Add process-level health check script (verify Docker container is running + bot is responsive)
- [ ] Terraform state encryption review
- [ ] Consider Graviton3 instance types (t4g → t4g equivalent on newer generation) when available and cheaper

---

## Terraform Project Structure

```
aws-infra/
├── agents/plans/goober-bot-deployment/PLAN.md   # This file
├── modules/
│   ├── vpc/                    # VPC, subnet, IGW, route tables, security groups
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── ecr/                    # ECR repository + lifecycle policy
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── compute/                # Launch template, ASG, IAM role, EBS data volume
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── user_data.sh.tpl   # Templatefile for cloud-init script
│   └── monitoring/             # CloudWatch logs, alarms, SNS, budgets
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── envs/
│   └── prod/                   # Production environment
│       ├── main.tf             # Module composition
│       ├── variables.tf        # Environment-specific variables
│       ├── outputs.tf          # Top-level outputs
│       ├── terraform.tfvars    # Variable values (git-ignored)
│       ├── backend.tf          # S3 backend configuration
│       └── providers.tf        # AWS provider + version constraints
├── .gitignore
└── README.md
```

### Key Design Decisions

1. **Modular structure** — each infrastructure concern is a separate module for reusability and clarity.
2. **Environment separation** — `envs/prod/` composes modules. Adding `envs/dev/` later is trivial.
3. **No `terraform.tfvars` in git** — sensitive values stay out of version control.
4. **Single AZ** — the bot is non-critical and single-instance; multi-AZ adds cost and complexity with no benefit.
5. **Public subnet, no NAT** — saves ~$32/mo. Acceptable because the bot has zero inbound ports.
6. **No EFS** — SQLite doesn't work reliably over NFS. A dedicated EBS volume is simpler, cheaper, and faster.
7. **ASG over raw Spot request** — the legacy `RequestSpotInstances` API is deprecated. ASG with mixed instances policy is the recommended approach and provides automatic replacement on interruption.
8. **Docker over bare binary** — operational convenience outweighs the ~50-80 MB RAM overhead on 512 MB instance.
9. **User data bootstrapping** — instance is stateless except for the attached EBS data volume. Any instance replacement gets the same setup via cloud-init.
10. **T4g credit specification: standard** — prevents surprise surplus credit charges on Spot instances. The bot uses <5% CPU baseline anyway.

---

## Configuration Variables

| Variable | Default | Description |
| --- | --- | --- |
| `aws_region` | `us-east-1` | AWS region |
| `project_name` | `goober-bot` | Used for resource naming and tagging |
| `environment` | `prod` | Environment label |
| `vpc_cidr` | `10.0.0.0/24` | VPC CIDR (small — only need a handful of IPs) |
| `public_subnet_cidr` | `10.0.0.0/26` | Public subnet CIDR |
| `instance_type` | `t4g.nano` | Primary EC2 instance type |
| `spot_instance_types` | `["t4g.nano","t4g.micro","t3a.nano","t3.nano"]` | Fallback types for Spot diversity |
| `root_volume_size` | `8` | Root EBS volume size (GiB) |
| `data_volume_size` | `1` | Data EBS volume size (GiB) for SQLite |
| `swap_size_mb` | `256` | Swap file size (MB) |
| `docker_memory_limit` | `256m` | Docker container memory cap |
| `asg_health_check_grace` | `300` | Health check grace period (seconds) |
| `log_retention_days` | `7` | CloudWatch log retention |
| `ecr_max_image_count` | `5` | Max untagged images to retain in ECR |
| `budget_limit_usd` | `5` | Monthly budget alert threshold |
| `alert_email` | *(required)* | Email for alarm/budget notifications |
| `telegram_bot_token_ssm_name` | `/goober-bot/telegram-bot-token` | SSM parameter name for bot token |
| `allowed_user_ids_ssm_name` | `/goober-bot/allowed-user-ids` | SSM parameter name for user whitelist |

---

## Deployment Workflow (Phase 1 — Manual)

### One-Time Bootstrap (before first `terraform apply`)

1. **Create Terraform state backend:**
   ```bash
   # Create S3 bucket for state
   aws s3api create-bucket --bucket <your-tf-state-bucket> --region us-east-1

   # Enable versioning
   aws s3api put-bucket-versioning --bucket <your-tf-state-bucket> --versioning-configuration Status=Enabled

   # Create DynamoDB table for state locking
   aws dynamodb create-table \
     --table-name terraform-state-lock \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST \
     --region us-east-1
   ```

2. **Store secrets in SSM Parameter Store:**
   ```bash
   aws ssm put-parameter \
     --name /goober-bot/telegram-bot-token \
     --type SecureString \
     --value "YOUR_BOT_TOKEN" \
     --region us-east-1

   aws ssm put-parameter \
     --name /goober-bot/allowed-user-ids \
     --type String \
     --value "123456789,987654321" \
     --region us-east-1
   ```

### Build and Push Docker Image

```bash
# From the goober-bot repo directory
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
ECR_REPO="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# Authenticate to ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO

# Build for ARM64 (required for t4g Graviton instances)
docker buildx build --platform linux/arm64 -t goober-bot .

# Tag and push
docker tag goober-bot:latest $ECR_REPO/goober-bot:latest
docker push $ECR_REPO/goober-bot:latest
```

> **Important:** The image must be built for `linux/arm64` since t4g instances use Graviton (ARM) processors. If building on an x86 machine, use `docker buildx` with `--platform linux/arm64`.

### Apply Terraform

```bash
cd aws-infra/envs/prod
terraform init
terraform plan
terraform apply
```

### Verify

1. Check ASG in EC2 console — should show 1 instance in service
2. Check CloudWatch Logs for `/goober-bot/application` log group
3. Send a Telegram command to the bot (e.g., `/weather`)
4. Verify SQLite data persists: terminate the instance, wait for ASG replacement, check bot still has schedules

---

## Spot Interruption Handling

When AWS reclaims a Spot instance:

1. **2-minute warning** — AWS sends SIGTERM to the instance
2. **goober-bot shuts down gracefully** — stops polling, waits for running cron jobs, closes SQLite database
3. **Instance terminates** — root volume is destroyed, but the **data EBS volume persists**
4. **ASG detects missing instance** — launches a replacement Spot instance
5. **New instance boots** — user data script runs: installs Docker, attaches data volume, pulls image, starts bot
6. **Bot resumes** — loads schedules from SQLite, reconnects to Telegram long-polling

**Expected downtime per interruption:** 2-5 minutes (instance launch + Docker pull + bot startup).
**Expected frequency:** Rare — t4g.nano interruptions are historically <5% per month in us-east-1.

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Spot interruption | Very Low | Bot offline 2-5 min | ASG auto-replaces; instance type diversification |
| Spot capacity unavailable | Very Low | Bot can't launch | Mixed instances policy with 4 fallback types; on-demand fallback in ASG if needed |
| Bot crash loop | Medium | Bot offline | Docker `--restart unless-stopped`; ASG health check eventually replaces |
| EBS data volume detach failure | Low | Bot starts without data | User data handles gracefully; data is small enough to recreate |
| OOM on t4g.nano | Low | Container killed | 256 MB swap + `--memory=256m` Docker limit; bot uses <50 MB |
| T4g CPU credit exhaustion | Very Low | Throttled to 5% baseline | Bot uses <1% CPU normally; standard mode prevents surprise charges |
| Cost overrun | Very Low | Unexpected bill | Budget alert at $5/mo; Spot pricing is predictable |
| Telegram token leaked | Low | Bot hijacked | Stored in SSM SecureString with KMS encryption; never in code or Terraform state |
| User data script failure | Low | Instance runs but bot doesn't start | CloudWatch logs capture cloud-init output; ASG health check detects |

---

## Implementation Order

Phase 1 should be implemented in this order (each step depends on the previous):

1. ~~`.gitignore` + Terraform foundation (`backend.tf`, `providers.tf`, variables)~~ **DONE**
2. ~~VPC module (VPC, subnet, IGW, route table, security groups)~~ **DONE**
3. ~~ECR module (repository + lifecycle policy)~~ **DONE**
4. ~~Compute module (launch template, ASG, IAM role, EBS data volume, user data script)~~ **DONE**
5. ~~Monitoring module (CloudWatch log group, ASG alarm, SNS topic, budget)~~ **DONE**
6. ~~Environment composition (`envs/prod/main.tf` wiring modules together)~~ **DONE**
7. Create Terraform state backend (S3 bucket + DynamoDB table) — **requires AWS auth**
8. Store SSM parameters (bot token, allowed user IDs) — **requires AWS auth**
9. Build and push ARM64 Docker image to ECR — **requires AWS auth**
10. `terraform init` + `terraform apply` + manual verification — **requires AWS auth**
