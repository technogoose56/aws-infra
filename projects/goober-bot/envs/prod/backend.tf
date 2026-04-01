terraform {
  backend "s3" {
    bucket         = "goober-bot-terraform-state"
    key            = "prod/goober-bot/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
