variable "aws_access_key_id" {
  type        = string
  description = "Access key for LocalStack"
  default     = "test"
}

variable "aws_secret_access_key" {
  type        = string
  description = "Secret key for LocalStack"
  default     = "test"
}

variable "primary_region" {
  type        = string
  description = "Primary AWS region"
  default     = "us-east-1"
}

variable "secondary_region" {
  type        = string
  description = "Secondary AWS region"
  default     = "us-west-2"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint"
  default     = "http://localstack:4566"
}

variable "name_prefix" {
  type        = string
  description = "Name prefix for resources"
  default     = "sandbox"
}

variable "environment" {
  type        = string
  description = "Environment tag"
  default     = "dev"
}

variable "primary_vpc_cidr" {
  type        = string
  description = "Primary VPC CIDR"
  default     = "10.0.0.0/16"
}

variable "secondary_vpc_cidr" {
  type        = string
  description = "Secondary VPC CIDR"
  default     = "10.1.0.0/16"
}

variable "simulate_unsupported" {
  type        = bool
  description = "Skip resources not supported by LocalStack Community"
  default     = true
}

variable "localstack_pro" {
  type        = bool
  description = "Enable LocalStack Pro-only resources when available"
  default     = false
}

variable "app_instance_type" {
  type        = string
  description = "EC2 instance type for app servers"
  default     = "t3.micro"
}

variable "db_instance_class" {
  type        = string
  description = "RDS instance class"
  default     = "db.t3.micro"
}

variable "db_username" {
  type        = string
  description = "Database username"
  default     = "appuser"
}

variable "db_password" {
  type        = string
  description = "Database password"
  default     = "localstack123"
  sensitive   = true
}

variable "asg_min_size" {
  type        = number
  description = "Auto Scaling Group minimum size"
  default     = 3
}

variable "asg_max_size" {
  type        = number
  description = "Auto Scaling Group maximum size"
  default     = 6
}

variable "asg_desired_capacity" {
  type        = number
  description = "Auto Scaling Group desired capacity"
  default     = 3
}

variable "alb_count" {
  type        = number
  description = "Number of ALBs per region"
  default     = 3
}
