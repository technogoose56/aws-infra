# Plan: Restructure Project Manifests

## Goal

Reorganize the repository so that infrastructure manifests specific to a project (e.g. goober-bot) live inside that project's own folder. Shared Terraform modules remain generic and project-agnostic under `modules/`.

---

## Current State

```
aws-infra/
├── modules/
│   ├── compute/
│   ├── ecr/
│   ├── github-actions-iam/
│   ├── monitoring/
│   ├── terraform-cicd-iam/
│   └── vpc/
├── envs/
│   └── prod/
│       ├── goober-bot/         # goober-bot infra (mixed in with cicd)
│       └── cicd/               # Terraform CI/CD IAM + OIDC
├── agents/
│   └── plans/
│       ├── goober-bot-deployment/PLAN.md
│       └── terraform-cicd/PLAN.md
└── .github/
    └── workflows/
        └── terraform.yml
```

**Problems with current layout:**
- `envs/prod/goober-bot/` and `envs/prod/cicd/` are peers, making it unclear which env configs belong to which project.
- The `agents/plans/goober-bot-deployment/PLAN.md` plan for goober-bot lives at the top level alongside the CI/CD plan, not co-located with its infrastructure.
- Adding a second project would produce more sibling folders in `envs/prod/`, making it hard to reason about ownership.

---

## Proposed Structure

```
aws-infra/
├── modules/                            # Generic, reusable Terraform modules
│   ├── compute/
│   ├── ecr/
│   ├── github-actions-iam/
│   ├── monitoring/
│   ├── terraform-cicd-iam/
│   └── vpc/
│
├── projects/                           # One subfolder per deployed project
│   └── goober-bot/
│       ├── envs/
│       │   └── prod/                   # Formerly envs/prod/goober-bot/
│       │       ├── main.tf
│       │       ├── variables.tf
│       │       ├── outputs.tf
│       │       ├── providers.tf
│       │       └── backend.tf
│       └── plans/
│           └── PLAN.md                 # Formerly agents/plans/goober-bot-deployment/PLAN.md
│
├── shared/                             # Infrastructure not owned by a single project
│   └── cicd/
│       ├── envs/
│       │   └── prod/                   # Formerly envs/prod/cicd/
│       │       ├── main.tf
│       │       ├── variables.tf
│       │       ├── outputs.tf
│       │       ├── providers.tf
│       │       └── backend.tf
│       └── plans/
│           └── PLAN.md                 # Formerly agents/plans/terraform-cicd/PLAN.md
│
├── agents/
│   └── plans/                          # Reserved for cross-cutting / repo-level plans (e.g. this one)
│
└── .github/
    └── workflows/
        └── terraform.yml
```

### Design Decisions

| Decision | Choice | Reason |
|---|---|---|
| Top-level container for projects | `projects/` | Clearly signals "each subfolder is a deployed app" |
| Shared infra (CI/CD) | `shared/` | Distinct from per-project folders; not tied to one app |
| Plans placement | Co-located with project (`projects/<name>/plans/`) | Plans document the infra in the same folder; easier to find and maintain |
| `agents/plans/` | Kept for repo-level plans only | Cross-cutting plans (like this one) don't belong inside a single project |
| `modules/` | Unchanged | All modules are already written generically via variables; no restructuring needed |

---

## Changes Required

### 1. Move goober-bot env config

```
envs/prod/goober-bot/  →  projects/goober-bot/envs/prod/
```

- No content changes needed; only the directory path changes.
- Update `backend.tf` if the S3 key embeds a relative path assumption (verify).
- Update module source paths in `main.tf`:
  - `"../../../modules/vpc"` → `"../../../../modules/vpc"`
  - `"../../../modules/ecr"` → `"../../../../modules/ecr"`
  - `"../../../modules/github-actions-iam"` → `"../../../../modules/github-actions-iam"`
  - `"../../../modules/compute"` → `"../../../../modules/compute"`
  - `"../../../modules/monitoring"` → `"../../../../modules/monitoring"`

### 2. Move CI/CD env config

```
envs/prod/cicd/  →  shared/cicd/envs/prod/
```

- Update module source paths in `main.tf`:
  - `"../../../modules/terraform-cicd-iam"` → `"../../../../modules/terraform-cicd-iam"`

### 3. Move goober-bot plan

```
agents/plans/goober-bot-deployment/PLAN.md  →  projects/goober-bot/plans/PLAN.md
```

### 4. Move terraform-cicd plan

```
agents/plans/terraform-cicd/PLAN.md  →  shared/cicd/plans/PLAN.md
```

### 5. Update GitHub Actions workflow

`terraform.yml` references working directories for `terraform init/plan/apply`. Update both working directory paths:
- `envs/prod/goober-bot` → `projects/goober-bot/envs/prod`
- `envs/prod/cicd` → `shared/cicd/envs/prod`

### 6. Remove empty directories

After moving files, delete:
- `envs/` (now empty)
- `agents/plans/goober-bot-deployment/`
- `agents/plans/terraform-cicd/`

---

## Implementation Steps

- [x] **Step 1** — Create new directory scaffolding (`projects/goober-bot/envs/prod/`, `projects/goober-bot/plans/`, `shared/cicd/envs/prod/`, `shared/cicd/plans/`)
- [x] **Step 2** — Move goober-bot env files and update module source paths and relative depth
- [x] **Step 3** — Move CI/CD env files and update module source paths
- [x] **Step 4** — Move plan documents to their new co-located paths
- [x] **Step 5** — Update `.github/workflows/terraform.yml` working directory references
- [x] **Step 6** — Delete now-empty directories (`envs/`, old plan directories)
- [ ] **Step 7** — Run `terraform init` in both new env paths locally to validate module resolution
- [ ] **Step 8** — Open PR, verify GitHub Actions workflow runs cleanly against new paths

---

## Risks & Notes

- **Terraform state is unaffected.** State lives in S3 and is keyed by the `backend.tf` key string, not the local directory path. Moving files does not migrate or destroy state.
- **`terraform init` must be re-run** in both new env directories before plan/apply since the `.terraform/` lock file and provider cache are local to the directory.
- **GitHub Actions working directories** must be updated before merging, or CI will fail to find the Terraform configs.
- **No module content changes needed.** All modules accept project-specific values via variables; they are already generic.
