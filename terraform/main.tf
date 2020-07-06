# main.tf

module "terraform_state_backend" {
  source    = "git::https://github.com/cloudposse/terraform-aws-tfstate-backend.git?ref=write-if-doesnt-exist"
  namespace = var.namespace
  stage     = var.stage
  region    = var.region
  name      = "terraform"

  terraform_backend_config_file_path = "."
  terraform_backend_config_file_name = "backend.tf"
}

module "base_label" {
  source    = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  namespace = var.namespace
  stage     = var.stage
  name      = "app"
}

module "backend_label" {
  source    = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  namespace = var.namespace
  stage     = var.stage
  name      = "backend"
}

module "frontend_label" {
  source    = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  namespace = var.namespace
  stage     = var.stage
  name      = "frontend"
}

module "backend_ec2_label" {
  source    = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  namespace = var.namespace
  stage     = var.stage
  name      = "backend-ec2"
  additional_tag_map = {
    propagate_at_launch = "true"
  }
}

module "ecs_instance_role_label" {
  source    = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  namespace = var.namespace
  stage     = var.stage
  name      = "ecs"
}

module "db_ec2_label" {
  source    = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  namespace = var.namespace
  stage     = var.stage
  name      = "db-ec2"
  additional_tag_map = {
    propagate_at_launch = "true"
  }
}

module "backend_cp_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  namespace  = var.namespace
  stage      = var.stage
  attributes = ["1"]
  name       = "backend-capacity-provider"
  additional_tag_map = {
    propagate_at_launch = "true"
  }
}

locals {
  healthcheck = {
    command     = ["CMD-SHELL", "echo 'dummy healthcheck' || exit 1"]
    retries     = 3
    timeout     = 20
    interval    = 30
    startPeriod = 30
  }

  ssm_params = [
    { name = "/backend/node_env", value = "prod", type = "String", overwrite = true },
    { name = "/frontend/node_env", value = "prod", type = "String", overwrite = true },
  ]

  user_data = <<EOT
#!/bin/bash
echo ECS_CLUSTER=${module.base_label.id} >> /etc/ecs/ecs.config
sudo yum update -y ecs-init
sudo start ecs

# Install ssm-agent for access to ECS instances.
sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent
EOT

}

## Network
###########

module "vpc" {
  source     = "git::https://github.com/cloudposse/terraform-aws-vpc.git?ref=tags/0.13.0"
  namespace  = var.namespace
  stage      = var.stage
  name       = "vpc"
  cidr_block = "10.0.0.0/16"

  enable_default_security_group_with_custom_rules = true
}

module "subnets" {
  source               = "git::https://github.com/cloudposse/terraform-aws-dynamic-subnets.git?ref=tags/0.19.0"
  namespace            = var.namespace
  stage                = var.stage
  availability_zones   = var.availability_zones
  vpc_id               = module.vpc.vpc_id
  igw_id               = module.vpc.igw_id
  cidr_block           = module.vpc.vpc_cidr_block
  nat_gateway_enabled  = false
  nat_instance_enabled = true
}

## SSM Params
##############

module "ssm_params" {
  source          = "git::https://github.com/cloudposse/terraform-aws-ssm-parameter-store?ref=tags/0.2.0"
  parameter_write = local.ssm_params
  tags            = module.base_label.tags
}

## Certificate + DNS
#####################

resource "aws_acm_certificate" "this" {
  domain_name       = "ecs101.${var.domain}"
  validation_method = "DNS"
  tags              = module.base_label.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  count           = length(aws_acm_certificate.this.domain_validation_options)
  zone_id         = data.aws_route53_zone.this.zone_id
  name            = aws_acm_certificate.this.domain_validation_options[count.index].resource_record_name
  type            = aws_acm_certificate.this.domain_validation_options[count.index].resource_record_type
  ttl             = "300"
  records         = [aws_acm_certificate.this.domain_validation_options[count.index].resource_record_value]
  allow_overwrite = true

  depends_on = [aws_acm_certificate.this]
}

resource "aws_route53_record" "this" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "ecs101.${var.domain}"
  type    = "CNAME"
  ttl     = "300"
  records = [module.alb.dns_name]
}

## ALB
#######

module "alb" {
  source = "./modules/alb"

  namespace       = var.namespace
  stage           = var.stage
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.subnets.public_subnet_ids
  certificate_arn = aws_acm_certificate.this.arn
}

## ECR
#######

resource "aws_ecr_repository" "backend" {
  name = module.backend_label.id
  tags = module.backend_label.tags
}

resource "aws_ecr_repository" "frontend" {
  name = module.frontend_label.id
  tags = module.frontend_label.tags
}

## ECS
#######

resource "aws_ecs_cluster" "this" {
  name = module.base_label.id
  tags = module.base_label.tags

  capacity_providers = [
    "FARGATE",
    "FARGATE_SPOT",
    module.backend_cp_label.id
  ]

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "null_resource" "enable_long_ecs_resource_ids_for_region" {
  provisioner "local-exec" {
    command = <<EOF
      aws ecs --region ${var.region} put-account-setting-default --name serviceLongArnFormat --value enabled
      aws ecs --region ${var.region} put-account-setting-default --name taskLongArnFormat --value enabled
      aws ecs --region ${var.region} put-account-setting-default --name containerInstanceLongArnFormat --value enabled
EOF
  }
}

## Custom Capacity Provider
############################

resource "aws_launch_template" "this" {
  name          = module.backend_ec2_label.id
  image_id      = var.ami != "" ? var.ami : data.aws_ami.ecs_optimized.id
  key_name      = var.key_pair_name != "" ? var.key_pair_name : null
  instance_type = var.instance_type
  user_data     = base64encode(local.user_data)

  iam_instance_profile {
    name = module.ecs_instance_role_label.id
  }

  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = [module.backend_service.service_security_group_id]
  }

  tag_specifications {
    resource_type = "instance"
    tags          = module.backend_ec2_label.tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = module.backend_ec2_label.tags
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "this" {
  name = "${module.backend_cp_label.id}-asg"
  tags = module.backend_ec2_label.tags_as_list_of_maps

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  max_size         = 3
  min_size         = 1
  desired_capacity = 1

  vpc_zone_identifier = module.subnets.private_subnet_ids

  default_cooldown          = 180
  health_check_grace_period = 180
  health_check_type         = "EC2"

  termination_policies = [
    "OldestLaunchConfiguration",
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_capacity_provider" "this" {
  name = module.backend_cp_label.id
  tags = module.backend_cp_label.tags

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.this.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 100
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}

## Container Defs
##################

module "backend_def" {
  source           = "git::https://github.com/cloudposse/terraform-aws-ecs-container-definition.git?ref=tags/0.33.0"
  container_name   = "backend"
  container_image  = "${aws_ecr_repository.backend.repository_url}:latest"
  container_memory = "512"
  container_cpu    = "256"
  healthcheck      = local.healthcheck

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-create-group  = true
      awslogs-group         = "/ecs/ecs101/"
      awslogs-region        = var.region,
      awslogs-stream-prefix = "backend"
    }
    secretOptions = null
  }

  port_mappings = [{
    containerPort = 3000
    hostPort      = 3000
    protocol      = "tcp"
  }]
}

module "frontend_def" {
  source           = "git::https://github.com/cloudposse/terraform-aws-ecs-container-definition.git?ref=tags/0.33.0"
  container_name   = "frontend"
  container_image  = "${aws_ecr_repository.frontend.repository_url}:latest"
  container_memory = "512"
  container_cpu    = "256"
  healthcheck      = local.healthcheck

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-create-group  = true
      awslogs-group         = "/ecs/ecs101/"
      awslogs-region        = var.region,
      awslogs-stream-prefix = "frontend"
    }
    secretOptions = null
  }

  port_mappings = [{
    containerPort = 5000
    hostPort      = 5000
    protocol      = "tcp"
  }]
}

module "database_def" {
  source           = "git::https://github.com/cloudposse/terraform-aws-ecs-container-definition.git?ref=tags/0.33.0"
  container_name   = "database"
  container_image  = "mongo:4.2.0"
  container_memory = "512"
  container_cpu    = "256"
  healthcheck      = local.healthcheck

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-create-group  = true
      awslogs-group         = "/ecs/ecs101/"
      awslogs-region        = var.region,
      awslogs-stream-prefix = "database"
    }
    secretOptions = null
  }

  port_mappings = [{
    containerPort = 27017
    hostPort      = 27017
    protocol      = "tcp"
  }]
}

## Services
############

module "backend_service" {
  source                         = "git::https://github.com/cloudposse/terraform-aws-ecs-alb-service-task.git?ref=tags/0.26.0"
  namespace                      = var.namespace
  stage                          = var.stage
  name                           = "backend"
  vpc_id                         = module.vpc.vpc_id
  container_definition_json      = module.backend_def.json
  ecs_cluster_arn                = aws_ecs_cluster.this.arn
  launch_type                    = "EC2"
  subnet_ids                     = module.subnets.private_subnet_ids
  network_mode                   = "awsvpc"
  ignore_changes_task_definition = true
  assign_public_ip               = false
  propagate_tags                 = "SERVICE"
  desired_count                  = 1
  task_memory                    = "512"
  task_cpu                       = "256"

  ecs_load_balancers = [{
    container_name   = "backend"
    container_port   = 3000
    elb_name         = null
    target_group_arn = module.alb.backend_target_group_arn
  }]

  capacity_provider_strategies = [{
    capacity_provider = module.backend_cp_label.id
    weight            = 100
    base              = 1
  }]
}

module "frontend_service" {
  source                         = "git::https://github.com/cloudposse/terraform-aws-ecs-alb-service-task.git?ref=tags/0.26.0"
  namespace                      = var.namespace
  stage                          = var.stage
  name                           = "frontend"
  vpc_id                         = module.vpc.vpc_id
  container_definition_json      = module.frontend_def.json
  ecs_cluster_arn                = aws_ecs_cluster.this.arn
  launch_type                    = "FARGATE"
  platform_version               = "1.4.0"
  subnet_ids                     = module.subnets.private_subnet_ids
  network_mode                   = "awsvpc"
  ignore_changes_task_definition = true
  assign_public_ip               = false
  propagate_tags                 = "SERVICE"
  desired_count                  = 1
  task_memory                    = "512"
  task_cpu                       = "256"

  ecs_load_balancers = [{
    container_name   = "frontend"
    container_port   = 5000
    elb_name         = null
    target_group_arn = module.alb.frontend_target_group_arn
  }]

  capacity_provider_strategies = [{
    capacity_provider = "FARGATE"
    weight            = 10
    base              = 1
    }, {
    capacity_provider = "FARGATE_SPOT"
    weight            = 90
    base              = 0
  }]
}

module "database_service" {
  source                         = "git::https://github.com/cloudposse/terraform-aws-ecs-alb-service-task.git?ref=tags/0.26.0"
  namespace                      = var.namespace
  stage                          = var.stage
  name                           = "database"
  vpc_id                         = module.vpc.vpc_id
  container_definition_json      = module.database_def.json
  ecs_cluster_arn                = aws_ecs_cluster.this.arn
  launch_type                    = "EC2"
  subnet_ids                     = module.subnets.private_subnet_ids
  network_mode                   = "awsvpc"
  ignore_changes_task_definition = true
  assign_public_ip               = false
  propagate_tags                 = "SERVICE"
  desired_count                  = 1
  task_memory                    = "512"
  task_cpu                       = "256"

  service_registries = [{
    registry_arn   = aws_service_discovery_service.this.arn
    container_name = null
    container_port = 0
    port           = 0
  }]

  service_placement_constraints = [{
    type       = "distinctInstance"
    expression = null
    }, {
    type       = "memberOf"
    expression = "attribute:ecs.instance-type =~ t2.*"
  }]
}

## Service Discovery
#####################

resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = "ecs101.local"
  description = "The service discovery namespace for ECS 101."
  vpc         = module.vpc.vpc_id
}

resource "aws_service_discovery_service" "this" {
  name = "ecs101-service"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.this.id
    routing_policy = "MULTIVALUE"
    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 3
  }
}

## DB Instance + SG
####################

resource "aws_security_group" "db" {
  name        = module.db_ec2_label.id
  description = "Security Group for the MongoDB EC2 Instance / ECS Tasks."
  vpc_id      = module.vpc.vpc_id
  tags        = module.db_ec2_label.tags
}

# TODO: Is this needed or does the ingress 27017 to DB service rule suffice?
resource "aws_security_group_rule" "backend_to_db_instance" {
  type                     = "ingress"
  from_port                = 27017
  to_port                  = 27017
  protocol                 = "tcp"
  source_security_group_id = module.backend_service.service_security_group_id
  security_group_id        = aws_security_group.db.id
}

resource "aws_security_group_rule" "db_all_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.db.id
}

resource "aws_instance" "this" {
  ami                         = var.db_ami != "" ? var.db_ami : data.aws_ami.ecs_optimized.id
  instance_type               = "t2.small"
  associate_public_ip_address = false
  subnet_id                   = module.subnets.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.db.id]
  iam_instance_profile        = module.ecs_instance_role_label.id
  key_name                    = var.key_pair_name
  tags                        = module.db_ec2_label.tags

  user_data = base64encode(local.user_data)
}

## Extra SG Rules
##################

resource "aws_security_group_rule" "backend_to_db" {
  type                     = "ingress"
  from_port                = 27017
  to_port                  = 27017
  protocol                 = "tcp"
  source_security_group_id = module.backend_service.service_security_group_id
  security_group_id        = module.database_service.service_security_group_id
}

resource "aws_security_group_rule" "alb_to_backend" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = module.alb.security_group_id
  security_group_id        = module.backend_service.service_security_group_id
}

resource "aws_security_group_rule" "alb_to_frontend" {
  type                     = "ingress"
  from_port                = 5000
  to_port                  = 5000
  protocol                 = "tcp"
  source_security_group_id = module.alb.security_group_id
  security_group_id        = module.frontend_service.service_security_group_id
}

## Extra IAM
#############

data "aws_iam_policy_document" "task_read_ssm_params" {

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:ListAliases",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:Describe*",
      "ssm:Get*",
      "ssm:List*"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "frontend_read_ssm_params" {
  name   = "AllowFrontendAppToReadSSMParams"
  role   = module.frontend_service.task_role_name
  policy = data.aws_iam_policy_document.task_read_ssm_params.json
}

resource "aws_iam_role_policy" "backend_read_ssm_params" {
  name   = "AllowBackendAppToReadSSMParams"
  role   = module.backend_service.task_role_name
  policy = data.aws_iam_policy_document.task_read_ssm_params.json
}

## ECS Instance Profile
########################

data "aws_iam_policy_document" "ecs_assume_role" {

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_instance_role" {
  name               = module.ecs_instance_role_label.id
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = module.ecs_instance_role_label.tags
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ssm_managed" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = module.ecs_instance_role_label.id
  role = aws_iam_role.ecs_instance_role.name
}
