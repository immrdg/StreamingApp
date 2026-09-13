# Jenkins Backup & Disaster Recovery Guide

## Overview

This guide documents the backup and disaster recovery strategy for the StreamingApp Jenkins infrastructure deployed via Terraform.

### Recovery Objectives
- **RTO (Recovery Time Objective)**: 15 minutes
- **RPO (Recovery Point Objective)**: 1 hour

---

## Backup Strategy

### 1. Jenkins Configuration Backups (S3)

**Frequency**: Daily automated backups  
**Retention**: 30 days (standard), then moved to Glacier  
**Location**: S3 bucket with versioning enabled

#### Backup Contents
- Jenkins job configurations
- Plugin configurations
- System settings
- Build history (if enabled)

#### S3 Lifecycle Policy
```
Days 0-30:   Standard storage (immediately accessible)
Days 31-365: Glacier storage (cost-optimized, ~5-hour retrieval)
Day 365+:    Automatic deletion
```

#### Manual Backup
```bash
# SSH into Jenkins instance
ssh -i ./generated/jenkins-controller.pem ec2-user@18.141.224.146

# Create manual backup of JENKINS_HOME
tar -czf jenkins-backup-$(date +%Y%m%d-%H%M%S).tar.gz /var/lib/jenkins

# Upload to S3
aws s3 cp jenkins-backup-*.tar.gz s3://streamingapp-jenkins-backups-<ACCOUNT_ID>/manual/
```

---

### 2. EBS Volume Snapshots

**Frequency**: Daily at 03:00 UTC  
**Retention**: 30 days (FastRestore enabled for first 7 days)  
**Managed By**: AWS Data Lifecycle Manager (DLM)

#### Snapshot Details
- Full root volume backups
- Automatically tagged with `SnapshotType: jenkins-backup`
- Can be used to launch replacement instances
- No manual intervention required

#### Restore from Snapshot
```bash
# 1. Identify the latest snapshot
aws ec2 describe-snapshots \
  --filters "Name=tag:SnapshotType,Values=jenkins-backup" \
  --query 'Snapshots[*].[SnapshotId,StartTime,State]' \
  --region ap-southeast-1 \
  --sort-by 'StartTime' \
  --profile siraj

# 2. Create new volume from snapshot
SNAPSHOT_ID="snap-xxxxxxxxx"
aws ec2 create-volume \
  --snapshot-id $SNAPSHOT_ID \
  --availability-zone ap-southeast-1a \
  --volume-type gp3 \
  --region ap-southeast-1 \
  --profile siraj

# 3. Attach volume to new EC2 instance
# Follow AWS console or CLI to mount the volume
```

---

### 3. Redis Session Persistence

**Configuration**: Multi-AZ with automatic failover  
**Replicas**: 2 (primary + 2 replicas across AZs)  
**Snapshots**: Daily at 03:00 UTC, retained for 35 days  
**Encryption**: In-transit and at-rest

#### How Sessions are Protected
- Jenkins sessions stored in Redis cluster
- Multi-AZ deployment ensures availability
- Automatic failover if primary fails (< 30 seconds)
- Daily snapshots for disaster recovery

#### Redis Health Check
```bash
# Get Redis endpoint
REDIS_ENDPOINT=$(terraform output -raw redis_endpoint)

# Check cluster status
aws elasticache describe-replication-groups \
  --replication-group-id streamingapp-jenkins-session-cache \
  --region ap-southeast-1 \
  --profile siraj
```

---

### 4. Terraform State Backup

**Storage**: S3 bucket with versioning  
**Encryption**: AES256  
**Retention**: All versions retained indefinitely

#### State File Recovery
```bash
# List all state versions
aws s3api list-object-versions \
  --bucket streamingapp-terraform-state-<ACCOUNT_ID> \
  --region ap-southeast-1 \
  --profile siraj

# Restore specific version
VERSION_ID="abc123xyz..."
aws s3api get-object \
  --bucket streamingapp-terraform-state-<ACCOUNT_ID> \
  --key terraform.tfstate \
  --version-id $VERSION_ID \
  terraform.tfstate.backup \
  --region ap-southeast-1 \
  --profile siraj
```

---

## Failover Scenarios

### Scenario 1: Redis Cluster Failover (Automatic)

**Condition**: Primary Redis node fails  
**Recovery**: Automatic (< 30 seconds)  
**Action Required**: None

**Verification**:
```bash
# Monitor Redis cluster events
aws elasticache describe-replication-groups \
  --replication-group-id streamingapp-jenkins-session-cache \
  --query 'ReplicationGroups[0].[Status,MemberClusters]' \
  --region ap-southeast-1 \
  --profile siraj
```

### Scenario 2: Jenkins Instance Failure

**Condition**: EC2 instance terminates unexpectedly  
**RTO**: ~10 minutes  
**Data Loss**: None (last EBS snapshot + S3 config backups)

#### Recovery Steps

1. **Verify CloudWatch Alarms**
   ```bash
   # Check if alarm was triggered
   aws cloudwatch describe-alarms \
     --alarm-names streamingapp-jenkins-instance-status-check \
     --region ap-southeast-1 \
     --profile siraj
   ```

2. **Check SNS Notifications**
   - Email should arrive with alert
   - Contains incident timestamp and details

3. **Restore from Latest Snapshot**
   ```bash
   # Get latest snapshot
   SNAPSHOT_ID=$(aws ec2 describe-snapshots \
     --filters "Name=tag:SnapshotType,Values=jenkins-backup" \
     --query 'Snapshots | sort_by(@, &StartTime)[-1].SnapshotId' \
     --region ap-southeast-1 \
     --profile siraj)

   # Apply Terraform to recreate instance
   cd StreamingApp/infrastructure/jenkins/terraform
   terraform apply -auto-approve
   ```

4. **Restore Jenkins Configuration** (if needed)
   ```bash
   # If EBS snapshot restore fails, restore from S3
   # SSH into new instance
   ssh -i ./generated/jenkins-controller.pem ec2-user@<NEW_IP>

   # Download backup from S3
   aws s3 cp s3://streamingapp-jenkins-backups-<ACCOUNT_ID>/jenkins-backup-latest.tar.gz .

   # Extract to JENKINS_HOME
   cd /var/lib/jenkins
   tar -xzf ~/jenkins-backup-latest.tar.gz
   sudo systemctl restart jenkins
   ```

### Scenario 3: Region-Wide Failure

**Condition**: Entire AWS region becomes unavailable  
**RTO**: ~60 minutes  
**Data Loss**: Up to 1 hour  

#### Recovery Steps

1. **Identify Latest Backup**
   - Review S3 backups in primary region
   - Document timestamp and backup key

2. **Deploy to Alternate Region**
   ```bash
   # Update terraform variables
   cd StreamingApp/infrastructure/jenkins/terraform
   
   # Change aws_region in terraform.tfvars
   # e.g., from ap-southeast-1 to ap-southeast-2
   
   sed -i '' 's/ap-southeast-1/ap-southeast-2/g' terraform.tfvars

   # Plan and apply
   terraform plan -out=tfplan-dr
   terraform apply tfplan-dr
   ```

3. **Restore Jenkins from S3 Backup**
   - Copy backup from S3 to new instance
   - Extract and verify configuration

---

## Backup Verification

### Monthly Backup Test

Run this monthly to ensure backups are viable:

```bash
#!/bin/bash
# backup-test.sh

set -e

REGION="ap-southeast-1"
PROFILE="siraj"
BACKUP_BUCKET="streamingapp-jenkins-backups-$(aws sts get-caller-identity --query Account --output text --profile $PROFILE)"

echo "🔍 Backup Verification Test"
echo "=============================="

# Check S3 backups exist
echo "✓ Checking S3 backups..."
aws s3 ls s3://$BACKUP_BUCKET --recursive --region $REGION --profile $PROFILE | tail -5

# Check latest snapshot exists
echo "✓ Checking EBS snapshots..."
aws ec2 describe-snapshots \
  --filters "Name=tag:SnapshotType,Values=jenkins-backup" \
  --query 'Snapshots | sort_by(@, &StartTime)[-1].[SnapshotId,StartTime,VolumeSize]' \
  --region $REGION \
  --profile $PROFILE

# Check Redis backup
echo "✓ Checking Redis replication..."
aws elasticache describe-replication-groups \
  --replication-group-id streamingapp-jenkins-session-cache \
  --query 'ReplicationGroups[0].[Status,MemberClusters,CacheNodeType]' \
  --region $REGION \
  --profile $PROFILE

# Check Terraform state
echo "✓ Checking Terraform state backup..."
aws s3 ls s3://streamingapp-terraform-state-$(aws sts get-caller-identity --query Account --output text --profile $PROFILE) \
  --region $REGION \
  --profile $PROFILE

echo ""
echo "✅ All backups verified successfully!"
```

---

## Monitoring & Alerts

### SNS Notifications

Critical events trigger SNS alerts:
- Jenkins instance failure
- Redis cluster failover
- Backup failure
- High resource usage

**Subscribe to Notifications**:
```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:ap-southeast-1:ACCOUNT_ID:streamingapp-jenkins-notifications \
  --protocol email \
  --notification-endpoint your-email@example.com \
  --region ap-southeast-1 \
  --profile siraj
```

### CloudWatch Dashboards

View health metrics:
```bash
# List available metrics
aws cloudwatch list-metrics \
  --namespace AWS/EC2 \
  --region ap-southeast-1 \
  --profile siraj \
  --query 'Metrics[?contains(Dimensions[0].Value, `jenkins`)]'
```

---

## Cost Optimization

### Storage Lifecycle
- **Days 0-30**: S3 Standard ($0.023/GB/month)
- **Days 31-365**: Glacier ($0.004/GB/month)
- **Auto-delete**: After 365 days

### EBS Snapshots
- **FastRestore**: 7-day retention ($0.10/GB)
- **Standard Snapshots**: 30-day retention ($0.05/GB)

### Redis
- **Multi-AZ**: Required for HA (+50% cost)
- **Snapshots**: Included in backup schedule
- **Recommendation**: Use cache.t3.micro for dev, cache.t3.small for prod

---

## Runbooks

### Quick Reference: RTO Recovery Times

| Scenario | RTO | Procedure |
|----------|-----|-----------|
| Redis node fails | < 1 min | Automatic failover |
| Jenkins instance fails | 10 min | Terminate + Terraform apply |
| Jenkins config lost | 5 min | Restore from S3 backup |
| EBS volume corrupted | 15 min | Restore from snapshot |
| Region unavailable | 60 min | Redeploy to new region |

---

## Disaster Recovery Checklist

- [ ] Backups verified in last 30 days
- [ ] SNS topic subscribed to email
- [ ] Terraform state backed up
- [ ] EBS snapshots created successfully
- [ ] Redis replication healthy
- [ ] Documentation updated
- [ ] Team trained on recovery procedures

---

## Support & Documentation

- **AWS Backup**: https://docs.aws.amazon.com/aws-backup/
- **DLM Snapshots**: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/snapshot-lifecycle.html
- **ElastiCache HA**: https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/replication.html
- **Terraform State**: https://www.terraform.io/docs/state/

---

**Last Updated**: 2026-09-13  
**Reviewed By**: DevOps Team  
**Next Review**: 2026-10-13
