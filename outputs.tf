output "instance_id" {
  description = "ID of the EC2 instance"
  value       = data.aws_instances.asg_instances.ids[0]
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_eip.instance_eip.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = data.aws_instances.asg_instances.private_ips[0]
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = module.s3_bucket.s3_bucket_id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = module.s3_bucket.s3_bucket_arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = module.iam_assumable_role.iam_role_arn
}

output "security_group_id" {
  description = "ID of the security group"
  value       = module.security_group.security_group_id
}
