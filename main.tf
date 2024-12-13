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

  # Add more entries as needed
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
  # Add more entries as needed
}

# Get latest AL2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group Module
module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "instance_sg_${var.environment}"
  description = "Security group for EC2 instance"
  vpc_id      = var.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    },
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
      from_port         = 8081
      to_port           = 8081
      protocol          = "tcp"
      prefix_list_ids   = [aws_ec2_managed_prefix_list.northwest.id, aws_ec2_managed_prefix_list.north.id]
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

# IAM Role Module
module "iam_assumable_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "~> 5.0"

  create_role             = true
  role_name              = "ec2_role_${var.environment}"
  role_requires_mfa      = false
  trusted_role_services  = ["ec2.amazonaws.com"]
  custom_role_policy_arns = [
    "arn:aws-cn:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

# Create instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile_${var.environment}"
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

# EC2 Instance Module
module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.0"

  name = "app-server-${var.environment}"

  ami                    = data.aws_ami.al2023.id
  instance_type         = var.instance_type
  key_name             = var.key_name
  subnet_id            = var.subnet_id

  vpc_security_group_ids = [module.security_group.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device = [
    {
      volume_size = 50
      volume_type = "gp3"
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

# Associate EIP with EC2 instance
resource "aws_eip_association" "eip_assoc" {
  instance_id   = module.ec2_instance.id
  allocation_id = aws_eip.instance_eip.id
}
