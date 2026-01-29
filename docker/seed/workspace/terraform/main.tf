terraform {
  required_version = ">= 1.4.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  access_key                  = var.aws_access_key_id
  secret_key                  = var.aws_secret_access_key
  region                      = var.primary_region
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3          = var.localstack_endpoint
    iam         = var.localstack_endpoint
    sts         = var.localstack_endpoint
    ec2         = var.localstack_endpoint
    autoscaling = var.localstack_endpoint
    elb         = var.localstack_endpoint
    elbv2       = var.localstack_endpoint
    acm         = var.localstack_endpoint
    rds         = var.localstack_endpoint
    route53     = var.localstack_endpoint
  }
}

provider "aws" {
  alias                       = "secondary"
  access_key                  = var.aws_access_key_id
  secret_key                  = var.aws_secret_access_key
  region                      = var.secondary_region
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3          = var.localstack_endpoint
    iam         = var.localstack_endpoint
    sts         = var.localstack_endpoint
    ec2         = var.localstack_endpoint
    autoscaling = var.localstack_endpoint
    elb         = var.localstack_endpoint
    elbv2       = var.localstack_endpoint
    acm         = var.localstack_endpoint
    rds         = var.localstack_endpoint
    route53     = var.localstack_endpoint
  }
}

locals {
  base_tags = {
    project = var.name_prefix
    env     = var.environment
  }
}

module "primary" {
  source              = "./modules/ha_region"
  providers           = { aws = aws }
  name_prefix         = var.name_prefix
  component           = "primary"
  environment         = var.environment
  region              = var.primary_region
  vpc_cidr            = var.primary_vpc_cidr
  simulate_unsupported = var.simulate_unsupported
  localstack_pro      = var.localstack_pro
  app_instance_type   = var.app_instance_type
  db_instance_class   = var.db_instance_class
  db_username         = var.db_username
  db_password         = var.db_password
  alb_count           = var.alb_count
  asg_min_size        = var.asg_min_size
  asg_max_size        = var.asg_max_size
  asg_desired_capacity = var.asg_desired_capacity
  tags                = local.base_tags
}

module "secondary" {
  source              = "./modules/ha_region"
  providers           = { aws = aws.secondary }
  name_prefix         = var.name_prefix
  component           = "secondary"
  environment         = var.environment
  region              = var.secondary_region
  vpc_cidr            = var.secondary_vpc_cidr
  simulate_unsupported = var.simulate_unsupported
  localstack_pro      = var.localstack_pro
  app_instance_type   = var.app_instance_type
  db_instance_class   = var.db_instance_class
  db_username         = var.db_username
  db_password         = var.db_password
  alb_count           = var.alb_count
  asg_min_size        = var.asg_min_size
  asg_max_size        = var.asg_max_size
  asg_desired_capacity = var.asg_desired_capacity
  tags                = local.base_tags
}
