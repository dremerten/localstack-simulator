variable "name_prefix" {
  type        = string
  description = "Base name prefix"
}

variable "component" {
  type        = string
  description = "Component name (primary/secondary)"
}

variable "environment" {
  type        = string
  description = "Environment tag"
}

variable "region" {
  type        = string
  description = "Region for this deployment"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR range"
}

variable "simulate_unsupported" {
  type        = bool
  description = "Skip resources not supported by LocalStack Community"
}

variable "localstack_pro" {
  type        = bool
  description = "Enable LocalStack Pro-only resources when available"
  default     = false
}

variable "azs" {
  type        = list(string)
  description = "Availability zones to use"
  default     = []
}

variable "alb_count" {
  type        = number
  description = "Number of ALBs per region"
  default     = 3
}

variable "app_instance_type" {
  type        = string
  description = "EC2 instance type for app servers"
}

variable "db_instance_class" {
  type        = string
  description = "RDS instance class"
}

variable "db_username" {
  type        = string
  description = "Database username"
}

variable "db_password" {
  type        = string
  description = "Database password"
  sensitive   = true
}

variable "asg_min_size" {
  type        = number
  description = "Auto Scaling Group minimum size"
}

variable "asg_max_size" {
  type        = number
  description = "Auto Scaling Group maximum size"
}

variable "asg_desired_capacity" {
  type        = number
  description = "Auto Scaling Group desired capacity"
}

variable "tags" {
  type        = map(string)
  description = "Base tags to apply"
  default     = {}
}
