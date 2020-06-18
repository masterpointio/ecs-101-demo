# main.tf

module "terraform_state_backend" {
  source    = "git::https://github.com/cloudposse/terraform-aws-tfstate-backend.git?ref=0.17.0"
  namespace = var.namespace
  stage     = var.stage
  region    = var.region
  name      = "terraform"

  terraform_backend_config_file_path = "."
  terraform_backend_config_file_name = "backend.tf"
}