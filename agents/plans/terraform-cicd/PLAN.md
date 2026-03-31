# Terraform CI/CD — GitHub Actions Plan

## Overview

Add a GitHub Actions workflow to this repo (`aws-infra`) that:

1. **Automatically on push to `main`** — runs `terraform plan` and posts the output as a job summary.
2. **Requires manual approval** — runs `terraform apply` after a human reviews and approves the plan, gated by a GitHub Environment protection rule.

Authentication uses OIDC (no long-lived AWS credentials). The OIDC provider already exists in AWS (created by the `github-actions-iam` module), but a new IAM role is needed for this repo with Terraform-scoped permissions.

---

## Architecture

```
push to main
     │
     ▼
┌─────────────┐       posts plan output
│  plan job   │ ──────► job summary
└─────────────┘
     │
     │  needs: [plan]
     ▼
┌─────────────────────────────────────────┐
│  apply job  │  environment: production  │  ◄── required reviewer approves
└─────────────────────────────────────────┘
     │
     ▼
  terraform apply (auto-approved: -auto-approve)
```

The `production` GitHub Environment has a **required reviewer** protection rule. The apply job can't run until a reviewer approves it in the GitHub UI. This uses the same `environment:production` OIDC condition already in the existing IAM role pattern.

---

## What Needs to Be Built

### Phase 1 — AWS IAM Role for Terraform

**Status: Complete**

The existing `modules/github-actions-iam` role is scoped to `technogoose56/goober-bot` and only has ECR push permissions. We need a separate role for `aws-infra` Terraform operations.

Two options:
| Option | Verdict | Reason |
|---|---|---|
| Expand existing module with second role | Rejected | Mixes concerns — goober-bot CI/CD and infra CI/CD are unrelated |
| New IAM module: `modules/terraform-cicd-iam` | **Selected** | Clean separation; scoped to this repo's Terraform needs |

The new role needs to:
- Trust the **existing** OIDC provider (already created, reuse it)
- Trust `repo:technogoose56/aws-infra:ref:refs/heads/main` (plan job — on push)
- Trust `repo:technogoose56/aws-infra:environment:production` (apply job — after approval)
- Have permissions to read/write the Terraform S3 state backend and DynamoDB lock table
- Have permissions to manage all resources Terraform touches: VPC, EC2, ASG, ECR, IAM, CloudWatch, SNS, Budgets

**IAM permissions scope:**

```
S3:
  - s3:GetObject, s3:PutObject, s3:DeleteObject  → state bucket/key
  - s3:ListBucket                                 → state bucket

DynamoDB:
  - dynamodb:GetItem, dynamodb:PutItem, dynamodb:DeleteItem → state lock table

Terraform-managed AWS resources (all needed for plan + apply):
  - ec2:* (scoped to VPC, subnet, IGW, route tables, SG, launch template, ASG, EBS, EIP)
  - ecr:* (scoped to goober-bot repo)
  - iam:* (scoped to goober-bot-* roles/policies/instance profiles)
  - logs:* (scoped to /goober-bot/* log groups)
  - sns:* (scoped to goober-bot-* topics)
  - cloudwatch:* (scoped to goober-bot-* alarms)
  - budgets:* (account-level — no resource ARN scoping available)
  - ssm:GetParameter (for AMI lookup via SSM public parameter)
```

> **Note:** `iam:*` scoped to the project prefix is required because Terraform creates instance profiles and role policies. Use `iam:PassRole` with a condition to prevent privilege escalation.

The CI/CD IAM config is non-specific to goober-bot, so it lives in its own Terraform environment (`envs/prod/cicd/`) rather than inside `envs/prod/goober-bot/`. The OIDC provider is already owned by the goober-bot env and is looked up via a `data` source.

**Tasks:**
- [x] Create `modules/terraform-cicd-iam/main.tf` — new IAM role + scoped policies
- [x] Create `modules/terraform-cicd-iam/variables.tf` — `github_repo`, `oidc_provider_arn`, `tf_state_bucket`, `tf_state_key_prefix`, `tf_lock_table`
- [x] Create `modules/terraform-cicd-iam/outputs.tf` — `role_arn`
- [x] Add `oidc_provider_arn` output to `modules/github-actions-iam/outputs.tf`
- [x] Create `envs/prod/cicd/backend.tf` — separate state key (`prod/cicd/terraform.tfstate`)
- [x] Create `envs/prod/cicd/providers.tf`
- [x] Create `envs/prod/cicd/variables.tf` — `github_actions_tf_repo`, `tf_state_bucket`, `tf_state_key_prefix`, `tf_lock_table`
- [x] Create `envs/prod/cicd/main.tf` — data source for OIDC provider + `terraform_cicd_iam` module
- [x] Create `envs/prod/cicd/outputs.tf` — `github_actions_tf_role_arn`

---

### Phase 2 — GitHub Actions Workflow

**Status: Complete**

**File:** `.github/workflows/terraform.yml`

#### Workflow Trigger

```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:        # allow manual re-run of plan+apply
```

#### Job 1: `plan`

- Runs on: every push to `main` (and `workflow_dispatch`)
- OIDC condition used: `repo:technogoose56/aws-infra:ref:refs/heads/main`
- Steps:
  1. Checkout
  2. Setup Terraform (pin version to match what's used locally)
  3. Configure AWS credentials via OIDC (`aws-actions/configure-aws-credentials`)
  4. `terraform init` (S3 backend)
  5. `terraform validate`
  6. `terraform plan -out=tfplan`
  7. `terraform show -no-color tfplan` → write to `$GITHUB_STEP_SUMMARY`
  8. Upload `tfplan` as a workflow artifact (used by apply job)

#### Job 2: `apply`

- Runs on: after `plan` succeeds, but **gated by the `production` GitHub Environment**
- `needs: [plan]`
- `environment: production` ← triggers required reviewer approval in GitHub UI
- OIDC condition used: `repo:technogoose56/aws-infra:environment:production`
- Steps:
  1. Checkout
  2. Setup Terraform (same pinned version)
  3. Configure AWS credentials via OIDC (same role, different OIDC sub)
  4. `terraform init` (S3 backend)
  5. Download `tfplan` artifact
  6. `terraform apply -auto-approve tfplan`

**Tasks:**
- [x] Create `.github/workflows/terraform.yml`
- [x] Pin Terraform version via `TF_VERSION` env var (currently `1.12.0` — update to match local)

---

### Phase 3 — GitHub & AWS Setup (Manual, One-Time)

**Status: Not Started**

These steps require manual action outside of code and Terraform.

- [ ] Create a `production` environment in the GitHub repo settings
  - Add at least one required reviewer
  - Optionally: restrict to the `main` branch only
- [ ] Run `terraform init && terraform apply` in `envs/prod/cicd/` to create the new IAM role
- [ ] Note the `github_actions_tf_role_arn` output value
- [ ] Add `AWS_GITHUB_ACTIONS_TF_ROLE_ARN` as a GitHub Actions secret (repo level)
- [ ] Add `TF_VAR_ALERT_EMAIL` as a GitHub Actions secret (the email used for CloudWatch/budget alerts)

---

## Configuration Variables

| Variable | Where | Description |
|---|---|---|
| `github_actions_repo` | `envs/prod/goober-bot/variables.tf` | This repo in `org/repo` format (default: `technogoose56/aws-infra`) |
| `tf_state_bucket` | `envs/prod/goober-bot/variables.tf` | S3 bucket name for Terraform state |
| `tf_state_key_prefix` | `envs/prod/goober-bot/variables.tf` | S3 key prefix for state files |
| `tf_lock_table` | `envs/prod/goober-bot/variables.tf` | DynamoDB table name for state locking |
| `terraform_version` | `.github/workflows/terraform.yml` | Pinned Terraform version (match local) |

---

## Key Design Decisions

1. **GitHub Environments for approval gate** — the `production` environment protection rule is the most native GitHub mechanism for requiring human approval. It also integrates cleanly with the OIDC trust policy (the `environment:production` sub condition is already established).

2. **Plan artifact passed to apply** — the `tfplan` binary is uploaded as a workflow artifact and downloaded by the apply job. This ensures the apply job executes exactly the plan that was reviewed, not a re-generated plan.

3. **Separate IAM role from goober-bot CI/CD role** — the existing role is for the goober-bot repo with ECR push permissions. The Terraform role is for this repo with broader infrastructure permissions. Keeping them separate follows least-privilege and makes auditing cleaner.

4. **Reuse existing OIDC provider** — AWS only allows one OIDC provider per URL per account. The provider was created by the `github-actions-iam` module; the new module references it by ARN as an input variable rather than creating a duplicate.

5. **Both jobs use the same IAM role** — the OIDC trust policy allows both `ref:refs/heads/main` (plan) and `environment:production` (apply) conditions on the same role. This avoids managing two separate roles for the same repo.

6. **`workflow_dispatch` trigger** — allows manually re-running the full plan+apply cycle without needing a new push. Useful for re-applying after a failed apply or for running the workflow in a fresh state.

---

## Implementation Order

1. [x] Create `modules/terraform-cicd-iam/` (Terraform module)
2. [x] Add `oidc_provider_arn` output to `modules/github-actions-iam/`
3. [x] Create `envs/prod/cicd/` environment
4. [x] Create `.github/workflows/terraform.yml`
5. [ ] Run `terraform init && terraform apply` in `envs/prod/cicd/` to create the IAM role
6. [ ] Create `production` GitHub Environment with required reviewer
7. [ ] Set `AWS_GITHUB_ACTIONS_TF_ROLE_ARN` and `TF_VAR_ALERT_EMAIL` GitHub secrets
8. [ ] Push to main, verify plan job runs and posts summary
9. [ ] Approve apply in GitHub UI, verify apply job completes successfully
