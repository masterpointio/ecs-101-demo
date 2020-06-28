# fargate.tf

variable "stage" {
  type        = string
  description = "The environment that this infrastrcuture is being deployed to e.g. dev, stage, or prod"
}

variable "namespace" {
  type        = string
  description = "Namespace, which could be your organization name or abbreviation, e.g. 'eg' or 'cp'"
}

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC that this Fargate project "
}

## ALB Configuration

variable "certificate_arn" {
  type        = string
  description = "The ARN of the certificate to associate with the HTTPS listener on the ALB."
}

variable "subnet_ids" {
  type        = list(string)
  description = "A list of subnet IDs to associate with ALB"
}

variable "idle_timeout" {
  default     = 30
  type        = number
  description = "The time in seconds that the connection is allowed to be idle."
}

variable "deletion_protection_enabled" {
  default     = false
  type        = bool
  description = "A boolean flag to enable/disable deletion protection for ALB"
}

variable "deregistration_delay" {
  type        = number
  description = "The amount of time to wait in seconds before changing the state of a deregistering target to unused"
  default     = 15
}

## Healthcheck Settings

variable "healthcheck_path" {
  default     = "/"
  type        = string
  description = "The destination for the health check request"
}

variable "healthcheck_timeout" {
  default     = 15
  type        = number
  description = "The amount of time to wait in seconds before failing a health check request"
}

variable "healthcheck_healthy_threshold" {
  default     = 2
  type        = number
  description = "The number of consecutive health checks successes required before considering an unhealthy target healthy"
}

variable "healthcheck_unhealthy_threshold" {
  default     = 5
  type        = number
  description = "The number of consecutive health check failures required before considering the target unhealthy"
}

variable "healthcheck_interval" {
  default     = 30
  type        = number
  description = "The duration in seconds in between health checks"
}

variable "healthcheck_matcher" {
  default     = "200-399"
  type        = string
  description = "The HTTP response codes to indicate a healthy check"
}
