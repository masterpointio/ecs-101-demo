# variables.tf

variable "namespace" {
  type        = string
  description = "Namespace, which could be your organization name or abbreviation, e.g. 'eg' or 'cp'"
}

variable "stage" {
  type        = string
  default     = "ecs101"
  description = "Stage, e.g. 'prod', 'staging', 'dev', OR 'source', 'build', 'test', 'deploy', 'release'"
}

variable "region" {
  type        = string
  description = "The region that all AWS resources are deployed to."
}

variable "availability_zones" {
  type        = list(string)
  description = "List of Availability Zones where resources will be created"
}

variable "domain" {
  type        = string
  description = "The root domain to host DNS records on. Requires a hosted zone is already created for this domain in the account."
}

## EC2 Capacity Provider
#########################

variable "instance_type" {
  default     = "t3.micro"
  type        = string
  description = "The instance type to use for the Backend EC2 instances."
}

variable "ami" {
  default     = ""
  type        = string
  description = "The AMI to use for the Backend EC2 instances. If not provided, the latest ECS Optimized AMI will be used. Note: This will update periodically as AWS releases updates to that AMI. Pin to a specific AMI if you would like to avoid these updates."
}

variable "key_pair_name" {
  default     = ""
  type        = string
  description = "The name of the key-pair to associate with the Backend EC2 instances."
}
