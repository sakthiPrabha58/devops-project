variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "ecommerce"
}

variable "environment" {
  type    = string
  default = "devops"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "key_name" {
  description = "Existing EC2 key pair name."
  type        = string
}

variable "admin_cidr" {
  description = "Your public IP/CIDR for SSH and management access, e.g. 203.0.113.10/32."
  type        = string
}

variable "domain_name" {
  description = "Optional Route53 hosted zone domain. Leave empty to skip Route53 records."
  type        = string
  default     = "sjss-dev.shop"
}

variable "instance_type" {
  type    = string
  default = "m7i-flex.large"
}

variable "worker_instance_type" {
  type    = string
  default = "c7i-flex.large"
}

variable "rds_username" {
  type    = string
  default = "sakthi58"
}

variable "rds_password" {
  description = "Use a strong password. For production use Secrets Manager instead."
  type        = string
  sensitive   = true
}

variable "rds_db_name" {
  type    = string
  default = "shop"
}

variable "worker_count" {
  type    = number
  default = 4
}
