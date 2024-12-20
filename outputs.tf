output "instance_id" {
  description = "ID of the EC2 instance"
  value       = data.aws_instances.asg_instances.ids[0]
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = data.aws_instances.asg_instances.private_ips[0]
}

output "ebs_volume_id" {
  description = "ID of the EBS volume for Nexus data"
  value       = aws_ebs_volume.nexus_data.id
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.asg.autoscaling_group_name
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = module.s3_bucket.s3_bucket_id
}

output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = module.iam_assumable_role.iam_role_arn
}

output "instance_security_group_id" {
  description = "ID of the instance security group"
  value       = module.security_group.security_group_id
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.lb_dns_name
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = module.alb_security_group.security_group_id
}

output "waf_web_acl_id" {
  description = "ID of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.id
}
