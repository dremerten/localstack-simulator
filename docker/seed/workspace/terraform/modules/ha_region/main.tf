terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

locals {
  enable_full = !var.simulate_unsupported && var.localstack_pro
  azs         = length(var.azs) > 0 ? var.azs : ["${var.region}a", "${var.region}b", "${var.region}c"]
  name        = "${var.name_prefix}-${var.component}"
  tags = merge(var.tags, {
    component = var.component
    region    = var.region
    env       = var.environment
  })
  bucket_name = substr(join("-", regexall("[a-z0-9-]+", lower("${local.name}-app"))), 0, 63)
  alb_name_prefix = substr(join("-", regexall("[a-z0-9-]+", lower("${local.name}-alb"))), 0, 30)
  tg_name_prefix  = substr(join("-", regexall("[a-z0-9-]+", lower("${local.name}-tg"))), 0, 30)
  user_data   = "#!/bin/bash\necho 'Hello from LocalStack' > /var/www/html/index.html\n"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, {
    Name = "${local.name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.tags, {
    Name = "${local.name}-igw"
  })
}

resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = merge(local.tags, {
    Name = "${local.name}-public-${count.index + 1}"
    tier = "public"
  })
}

resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.azs[count.index]
  tags = merge(local.tags, {
    Name = "${local.name}-private-${count.index + 1}"
    tier = "private"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.tags, {
    Name = "${local.name}-public-rt"
    tier = "public"
  })
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = local.enable_full ? length(aws_subnet.public) : 0
  domain = "vpc"
  tags = merge(local.tags, {
    Name = "${local.name}-nat-eip-${count.index + 1}"
  })
}

resource "aws_nat_gateway" "this" {
  count         = local.enable_full ? length(aws_subnet.public) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags = merge(local.tags, {
    Name = "${local.name}-nat-${count.index + 1}"
  })
}

resource "aws_route_table" "private" {
  for_each = { for idx, subnet in aws_subnet.private : idx => subnet }
  vpc_id   = aws_vpc.this.id
  tags = merge(local.tags, {
    Name = "${local.name}-private-rt-${tonumber(each.key) + 1}"
    tier = "private"
  })
}

resource "aws_route" "private_nat" {
  for_each               = local.enable_full ? aws_route_table.private : {}
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[tonumber(each.key)].id
}

resource "aws_route_table_association" "private" {
  for_each       = aws_route_table.private
  subnet_id      = aws_subnet.private[tonumber(each.key)].id
  route_table_id = each.value.id
}

resource "aws_s3_bucket" "app" {
  bucket        = local.bucket_name
  force_destroy = true
  tags = merge(local.tags, {
    Name = "${local.name}-app-bucket"
  })
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${local.name}-app-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = local.tags
}

data "aws_iam_policy_document" "app_policy" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.app.arn]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.app.arn}/*"]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "${local.name}-app-policy"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_policy.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name}-instance-profile"
  role = aws_iam_role.app.name
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Allow HTTP/HTTPS to ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group" "app" {
  name        = "${local.name}-app-sg"
  description = "Allow HTTP from ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db-sg"
  description = "Allow MySQL from app"
  vpc_id      = aws_vpc.this.id

  ingress {
    protocol        = "tcp"
    from_port       = 3306
    to_port         = 3306
    security_groups = [aws_security_group.app.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_lb" "app" {
  count               = local.enable_full ? var.alb_count : 0
  name                = format("%s-%d", local.alb_name_prefix, count.index + 1)
  load_balancer_type  = "application"
  internal            = false
  security_groups     = [aws_security_group.alb.id]
  subnets             = [for subnet in aws_subnet.public : subnet.id]
  enable_deletion_protection = false
  tags = local.tags
}

resource "aws_lb_target_group" "app" {
  count     = local.enable_full ? var.alb_count : 0
  name      = format("%s-%d", local.tg_name_prefix, count.index + 1)
  port      = 80
  protocol  = "HTTP"
  target_type = "instance"
  vpc_id    = aws_vpc.this.id
  health_check {
    path     = "/"
    protocol = "HTTP"
  }
  tags = local.tags
}

resource "aws_lb_listener" "app" {
  count             = local.enable_full ? var.alb_count : 0
  load_balancer_arn = aws_lb.app[count.index].arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[count.index].arn
  }
}

resource "aws_acm_certificate" "app" {
  count             = local.enable_full ? 1 : 0
  domain_name       = "app.${var.component}.local"
  validation_method = "DNS"
  tags              = local.tags
}

resource "aws_lb_listener" "app_https" {
  count             = local.enable_full ? var.alb_count : 0
  load_balancer_arn = aws_lb.app[count.index].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.app[0].arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[count.index].arn
  }
}

resource "aws_launch_template" "app" {
  count         = local.enable_full ? 1 : 0
  name_prefix   = "${local.name}-lt-"
  image_id      = "ami-12345678"
  instance_type = var.app_instance_type
  user_data     = base64encode(local.user_data)

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_tokens = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.tags, {
      Name = "${local.name}-app"
    })
  }

  tags = local.tags
}

resource "aws_autoscaling_group" "app" {
  count               = local.enable_full ? 1 : 0
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = [for subnet in aws_subnet.private : subnet.id]
  health_check_type   = "EC2"
  target_group_arns   = [for tg in aws_lb_target_group.app : tg.arn]

  launch_template {
    id      = aws_launch_template.app[0].id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-app"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_subnet_group" "app" {
  count      = local.enable_full ? 1 : 0
  name       = "${local.name}-db-subnets"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]
  tags       = local.tags
}

resource "aws_db_instance" "app" {
  count                  = local.enable_full ? 1 : 0
  identifier             = "${local.name}-db"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.4.0"
  instance_class         = var.db_instance_class
  db_subnet_group_name   = aws_db_subnet_group.app[0].name
  vpc_security_group_ids = [aws_security_group.db.id]
  username               = var.db_username
  password               = var.db_password
  multi_az               = true
  storage_encrypted      = true
  backup_retention_period = 7
  skip_final_snapshot    = true
  publicly_accessible    = false
  tags                   = local.tags
}

resource "aws_route53_zone" "app" {
  count       = local.enable_full ? 1 : 0
  name        = "${var.component}.local"
  comment     = "LocalStack private zone"
  force_destroy = true
  vpc {
    vpc_id     = aws_vpc.this.id
    vpc_region = var.region
  }
  tags = local.tags
}

resource "aws_route53_record" "app" {
  count   = local.enable_full ? var.alb_count : 0
  zone_id = aws_route53_zone.app[0].zone_id
  name    = "app.${var.component}.local"
  type    = "CNAME"
  ttl     = 60
  records = [aws_lb.app[count.index].dns_name]
  set_identifier = "alb-${count.index + 1}"
  weighted_routing_policy {
    weight = 1
  }
}

locals {
  alb_dns     = local.enable_full ? [for lb in aws_lb.app : lb.dns_name] : ["simulated-alb"]
  rds_endpoint = local.enable_full ? aws_db_instance.app[0].endpoint : "simulated-rds"
}
