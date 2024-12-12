# AWS Infrastructure Terraform Configuration

This Terraform configuration creates the following AWS resources in the cn-northwest-1 region:

- EC2 instance (m7g.xlarge) with Amazon Linux 2023
- Elastic IP attached to the EC2 instance
- S3 bucket for blob storage
- IAM role with S3 access and SSM permissions
- Security group allowing SSH (22) and custom application port (8081)

## Prerequisites

- Terraform installed (version >= 1.0)
- AWS credentials configured
- Existing SSH key pair in AWS

## Usage

1. Initialize Terraform:
```bash
terraform init
```

2. Create a `terraform.tfvars` file with your values:
```hcl
key_name    = "your-key-pair-name"
bucket_name = "your-unique-bucket-name"
environment = "prod"  # optional, defaults to prod
```

3. Review the plan:
```bash
terraform plan
```

4. Apply the configuration:
```bash
terraform apply
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| region | AWS region | string | cn-northwest-1 |
| instance_type | EC2 instance type | string | m7g.xlarge |
| key_name | Name of the SSH key pair | string | - |
| environment | Environment name | string | prod |
| bucket_name | Name of the S3 bucket | string | - |

## Outputs

| Name | Description |
|------|-------------|
| instance_id | ID of the EC2 instance |
| instance_public_ip | Public IP address of the EC2 instance |
| instance_private_ip | Private IP address of the EC2 instance |
| s3_bucket_name | Name of the S3 bucket |
| s3_bucket_arn | ARN of the S3 bucket |
| iam_role_arn | ARN of the IAM role |
| security_group_id | ID of the security group |

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
