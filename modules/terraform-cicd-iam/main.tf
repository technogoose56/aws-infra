# ============================================================
# Terraform CI/CD IAM — Role for GitHub Actions plan/apply
# ============================================================
# Allows the aws-infra repo's GitHub Actions workflow to
# authenticate via OIDC and run terraform plan (on push to
# main) and terraform apply (after environment approval).
#
# Reuses the existing OIDC provider — passed in as a variable
# to avoid creating a duplicate provider resource.
# ============================================================

resource "aws_iam_role" "terraform_cicd" {
  name = "terraform-cicd"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              # plan job: runs on push to main
              "repo:${var.github_repo}:ref:refs/heads/main",
              # apply job: runs after environment approval
              "repo:${var.github_repo}:environment:production",
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name = "terraform-cicd"
  }
}

# ============================================================
# Terraform State Backend
# ============================================================

resource "aws_iam_role_policy" "tf_state" {
  name   = "terraform-cicd-state"
  role   = aws_iam_role.terraform_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "arn:aws:s3:::${var.tf_state_bucket}/*"
      },
      {
        Sid      = "StateBucketList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${var.tf_state_bucket}"
      },
      {
        Sid    = "StateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
        ]
        Resource = "arn:aws:dynamodb:*:*:table/${var.tf_lock_table}"
      },
    ]
  })
}

# ============================================================
# EC2 + Networking (VPC, Subnets, ASG, Launch Template, EBS)
# ============================================================

resource "aws_iam_role_policy" "ec2" {
  name   = "terraform-cicd-ec2"
  role   = aws_iam_role.terraform_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:DescribeVpcs",
          "ec2:ModifyVpcAttribute",
          "ec2:DescribeVpcAttribute",
          "ec2:CreateSubnet",
          "ec2:DeleteSubnet",
          "ec2:DescribeSubnets",
          "ec2:ModifySubnetAttribute",
          "ec2:CreateInternetGateway",
          "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:DescribeInternetGateways",
          "ec2:CreateRouteTable",
          "ec2:DeleteRouteTable",
          "ec2:DescribeRouteTables",
          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
          "ec2:CreateLaunchTemplate",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:ModifyLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion",
          "ec2:DeleteLaunchTemplateVersions",
          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:DescribeVolumes",
          "ec2:ModifyVolume",
          "ec2:DescribeVolumeAttribute",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeTags",
          "ec2:CreateTags",
          "ec2:DeleteTags",
        ]
        Resource = "*"
      },
      {
        Sid    = "AutoScaling"
        Effect = "Allow"
        Action = [
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeScheduledActions",
          "autoscaling:DescribeLifecycleHooks",
          "autoscaling:DescribeNotificationConfigurations",
          "autoscaling:DescribePolicies",
          "autoscaling:EnableMetricsCollection",
          "autoscaling:DisableMetricsCollection",
          "autoscaling:PutScalingPolicy",
          "autoscaling:DeletePolicy",
          "autoscaling:StartInstanceRefresh",
          "autoscaling:CancelInstanceRefresh",
          "autoscaling:DescribeInstanceRefreshes",
        ]
        Resource = "*"
      },
    ]
  })
}

# ============================================================
# ECR
# ============================================================

resource "aws_iam_role_policy" "ecr" {
  name   = "terraform-cicd-ecr"
  role   = aws_iam_role.terraform_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRManage"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:DeleteRepository",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy",
          "ecr:ListTagsForResource",
          "ecr:TagResource",
          "ecr:UntagResource",
          "ecr:PutLifecyclePolicy",
          "ecr:GetLifecyclePolicy",
          "ecr:DeleteLifecyclePolicy",
          "ecr:PutImageScanningConfiguration",
          "ecr:PutImageTagMutability",
          "ecr:DescribeRegistry",
          "ecr:GetRegistryPolicy",
        ]
        Resource = "*"
      },
    ]
  })
}

# ============================================================
# IAM (roles, instance profiles, OIDC provider)
# ============================================================

resource "aws_iam_role_policy" "iam" {
  name   = "terraform-cicd-iam"
  role   = aws_iam_role.terraform_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAMRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",
          "iam:ListRoleTags",
          "iam:GetRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:PassRole",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfilesForRole",
        ]
        Resource = "*"
      },
      {
        Sid    = "OIDCProvider"
        Effect = "Allow"
        Action = [
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviders",
        ]
        Resource = "arn:aws:iam::*:oidc-provider/token.actions.githubusercontent.com"
      },
    ]
  })
}

# ============================================================
# CloudWatch Logs + Alarms
# ============================================================

resource "aws_iam_role_policy" "cloudwatch" {
  name   = "terraform-cicd-cloudwatch"
  role   = aws_iam_role.terraform_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:ListTagsForResource",
          "logs:TagResource",
          "logs:UntagResource",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
        ]
        Resource = "arn:aws:logs:*:*:log-group:*"
      },
      {
        Sid    = "Alarms"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListTagsForResource",
          "cloudwatch:TagResource",
          "cloudwatch:UntagResource",
        ]
        Resource = "arn:aws:cloudwatch:*:*:alarm:*"
      },
    ]
  })
}

# ============================================================
# SNS
# ============================================================

resource "aws_iam_role_policy" "sns" {
  name   = "terraform-cicd-sns"
  role   = aws_iam_role.terraform_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SNS"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic",
          "sns:DeleteTopic",
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:Subscribe",
          "sns:Unsubscribe",
          "sns:GetSubscriptionAttributes",
          "sns:ListSubscriptionsByTopic",
          "sns:ListTagsForResource",
          "sns:TagResource",
          "sns:UntagResource",
        ]
        Resource = "arn:aws:sns:*:*:*"
      },
    ]
  })
}

# ============================================================
# Budgets (account-level — no ARN scoping available)
# ============================================================

resource "aws_iam_role_policy" "budgets" {
  name   = "terraform-cicd-budgets"
  role   = aws_iam_role.terraform_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Budgets"
        Effect = "Allow"
        Action = [
          "budgets:CreateBudget",
          "budgets:ModifyBudget",
          "budgets:DeleteBudget",
          "budgets:ViewBudget",
          "budgets:ListTagsForResource",
          "budgets:TagResource",
          "budgets:UntagResource",
          "budgets:DescribeBudgetActionsForBudget",
          "budgets:CreateBudgetAction",
          "budgets:DeleteBudgetAction",
        ]
        Resource = "*"
      },
    ]
  })
}

# ============================================================
# SSM (AMI lookup via public parameter store)
# ============================================================

resource "aws_iam_role_policy" "ssm" {
  name   = "terraform-cicd-ssm"
  role   = aws_iam_role.terraform_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMPublicParameters"
        Effect = "Allow"
        Action = "ssm:GetParameter"
        # Public SSM parameters (e.g. latest AMI IDs) live under /aws/service/
        Resource = "arn:aws:ssm:*::parameter/aws/service/*"
      },
    ]
  })
}
