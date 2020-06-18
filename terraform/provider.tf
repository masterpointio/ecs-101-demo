# provider.tf

provider "aws" {
  region = var.region
}

terraform {
  required_version = "~> 0.12.0"

  required_providers {
    aws   = "~> 2.61"
    local = "~> 1.2"
    null  = "~> 2.0"
  }
}
