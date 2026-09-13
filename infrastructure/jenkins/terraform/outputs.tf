output "instance_id" {
  description = "SSM-managed Jenkins EC2 instance ID."
  value       = aws_instance.jenkins.id
}

output "jenkins_url" {
  description = "Jenkins URL after the Ansible configuration succeeds."
  value       = "http://${aws_instance.jenkins.public_dns}:8080"
}

output "jenkins_ssh_key_path" {
  description = "Local path to the generated PEM private key for SSH access to the controller."
  value       = local_sensitive_file.jenkins_controller_private_key.filename
  sensitive   = true
}

output "jenkins_public_ip" {
  description = "Public IP of the Jenkins controller instance."
  value       = aws_instance.jenkins.public_ip
}

output "ssm_target" {
  description = "Target identifier for AWS Systems Manager Session Manager."
  value       = aws_instance.jenkins.id
}

output "jenkins_agent_security_group_id" {
  description = "Security group ID attached to EC2 build agents."
  value       = aws_security_group.jenkins_agent.id
}

output "jenkins_agent_instance_profile" {
  description = "Instance profile ARN used by EC2 build agents (the ec2 plugin's JCasC field requires the ARN, not the name)."
  value       = aws_iam_instance_profile.jenkins_agent.arn
}

output "jenkins_agent_key_name" {
  description = "EC2 key pair name used by the EC2 plugin to bootstrap agents."
  value       = aws_key_pair.jenkins_agent.key_name
}

output "jenkins_agent_ami" {
  description = "AMI ID used for EC2 build agents."
  value       = nonsensitive(local.jenkins_agent_ami)
}

output "jenkins_agent_subnet_id" {
  description = "Subnet ID EC2 build agents are launched into."
  value       = data.aws_subnets.default.ids[0]
}

output "jenkins_agent_private_key_path" {
  description = "Local path to the generated PEM private key for the agent SSH credential."
  value       = local_sensitive_file.jenkins_agent_private_key.filename
}

# ====================================================================
# BACKUP & FAILOVER OUTPUTS
# ====================================================================

output "jenkins_backup_bucket" {
  description = "S3 bucket for Jenkins configuration backups"
  value       = aws_s3_bucket.jenkins_backups.id
}

output "backup_bucket_region" {
  description = "AWS region where backups are stored"
  value       = aws_s3_bucket.jenkins_backups.region
}

output "terraform_state_bucket" {
  description = "S3 bucket for Terraform state backups"
  value       = aws_s3_bucket.terraform_state.id
}

output "redis_endpoint" {
  description = "Redis cluster endpoint for Jenkins session persistence"
  value       = aws_elasticache_replication_group.jenkins_session.configuration_endpoint_address
}

output "redis_port" {
  description = "Redis port number"
  value       = aws_elasticache_replication_group.jenkins_session.port
}

output "redis_auth_token_name" {
  description = "Name of AWS Secrets Manager secret containing Redis auth token"
  value       = "redis-auth-token-stored-in-secrets-manager"
}

output "ebs_snapshot_schedule_id" {
  description = "DLM lifecycle policy ID for EBS snapshots"
  value       = aws_dlm_lifecycle_policy.jenkins_ebs.id
}

output "sns_topic_arn" {
  description = "SNS topic ARN for Jenkins notifications"
  value       = aws_sns_topic.jenkins_notifications.arn
}

output "jenkins_redis_security_group_id" {
  description = "Security group ID for Redis access"
  value       = aws_security_group.redis.id
}

output "backup_strategy_summary" {
  description = "Summary of backup and failover strategy"
  value = {
    jenkins_config_backup = "Automatic daily S3 backups with versioning"
    ebs_snapshots         = "Automated daily EBS snapshots (30-day retention)"
    session_persistence   = "Redis multi-AZ replication with automatic failover"
    terraform_state       = "Versioned S3 bucket with encryption"
    notifications         = "SNS alerts for critical events"
    rto_minutes           = 15  # Recovery Time Objective
    rpo_hours             = 1   # Recovery Point Objective
  }
}

output "failover_configuration" {
  description = "Failover configuration details"
  value = {
    redis_ha           = "Multi-AZ with automatic failover enabled"
    redis_replicas     = var.redis_num_replicas
    jenkins_ebs        = "Daily snapshots with 30-day retention"
    backup_bucket      = "Cross-region replication recommended for production"
    recovery_procedure = "See BACKUP_RECOVERY.md in infrastructure/jenkins"
  }
}
