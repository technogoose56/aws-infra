# Plan: Rename Terraform State S3 Bucket

## Goal

Replace the `goober-bot-terraform-state` S3 bucket with a new `terraform-state-533267126082-us-east-1-an` bucket that uses
project-specific subfolders, making the state storage appropriately named for infrastructure that
is not specific to goober-bot.

## Proposed Bucket Key Structure

```
terraform-state/
├── goober-bot/
│   └── prod/
│       └── terraform.tfstate        (was: prod/goober-bot/terraform.tfstate)
└── shared/
    └── cicd/
        └── prod/
            └── terraform.tfstate    (was: prod/cicd/terraform.tfstate)
```

## Affected Files

| File | Change Required |
|------|----------------|
| `projects/goober-bot/envs/prod/backend.tf` | Update `bucket` and `key` |
| `shared/cicd/envs/prod/backend.tf` | Update `bucket` and `key` |
| `shared/cicd/envs/prod/variables.tf` | Update default for `tf_state_bucket` |

The IAM module at `modules/terraform-cicd-iam/main.tf` references the bucket via `var.tf_state_bucket`
and requires no changes — the updated variable default handles it.

## Steps

### Phase 1 — Provision the new bucket

- [x] 1. ~~Create the `terraform-state-533267126082-us-east-1-an` S3 bucket in AWS with the same settings as
         `goober-bot-terraform-state` (versioning enabled, encryption enabled, block public access).
         Do this manually via the AWS Console or CLI since bootstrapping Terraform state in Terraform
         itself is a chicken-and-egg problem.~~ **Done — bucket `terraform-state-533267126082-us-east-1-an` created.**

### Phase 2 — Copy existing state files to the new bucket

- [ ] 2. Copy state files to the new key paths:
    ```bash
    # goober-bot project state
    aws s3 cp \
      s3://goober-bot-terraform-state/prod/goober-bot/terraform.tfstate \
      s3://terraform-state-533267126082-us-east-1-an/goober-bot/prod/terraform.tfstate

    # Shared CI/CD state
    aws s3 cp \
      s3://goober-bot-terraform-state/prod/cicd/terraform.tfstate \
      s3://terraform-state-533267126082-us-east-1-an/shared/cicd/prod/terraform.tfstate
    ```
- [ ] 3. Verify the copies landed correctly:
    ```bash
    aws s3 ls s3://terraform-state-533267126082-us-east-1-an/ --recursive
    ```

### Phase 3 — Update IAM permissions FIRST (while still on the old backend)

The IAM role must be granted access to the new bucket **before** any `terraform init` migration
is attempted. The role has no permissions on the new bucket yet, which causes a 403 on init.

- [ ] 4. Update only the variable default in `shared/cicd/envs/prod/variables.tf` — leave
         `backend.tf` pointing at the old bucket for now:
    ```hcl
    variable "tf_state_bucket" {
      default = "terraform-state-533267126082-us-east-1-an"
    }
    ```
- [ ] 5. Run `terraform init` in `shared/cicd/envs/prod/` (still uses old backend — no backend
         change yet, so no migration prompt):
    ```bash
    terraform init
    ```
- [ ] 6. Run `terraform apply` in `shared/cicd/envs/prod/`. This updates the IAM policy to
         grant the CI/CD role access to the new bucket:
    ```bash
    terraform apply
    ```
    Expect only IAM policy changes — verify the plan before confirming.

### Phase 4 — Migrate backends to the new bucket

Now that IAM permissions cover the new bucket, both backends can be migrated.

- [ ] 7. Update `shared/cicd/envs/prod/backend.tf`:
    ```hcl
    terraform {
      backend "s3" {
        bucket         = "terraform-state-533267126082-us-east-1-an"
        key            = "shared/cicd/prod/terraform.tfstate"
        region         = "us-east-1"
        use_lockfile   = true
        encrypt        = true
      }
    }
    ```
- [ ] 8. Run `terraform init` in `shared/cicd/envs/prod/` and confirm migration when prompted:
    ```bash
    terraform init
    ```
- [ ] 9. Update `projects/goober-bot/envs/prod/backend.tf`:
    ```hcl
    terraform {
      backend "s3" {
        bucket         = "terraform-state-533267126082-us-east-1-an"
        key            = "goober-bot/prod/terraform.tfstate"
        region         = "us-east-1"
        use_lockfile   = true
        encrypt        = true
      }
    }
    ```
- [ ] 10. Run `terraform init` in `projects/goober-bot/envs/prod/` and confirm migration when prompted:
    ```bash
    terraform init
    ```
- [ ] 11. Run `terraform plan` in both directories. Expect **no changes** — a diff here means
          the state is out of sync and must be investigated before proceeding.

### Phase 5 — Verify CI/CD pipeline

- [ ] 12. Trigger the `goober-bot-terraform.yml` GitHub Actions workflow manually and confirm
          the `terraform plan` step succeeds with no unexpected changes.

### Phase 6 — Decommission the old bucket

- [ ] 13. Once everything is verified, delete the old `goober-bot-terraform-state` bucket
          (empty it first, then delete). Keep it around for at least one CI/CD run cycle
          before deleting.

## Rollback

If anything goes wrong before Step 12, the old bucket and its state files are still intact.
Simply revert the `backend.tf` changes and re-run `terraform init` to switch back.
