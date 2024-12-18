provider "aws" {
  region = var.region
}

# Get VPC details
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Managed prefix list for cn-northwest-1 region
resource "aws_ec2_managed_prefix_list" "northwest" {
  name           = "cn-northwest-1-ranges"
  address_family = "IPv4"
  max_entries    = 20

  entry {
    cidr        = "43.192.0.0/14"
  }
  entry {
    cidr        = "52.82.0.0/17"
  }
  entry {
    cidr        = "52.82.160.0/19"
  }
  entry {
    cidr        = "52.82.192.0/18"
  }
  entry {
    cidr        = "52.83.0.0/16"
  }
  entry {
    cidr        = "52.93.127.92/30"
  }
  entry {
    cidr        = "52.93.127.96/28"
  }
  entry {
    cidr        = "54.239.0.176/28"
  }
  entry {
    cidr        = "68.79.0.0/18"
  }
  entry {
    cidr        = "69.230.192.0/18"
  }
  entry {
    cidr        = "69.231.128.0/18"
  }
  entry {
    cidr        = "69.234.192.0/18"
  }
  entry {
    cidr        = "69.235.128.0/18"
  }
  entry {
    cidr        = "161.189.0.0/16"
  }
}

# Managed prefix list for cn-north-1 region
resource "aws_ec2_managed_prefix_list" "north" {
  name           = "cn-north-1-ranges"
  address_family = "IPv4"
  max_entries    = 20

  entry {
    cidr        = "15.230.41.0/24"
  }
  entry {
    cidr        = "15.230.49.0/24"
  }
  entry {
    cidr        = "15.230.141.0/24"
  }
  entry {
    cidr        = "43.195.0.0/16"
  }
  entry {
    cidr        = "43.196.0.0/16"
  }
  entry {
    cidr        = "52.80.0.0/15"
  }
  entry {
    cidr        = "52.95.255.144/28"
  }
  entry {
    cidr        = "54.222.0.0/15"
  }
  entry {
    cidr        = "54.239.0.144/28"
  }
  entry {
    cidr        = "71.131.192.0/18"
  }
  entry {
    cidr        = "71.132.0.0/18"
  }
  entry {
    cidr        = "71.136.64.0/18"
  }
  entry {
    cidr        = "71.137.0.0/18"
  }
  entry {
    cidr        = "107.176.0.0/15"
  }
  entry {
    cidr        = "140.179.0.0/16"
  }
  entry {
    cidr        = "150.222.64.0/24"
  }
  entry {
    cidr        = "150.222.88.0/23"
  }
}

# Get latest AL2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# ALB Security Group
module "alb_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "nexus_server_alb_sg_${var.environment}"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 8081
      to_port     = 8081
      protocol    = "tcp"
      cidr_blocks = data.aws_vpc.selected.cidr_block
      description = "Allow access from within VPC"
    }
  ]

  ingress_with_prefix_list_ids = [
    {
      from_port         = 80
      to_port           = 80
      protocol          = "tcp"
      prefix_list_ids   = "${aws_ec2_managed_prefix_list.northwest.id},${aws_ec2_managed_prefix_list.north.id}"
      description       = "Allow access from AWS China regions"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

# Instance Security Group
module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "nexus_server_instance_sg_${var.environment}"
  description = "Security group for EC2 instance"
  vpc_id      = var.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow SSH from anywhere"
    }
  ]

  computed_ingress_with_source_security_group_id = [
    {
      from_port                = 8081
      to_port                  = 8081
      protocol                 = "tcp"
      source_security_group_id = module.alb_security_group.security_group_id
      description             = "Allow traffic from ALB"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

# Application Load Balancer
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = "nexus-alb-${var.environment}"

  load_balancer_type = "application"
  vpc_id             = var.vpc_id
  subnets            = var.alb_subnet_ids
  security_groups    = [module.alb_security_group.security_group_id]

  target_groups = [
    {
      name             = "nexus-tg-${var.environment}"
      backend_protocol = "HTTP"
      backend_port     = 8081
      target_type      = "instance"
      health_check = {
        enabled             = true
        interval           = 30
        path               = "/"
        port               = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout            = 6
        protocol           = "HTTP"
        matcher            = "200-399"
      }
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Environment = var.environment
  }
}

# WAF Web ACL
resource "aws_wafv2_web_acl" "main" {
  name        = "nexus-waf-${var.environment}"
  description = "WAF Web ACL for Nexus ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled  = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name               = "nexus-waf-metric"
    sampled_requests_enabled  = true
  }
}

# Associate WAF Web ACL with ALB
resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = module.alb.lb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# IAM Role Module
module "iam_assumable_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "~> 5.0"

  create_role             = true
  role_name              = "nexus_repo_ec2_role_${var.environment}"
  role_requires_mfa      = false
  trusted_role_services  = ["ec2.amazonaws.com"]
  custom_role_policy_arns = [
    "arn:aws-cn:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

# Create instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "nexus_repo_ec2_profile_${var.environment}"
  role = module.iam_assumable_role.iam_role_name
}

# S3 Bucket Module
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = var.bucket_name

  # Force destroy for easier cleanup
  force_destroy = true

  # Block public access
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for EC2 role
resource "aws_iam_role_policy" "s3_access" {
  name = "s3_access_policy"
  role = module.iam_assumable_role.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn,
          "${module.s3_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Autoscaling Module
module "asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 7.0"

  # Auto scaling group
  name                = "nexus-server-${var.environment}"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = [var.subnet_id]
  health_check_type   = "EC2"
  target_group_arns   = module.alb.target_group_arns

  # Launch template
  create_launch_template = true
  launch_template_name   = "nexus-server-${var.environment}"
  image_id              = data.aws_ami.al2023.id
  instance_type         = var.instance_type
  key_name             = var.key_name

  security_groups          = [module.security_group.security_group_id]
  iam_instance_profile_arn = aws_iam_instance_profile.ec2_profile.arn

  block_device_mappings = [
    {
      device_name = "/dev/xvda"
      ebs = {
        volume_size = 50
        volume_type = "gp3"
      }
    }
  ]

  tags = {
    Environment = var.environment
  }
}

# Create Elastic IP
resource "aws_eip" "instance_eip" {
  domain = "vpc"
}

# Get the instance ID from the ASG
data "aws_instances" "asg_instances" {
  instance_tags = {
    "aws:autoscaling:groupName" = module.asg.autoscaling_group_name
  }

  depends_on = [module.asg]
}

# EIP Association
resource "aws_eip_association" "eip_assoc" {
  allocation_id = aws_eip.instance_eip.id
  instance_id   = data.aws_instances.asg_instances.ids[0]

  depends_on = [module.asg]
}
