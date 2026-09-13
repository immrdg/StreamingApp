# ====================================================================
# JENKINS BACKUP & PERSISTENCE MODULE
# Provides S3 backup storage, RDS database backup, and state management
# ====================================================================

# S3 bucket for Jenkins configuration backups
resource "aws_s3_bucket" "jenkins_backups" {
  bucket = "${var.name_prefix}-jenkins-backups-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "${var.name_prefix}-jenkins-backups"
    Project = "StreamingApp"
    Purpose = "Jenkins-Config-Backup"
    Managed = "terraform"
  }
}

# Enable versioning for backup recovery
resource "aws_s3_bucket_versioning" "jenkins_backups" {
  bucket = aws_s3_bucket.jenkins_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "jenkins_backups" {
  bucket = aws_s3_bucket.jenkins_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "jenkins_backups" {
  bucket = aws_s3_bucket.jenkins_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy: transition old backups to Glacier
resource "aws_s3_bucket_lifecycle_configuration" "jenkins_backups" {
  bucket = aws_s3_bucket.jenkins_backups.id

  rule {
    id     = "transition-old-backups"
    status = "Enabled"
    filter {}

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365  # Delete backups after 1 year
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# IAM policy for Jenkins to write to backup bucket
resource "aws_iam_role_policy" "jenkins_backup_s3" {
  name = "${var.name_prefix}-jenkins-backup-s3"
  role = aws_iam_role.jenkins.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadWriteJenkinsBackups"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:ListBucketVersions"
        ]
        Resource = [
          aws_s3_bucket.jenkins_backups.arn,
          "${aws_s3_bucket.jenkins_backups.arn}/*"
        ]
      }
    ]
  })
}

# ====================================================================
# EBS SNAPSHOTS FOR JENKINS VOLUME BACKUP
# ====================================================================

# Data lifecycle manager policy for EBS snapshots
resource "aws_dlm_lifecycle_policy" "jenkins_ebs" {
  description        = "Automated daily snapshots of Jenkins root volume"
  execution_role_arn = aws_iam_role.dlm.arn
  state               = "ENABLED"

  policy_details {
    policy_type = "EBS_SNAPSHOT_MANAGEMENT"

    resource_types = ["VOLUME"]

    schedule {
      name = "Daily snapshots"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]  # 3 AM UTC
      }

      retain_rule {
        count = 30
      }

      copy_tags = true

      tags_to_add = {
        SnapshotType = "jenkins-backup"
      }
    }

    target_tags = {
      Name = "${var.name_prefix}-jenkins"
    }
  }
}

# IAM role for DLM to create snapshots
resource "aws_iam_role" "dlm" {
  name = "${var.name_prefix}-dlm-lifecycle-manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "dlm.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "dlm" {
  name   = "dlm-lifecycle-policy"
  role   = aws_iam_role.dlm.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateSnapshots",
          "ec2:DeleteSnapshot",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:EnableFastSnapshotRestores",
          "ec2:DescribeFastSnapshotRestores",
          "ec2:DisableFastSnapshotRestores"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = [
          "arn:aws:ec2:*::snapshot/*",
          "arn:aws:ec2:*::volume/*"
        ]
      }
    ]
  })
}

# ====================================================================
# JENKINS STATE BACKUP TO S3 (Terraform State)
# ====================================================================

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.name_prefix}-terraform-state-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "${var.name_prefix}-terraform-state"
    Project = "StreamingApp"
    Purpose = "Terraform-State-Backup"
    Managed = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable MFA delete protection
resource "aws_s3_bucket_versioning" "terraform_state_mfa" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status     = "Enabled"
    mfa_delete = "Disabled"  # Enable this with MFA in production
  }
}

# ====================================================================
# ELASTICACHE FOR SESSION PERSISTENCE
# ====================================================================

resource "aws_elasticache_replication_group" "jenkins_session" {
  description          = "Redis for Jenkins session persistence and job queue"
  replication_group_id = "${var.name_prefix}-jenkins-session-cache"
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_clusters   = var.redis_num_replicas + 1  # Primary + replicas
  parameter_group_name = "default.redis7"
  port                 = 6379

  # High availability
  automatic_failover_enabled = true
  multi_az_enabled          = true

  # Subnet group for multi-AZ deployment
  subnet_group_name = aws_elasticache_subnet_group.jenkins_session.name

  # Security group
  security_group_ids = [aws_security_group.redis.id]

  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth_token.result

  # Automated backups
  snapshot_retention_limit = var.redis_snapshot_retention_days
  snapshot_window          = "03:00-05:00"
  maintenance_window       = "sun:05:00-sun:06:00"

  # Enable automatic minor version upgrades
  auto_minor_version_upgrade = true

  # Notification ARN for events
  notification_topic_arn = aws_sns_topic.jenkins_notifications.arn

  # Tags
  tags = {
    Name    = "${var.name_prefix}-jenkins-session-cache"
    Project = "StreamingApp"
    Managed = "terraform"
  }

  depends_on = [
    aws_elasticache_subnet_group.jenkins_session,
    aws_security_group.redis
  ]
}

# Redis authentication token (strong random string)
resource "random_password" "redis_auth_token" {
  length      = 32
  special     = false  # ElastiCache doesn't allow special characters in auth token
  upper       = true
  lower       = true
  numeric     = true
}

# Subnet group for ElastiCache across multiple AZs
resource "aws_elasticache_subnet_group" "jenkins_session" {
  name       = "${var.name_prefix}-jenkins-session-cache"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "${var.name_prefix}-jenkins-session-cache-subnet-group"
  }
}

# Security group for Redis
resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-jenkins-redis"
  description = "Security group for Jenkins Redis session cache"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Redis from Jenkins"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-jenkins-redis"
  }
}

# IAM policy for Jenkins to access Redis
resource "aws_iam_role_policy" "jenkins_redis" {
  name = "${var.name_prefix}-jenkins-redis-access"
  role = aws_iam_role.jenkins.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ElastiCacheRedisAccess"
        Effect = "Allow"
        Action = [
          "elasticache:DescribeReplicationGroups",
          "elasticache:DescribeCacheClusters",
          "elasticache:DescribeCacheNodes"
        ]
        Resource = aws_elasticache_replication_group.jenkins_session.arn
      }
    ]
  })
}

# ====================================================================
# SNS TOPIC FOR NOTIFICATIONS
# ====================================================================

resource "aws_sns_topic" "jenkins_notifications" {
  name              = "${var.name_prefix}-jenkins-notifications"
  display_name      = "Jenkins Events and Notifications"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name    = "${var.name_prefix}-jenkins-notifications"
    Project = "StreamingApp"
    Managed = "terraform"
  }
}

resource "aws_sns_topic_policy" "jenkins_notifications" {
  arn = aws_sns_topic.jenkins_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowServices"
        Effect = "Allow"
        Principal = {
          Service = ["elasticache.amazonaws.com", "cloudwatch.amazonaws.com"]
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.jenkins_notifications.arn
      }
    ]
  })
}

# ====================================================================
# CLOUDWATCH ALARMS FOR JENKINS HEALTH
# ====================================================================

resource "aws_cloudwatch_metric_alarm" "jenkins_instance_status" {
  alarm_name          = "${var.name_prefix}-jenkins-instance-status-check"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Alert when Jenkins instance fails status checks"
  alarm_actions       = [aws_sns_topic.jenkins_notifications.arn]

  dimensions = {
    InstanceId = aws_instance.jenkins.id
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "${var.name_prefix}-jenkins-redis-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Alert when Redis CPU exceeds 75%"
  alarm_actions       = [aws_sns_topic.jenkins_notifications.arn]

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.jenkins_session.id
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name          = "${var.name_prefix}-jenkins-redis-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Alert when Redis memory exceeds 90%"
  alarm_actions       = [aws_sns_topic.jenkins_notifications.arn]

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.jenkins_session.id
  }
}

# ====================================================================
# DATA SOURCE
# ====================================================================

data "aws_caller_identity" "current" {}
