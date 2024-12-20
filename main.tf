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

  name        = "nexus-repository-alb-sg-${var.environment}"
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

  name        = "nexus-repository-instance-sg-${var.environment}"
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

  ingress_with_source_security_group_id = [
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

  name = "nexus-repository-alb-${var.environment}"

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
        port               = 8081
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
  name        = "nexus-repository-waf-${var.environment}"
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
    metric_name               = "nexus-repository-waf-metric"
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
  role_name              = "nexus-repository-ec2-role-${var.environment}"
  role_requires_mfa      = false
  trusted_role_services  = ["ec2.amazonaws.com"]
  custom_role_policy_arns = [
    "arn:aws-cn:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws-cn:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ]
}

# Additional policy for EC2 to manage EBS volumes
resource "aws_iam_role_policy" "ebs_management" {
  name = "nexus-repository-ebs-management-policy"
  role = module.iam_assumable_role.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:DetachVolume"
        ]
        Resource = [
          "${aws_ebs_volume.nexus_data.arn}",
          "arn:aws-cn:ec2:*:*:instance/*"
        ]
      }
    ]
  })
}

# Get subnet information for AZ
data "aws_subnet" "selected" {
  id = var.subnet_id
}

# EBS volume for Nexus data
resource "aws_ebs_volume" "nexus_data" {
  availability_zone = data.aws_subnet.selected.availability_zone
  size             = 100
  type             = "gp3"

  tags = {
    Name = "nexus-repository-data-${var.environment}"
  }
}

# Create instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "nexus-repository-instance-profile-${var.environment}"
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
  name = "nexus-repository-s3-access-policy-${var.environment}"
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
  name                = "nexus-repository-${var.environment}"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = [var.subnet_id]
  health_check_type   = "EC2"
  target_group_arns   = module.alb.target_group_arns

  # Launch template
  create_launch_template = true
  launch_template_name   = "nexus-repository-${var.environment}"
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

  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Install Docker
    dnf update -y
    dnf install -y docker
    sudo usermod -a -G docker ec2-user
    systemctl enable docker
    systemctl start docker

    # Install ECR credential helper
    dnf install -y amazon-ecr-credential-helper
    mkdir -p /root/.docker
    echo '{"credsStore": "ecr-login"}' > /root/.docker/config.json

    # Find and attach the Nexus data volume
    VOLUME_ID=$(aws ec2 describe-volumes \
      --filters "Name=tag:Name,Values=nexus-repository-data-${var.environment}" \
      --query "Volumes[0].VolumeId" \
      --output text)

    if [ -z "$VOLUME_ID" ]; then
      echo "ERROR: Could not find Nexus data volume" | logger -t nexus-setup
      exit 1
    fi

    # Check if volume is already attached
    ATTACHMENT_STATE=$(aws ec2 describe-volumes \
      --volume-ids "$VOLUME_ID" \
      --query 'Volumes[0].Attachments[0].State' \
      --output text)

    if [ "$ATTACHMENT_STATE" = "attached" ]; then
      echo "ERROR: Volume $VOLUME_ID is already attached to another instance" | logger -t nexus-setup
      exit 1
    fi

    # Get instance ID
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

    # Attach volume
    aws ec2 attach-volume \
      --volume-id "$VOLUME_ID" \
      --instance-id "$INSTANCE_ID" \
      --device /dev/xvdb

    # Wait for device to be available
    while [ ! -e /dev/xvdb ]; do
      echo "Waiting for volume to be attached..." | logger -t nexus-setup
      sleep 5
    done

    # Format only if not already formatted
    if ! blkid /dev/xvdb; then
      mkfs -t xfs /dev/xvdb
    fi

    # Mount volume
    mkdir -p /opt/nexus-data
    mount /dev/xvdb /opt/nexus-data
    echo "/dev/xvdb /opt/nexus-data xfs defaults,nofail 0 2" >> /etc/fstab
    chown -R 200:200 /opt/nexus-data

    # Get account ID for ECR repository URL
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    # Start Nexus container
    docker pull ${var.nexus_image}
    docker run -d \
      --restart=always \
      --name nexus \
      -p 8081:8081 \
      -v /opt/nexus-data:/nexus-data \
      ${var.nexus_start_parameter} \
      ${var.nexus_image}
  EOF
  )

  tags = {
    Environment = var.environment
  }
}

# Get the instance ID from the ASG
data "aws_instances" "asg_instances" {
  instance_tags = {
    "aws:autoscaling:groupName" = module.asg.autoscaling_group_name
  }

  depends_on = [module.asg]
}