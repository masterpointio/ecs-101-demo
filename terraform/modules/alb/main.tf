# alb.tf

module "label" {
  source    = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  namespace = var.namespace
  stage     = var.stage
  name      = "alb"
}

module "backend_target_group_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  namespace  = var.namespace
  stage      = var.stage
  name       = "backend"
  attributes = ["target-group"]
}

module "frontend_target_group_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  namespace  = var.namespace
  stage      = var.stage
  name       = "frontend"
  attributes = ["target-group"]
}

## Security Group
##################

resource "aws_security_group" "this" {
  description = "Controls access to the ALB (HTTP/HTTPS)"
  vpc_id      = var.vpc_id
  name        = module.label.id
  tags        = module.label.tags
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = "0"
  to_port           = "0"
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.this.id
}

resource "aws_security_group_rule" "http_ingress" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  prefix_list_ids   = []
  security_group_id = aws_security_group.this.id
}

resource "aws_security_group_rule" "https_ingress" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  prefix_list_ids   = []
  security_group_id = aws_security_group.this.id
}

## Application Load Balancer
#############################

resource "aws_lb" "this" {
  name               = module.label.id
  tags               = module.label.tags
  load_balancer_type = "application"

  security_groups                  = [aws_security_group.this.id]
  subnets                          = var.subnet_ids
  enable_cross_zone_load_balancing = true
  enable_http2                     = true
  idle_timeout                     = var.idle_timeout
  ip_address_type                  = "ipv4"
  enable_deletion_protection       = var.deletion_protection_enabled
}

## Target Groups
#################

resource "aws_lb_target_group" "frontend" {
  name                 = module.frontend_target_group_label.id
  port                 = "80"
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay
  tags                 = module.frontend_target_group_label.tags

  health_check {
    path                = var.healthcheck_path
    timeout             = var.healthcheck_timeout
    healthy_threshold   = var.healthcheck_healthy_threshold
    unhealthy_threshold = var.healthcheck_unhealthy_threshold
    interval            = var.healthcheck_interval
    matcher             = var.healthcheck_matcher
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "backend" {
  name                 = module.backend_target_group_label.id
  port                 = "80"
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay
  tags                 = module.backend_target_group_label.tags

  health_check {
    path                = "/api"
    timeout             = var.healthcheck_timeout
    healthy_threshold   = var.healthcheck_healthy_threshold
    unhealthy_threshold = var.healthcheck_unhealthy_threshold
    interval            = var.healthcheck_interval
    matcher             = var.healthcheck_matcher
  }

  lifecycle {
    create_before_destroy = true
  }
}


## Listeners + Listener Rules
##############################

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

## Default forwards to Frontend
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "backend" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api*"]
    }
  }
}
