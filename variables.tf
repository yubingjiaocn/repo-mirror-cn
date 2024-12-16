variable "region" {
  description = "AWS region"
  type        = string
  default     = "cn-northwest-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "m7g.xlarge"
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the EC2 instance will be created"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where the EC2 instance will be created"
  type        = string
}

variable "alb_subnet_ids" {
  description = "List of subnet IDs for the Application Load Balancer (minimum 2 subnets in different AZs required)"
  type        = list(string)
}
