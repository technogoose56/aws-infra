# aws-infra
This repo contains the infrastructure-as-code and any other configuration necessary for maintaining my AWS environment.

## goober-bot (prod)

Deploys [goober-bot](https://github.com/technogoose56/goober-bot) — a Go Telegram bot — on an EC2 Spot t4g.nano instance (~$1.82/mo).

```mermaid
graph TB
    subgraph internet[" "]
        user([Telegram User])
        tg[Telegram API]
        noaa[NOAA API]
    end

    subgraph aws[AWS us-east-1]
        subgraph vpc["VPC (10.0.0.0/24)"]
            igw[Internet Gateway]
            subgraph subnet["Public Subnet (10.0.0.0/26)"]
                asg["Auto Scaling Group (min/max/desired = 1)"]
                subgraph ec2["EC2 Spot t4g.nano"]
                    bot["goober-bot (Docker)"]
                end
            end
        end

        ebs[("EBS 1 GiB gp3\n/data — SQLite")]
        ecr["ECR\ngoober-bot:latest (ARM64)"]
        ssm["SSM Parameter Store\nBot Token · Allowed User IDs"]
        logs["CloudWatch Logs\n/goober-bot/application"]
        alarm["CloudWatch Alarm\nGroupInServiceInstances < 1"]
        sns[SNS Topic]
        budget["Budget Alert - 5 USD/mo"]
        email([Email Alerts])
    end

    user <-->|messages| tg
    tg <-->|long-polling HTTPS| bot
    bot -->|weather queries| noaa
    bot -->|app logs| logs
    bot <-->|SQLite persistence| ebs
    ec2 -->|pulls image on boot| ecr
    ec2 -->|reads secrets on boot| ssm
    asg -->|launches/replaces| ec2
    igw --- subnet
    alarm --> sns
    budget --> email
    sns --> email
```