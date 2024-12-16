# AWS Infrastructure Terraform Configuration

This Terraform configuration creates the following AWS resources:

- Application Load Balancer (ALB) with Web Application Firewall (WAF)
- Auto Scaling Group with single EC2 instance running Amazon Linux 2023 (ARM64)
- Managed prefix lists for AWS China regions (cn-north-1 and cn-northwest-1)
- Elastic IP attached to the EC2 instance
- S3 bucket for blob storage
- IAM role with S3 access and SSM permissions
- Security groups for ALB and EC2 instance

## Prerequisites

- Terraform installed (version >= 1.0)
- AWS credentials configured
- Existing VPC and subnets
- Existing SSH key pair in AWS

## Usage

1. Initialize Terraform:

    ```bash
    terraform init
    ```

2. Create a `terraform.tfvars` file with your values:

    ```hcl
    region         = "cn-northwest-1"  # or cn-north-1
    vpc_id         = "vpc-xxxxxx"
    subnet_id      = "subnet-xxxxxx"
    alb_subnet_ids = ["subnet-xxxxx1", "subnet-xxxxx2"]  # At least 2 subnets in different AZs
    key_name       = "your-key-pair-name"
    bucket_name    = "your-unique-bucket-name"
    environment    = "prod"  # optional, defaults to prod
    ```

3. Review the plan:

    ```bash
    terraform plan
    ```

4. Apply the configuration:

    ```bash
    terraform apply
    ```

## Required Variables

| Name | Description | Type |
|------|-------------|------|
| vpc_id | ID of the VPC | string |
| subnet_id | ID of the subnet for the EC2 instance | string |
| alb_subnet_ids | List of subnet IDs for ALB (minimum 2 subnets in different AZs) | list(string) |
| key_name | Name of the SSH key pair | string |
| bucket_name | Name of the S3 bucket | string |

## Optional Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| region | AWS region | string | cn-northwest-1 |
| instance_type | EC2 instance type | string | m7g.xlarge |
| environment | Environment name | string | prod |

## Outputs

| Name | Description |
|------|-------------|
| alb_dns_name | DNS name of the Application Load Balancer |
| instance_public_ip | Public IP (Elastic IP) of the EC2 instance |
| instance_private_ip | Private IP of the EC2 instance |
| s3_bucket_name | Name of the created S3 bucket |
| s3_bucket_arn | ARN of the S3 bucket |
| iam_role_arn | ARN of the IAM role |
| security_group_id | ID of the security group |
| asg_name | Name of the Auto Scaling Group |
| managed_prefix_list_ids | IDs of the managed prefix lists for AWS China regions |

## Clean Up

To destroy the created resources:

```bash
terraform destroy
```

## Notes

- The EC2 instance uses the latest Amazon Linux 2023 ARM64 AMI
- The root volume is 50GB GP3
- The instance has full access to the created S3 bucket
- SSM Session Manager access is enabled through the IAM role
- The Auto Scaling Group maintains exactly one instance
- Application traffic is routed through ALB with WAF protection
- All S3 bucket public access is blocked by default
