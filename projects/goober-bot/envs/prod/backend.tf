terraform {
  backend "s3" {
    bucket         = "terraform-state-533267126082-us-east-1-an"
    key            = "goober-bot/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
