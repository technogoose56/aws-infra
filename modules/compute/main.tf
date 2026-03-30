# ============================================================
# Compute Module — EC2 Spot via Auto Scaling Group
# ============================================================

locals {
  data_volume_tag = "${var.project_name}-data"
}

# --- Data Sources ---

# Look up the latest Amazon Linux 2023 ARM64 AMI via SSM parameter
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_caller_identity" "current" {}

# --- Persistent Data Volume (survives instance replacements) ---

resource "aws_ebs_volume" "data" {
  availability_zone = var.subnet_az
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = local.data_volume_tag
  }
}

# --- IAM Role for EC2 Instances ---

resource "aws_iam_role" "instance" {
  name_prefix = "${var.project_name}-instance-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-instance-role"
  }
}

# ECR pull permissions
resource "aws_iam_role_policy" "ecr_pull" {
  name_prefix = "${var.project_name}-ecr-pull-"
  role        = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = var.ecr_repo_arn
      }
    ]
  })
}

# SSM Parameter Store read permissions
resource "aws_iam_role_policy" "ssm_read" {
  name_prefix = "${var.project_name}-ssm-read-"
  role        = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.bot_token_ssm_name}",
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.allowed_user_ids_ssm_name}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# EBS volume attach permissions
resource "aws_iam_role_policy" "ebs_attach" {
  name_prefix = "${var.project_name}-ebs-attach-"
  role        = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:DescribeVolumes"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Logs permissions
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name_prefix = "${var.project_name}-cw-logs-"
  role        = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${var.log_group_name}:*"
      }
    ]
  })
}

# STS permissions (needed by user data to get account ID)
resource "aws_iam_role_policy" "sts_identity" {
  name_prefix = "${var.project_name}-sts-"
  role        = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bot" {
  name_prefix = "${var.project_name}-"
  role        = aws_iam_role.instance.name
}

# --- Launch Template ---

resource "aws_launch_template" "bot" {
  name_prefix   = "${var.project_name}-"
  image_id      = data.aws_ssm_parameter.al2023_arm64.value
  instance_type = var.instance_type

  # Use standard credit mode to avoid surprise charges on Spot
  credit_specification {
    cpu_credits = "standard"
  }

  # IAM instance profile
  iam_instance_profile {
    arn = aws_iam_instance_profile.bot.arn
  }

  # Network — public subnet, auto-assign public IP
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = var.security_group_ids
    delete_on_termination       = true
  }

  # Root volume
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Require IMDSv2 (security best practice)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # User data script (templated)
  user_data = base64encode(templatefile(
    "${path.module}/user_data.sh.tpl",
    {
      region                    = var.aws_region
      project_name              = var.project_name
      ecr_repo_url              = var.ecr_repo_url
      bot_token_ssm_name        = var.bot_token_ssm_name
      allowed_user_ids_ssm_name = var.allowed_user_ids_ssm_name
      data_volume_tag           = local.data_volume_tag
      swap_size_mb              = var.swap_size_mb
      docker_memory_limit       = var.docker_memory_limit
      log_group_name            = var.log_group_name
    }
  ))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-${var.environment}"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.project_name}-root"
    }
  }

  tags = {
    Name = "${var.project_name}-launch-template"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Auto Scaling Group ---

resource "aws_autoscaling_group" "bot" {
  name_prefix         = "${var.project_name}-"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = [var.subnet_id]

  # Health check
  health_check_type         = "EC2"
  health_check_grace_period = var.health_check_grace_period

  # Capacity rebalance for proactive Spot replacement
  capacity_rebalance = true

  # Use mixed instances policy for Spot diversity
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.bot.id
        version            = "$Latest"
      }

      # Additional instance types for Spot fallback
      dynamic "override" {
        for_each = var.spot_instance_types
        content {
          instance_type = override.value
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "capacity-optimized"
    }
  }

  # Enable CloudWatch group metrics (required — not published by default)
  enabled_metrics = [
    "GroupInServiceInstances",
    "GroupDesiredCapacity",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupTotalInstances",
  ]
  metrics_granularity = "1Minute"

  # Allow ASG to replace instances cleanly
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
