terraform {
  required_version = ">= 0.12.25"

  required_providers {
    aws   = "~> 2.0"
    local = "~> 1.2"
    null  = "~> 2.0"
  }

  backend "s3" {
    region         = "us-west-2"
    bucket         = "mp-ecs101-terraform-state"
    key            = "terraform.tfstate"
    dynamodb_table = "mp-ecs101-terraform-state-lock"
    encrypt        = "true"
  }
}
