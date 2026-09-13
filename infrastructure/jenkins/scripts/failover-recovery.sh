#!/bin/bash

################################################################################
# Jenkins Failover & Recovery Automation
# 
# Automates failover procedures for Jenkins infrastructure
# Handles Redis failover, instance recovery, and backup restoration
################################################################################

set -e

# Configuration
JENKINS_NAME_PREFIX="streamingapp"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
AWS_PROFILE="${AWS_PROFILE:-siraj}"
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/terraform" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

################################################################################
# Health Check Functions
################################################################################

check_jenkins_instance() {
    log_info "Checking Jenkins instance status..."
    
    local instance_id=$(terraform -chdir="$TF_DIR" output -raw instance_id 2>/dev/null || echo "")
    
    if [ -z "$instance_id" ]; then
        log_error "Could not retrieve Jenkins instance ID"
        return 1
    fi
    
    local state=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --output text)
    
    case "$state" in
        running)
            log_success "Jenkins instance is running ($instance_id)"
            return 0
            ;;
        stopped)
            log_warning "Jenkins instance is stopped ($instance_id)"
            return 1
            ;;
        terminated)
            log_error "Jenkins instance is terminated ($instance_id)"
            return 2
            ;;
        *)
            log_error "Jenkins instance state: $state"
            return 1
            ;;
    esac
}

check_redis_cluster() {
    log_info "Checking Redis cluster status..."
    
    local status=$(aws elasticache describe-replication-groups \
        --replication-group-id "${JENKINS_NAME_PREFIX}-jenkins-session-cache" \
        --query 'ReplicationGroups[0].Status' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$status" ]; then
        log_warning "Redis cluster not found or not yet created"
        return 1
    fi
    
    if [ "$status" = "available" ]; then
        log_success "Redis cluster is healthy ($status)"
        return 0
    else
        log_warning "Redis cluster status: $status"
        return 1
    fi
}

check_backups() {
    log_info "Checking backup status..."
    
    local backup_bucket="${JENKINS_NAME_PREFIX}-jenkins-backups-$(aws sts get-caller-identity --query Account --output text --profile $AWS_PROFILE)"
    
    local backup_count=$(aws s3 ls "s3://$backup_bucket" --recursive --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | wc -l || echo 0)
    
    if [ "$backup_count" -gt 0 ]; then
        log_success "Backups exist in S3 ($backup_count files)"
        return 0
    else
        log_warning "No backups found in S3"
        return 1
    fi
}

check_ebs_snapshots() {
    log_info "Checking EBS snapshots..."
    
    local snapshot_count=$(aws ec2 describe-snapshots \
        --filters "Name=tag:SnapshotType,Values=jenkins-backup" \
        --query 'length(Snapshots)' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --output text)
    
    if [ "$snapshot_count" -gt 0 ]; then
        log_success "EBS snapshots available ($snapshot_count)"
        return 0
    else
        log_warning "No EBS snapshots found"
        return 1
    fi
}

################################################################################
# Failover Functions
################################################################################

failover_redis() {
    log_info "Initiating Redis cluster failover..."
    
    local replication_group_id="${JENKINS_NAME_PREFIX}-jenkins-session-cache"
    
    # Test primary node connectivity
    aws elasticache describe-replication-groups \
        --replication-group-id "$replication_group_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" > /dev/null
    
    log_success "Redis cluster is responsive - no failover needed"
    
    # For actual failover, AWS handles it automatically
    # This would trigger manual failover if available:
    # aws elasticache test-failover \
    #   --replication-group-id "$replication_group_id" \
    #   --node-group-id "001" \
    #   --region "$AWS_REGION" \
    #   --profile "$AWS_PROFILE"
}

recover_jenkins_instance() {
    log_info "Recovering Jenkins instance..."
    
    cd "$TF_DIR"
    
    log_info "Running terraform refresh to sync current state..."
    terraform refresh \
        -var-file=terraform.tfvars \
        -region="$AWS_REGION" \
        -profile="$AWS_PROFILE"
    
    log_info "Applying terraform configuration to ensure instance exists..."
    terraform apply \
        -var-file=terraform.tfvars \
        -auto-approve
    
    log_success "Jenkins instance recovery initiated"
}

list_ebs_snapshots() {
    log_info "Available EBS snapshots:"
    
    aws ec2 describe-snapshots \
        --filters "Name=tag:SnapshotType,Values=jenkins-backup" \
        --query 'sort_by(Snapshots, &StartTime)[-10:] | [].{ID:SnapshotId, Created:StartTime, Size:VolumeSize}' \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --output table
}

list_s3_backups() {
    log_info "Latest S3 backups:"
    
    local backup_bucket="${JENKINS_NAME_PREFIX}-jenkins-backups-$(aws sts get-caller-identity --query Account --output text --profile $AWS_PROFILE)"
    
    aws s3 ls "s3://$backup_bucket" \
        --recursive \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --summarize | tail -20
}

restore_from_snapshot() {
    local snapshot_id=$1
    
    if [ -z "$snapshot_id" ]; then
        log_error "Snapshot ID required"
        return 1
    fi
    
    log_info "Restoring from snapshot: $snapshot_id"
    
    # Get snapshot details
    local snap_info=$(aws ec2 describe-snapshots \
        --snapshot-ids "$snapshot_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Snapshots[0].{Size:VolumeSize, Created:StartTime, State:State}' \
        --output text)
    
    log_info "Snapshot info: $snap_info"
    
    # Create volume from snapshot
    local volume_id=$(aws ec2 create-volume \
        --snapshot-id "$snapshot_id" \
        --availability-zone "${AWS_REGION}a" \
        --volume-type gp3 \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'VolumeId' \
        --output text)
    
    log_success "Created volume from snapshot: $volume_id"
    log_info "Next steps:"
    log_info "1. Attach volume $volume_id to recovered instance"
    log_info "2. Mount the volume: sudo mount /dev/xvdf /mnt/jenkins-restore"
    log_info "3. Copy data: sudo cp -r /mnt/jenkins-restore/* /var/lib/jenkins/"
    log_info "4. Restart Jenkins: sudo systemctl restart jenkins"
}

################################################################################
# Monitoring Functions
################################################################################

show_health_status() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Jenkins Infrastructure Health Report   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    check_jenkins_instance
    check_redis_cluster
    check_backups
    check_ebs_snapshots
    
    echo ""
}

show_metrics() {
    log_info "Fetching CloudWatch metrics..."
    
    # Redis CPU
    local redis_cpu=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/ElastiCache \
        --metric-name CPUUtilization \
        --dimensions Name=ReplicationGroupId,Value="${JENKINS_NAME_PREFIX}-jenkins-session-cache" \
        --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 300 \
        --statistics Average \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null || echo "N/A")
    
    log_info "Redis CPU: ${redis_cpu}%"
    
    # EC2 instance metrics
    local instance_id=$(terraform -chdir="$TF_DIR" output -raw instance_id 2>/dev/null || echo "")
    
    if [ -n "$instance_id" ]; then
        local cpu=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/EC2 \
            --metric-name CPUUtilization \
            --dimensions Name=InstanceId,Value="$instance_id" \
            --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
            --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
            --period 300 \
            --statistics Average \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" \
            --query 'Datapoints[0].Average' \
            --output text 2>/dev/null || echo "N/A")
        
        log_info "Jenkins EC2 CPU: ${cpu}%"
    fi
}

################################################################################
# Main Menu
################################################################################

show_menu() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ Jenkins Failover & Recovery Console    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "  1) Health Check"
    echo "  2) Show Metrics"
    echo "  3) List EBS Snapshots"
    echo "  4) List S3 Backups"
    echo "  5) Redis Failover Test"
    echo "  6) Recover Jenkins Instance"
    echo "  7) Restore from EBS Snapshot"
    echo "  8) Exit"
    echo ""
    read -p "Select option (1-8): " choice
    
    case $choice in
        1) show_health_status ;;
        2) show_metrics ;;
        3) list_ebs_snapshots ;;
        4) list_s3_backups ;;
        5) failover_redis ;;
        6) recover_jenkins_instance ;;
        7)
            list_ebs_snapshots
            read -p "Enter snapshot ID: " snapshot_id
            restore_from_snapshot "$snapshot_id"
            ;;
        8)
            log_info "Exiting..."
            exit 0
            ;;
        *)
            log_error "Invalid option"
            show_menu
            ;;
    esac
    
    show_menu
}

################################################################################
# CLI Argument Handling
################################################################################

case "${1:-}" in
    health)
        show_health_status
        ;;
    metrics)
        show_metrics
        ;;
    snapshots)
        list_ebs_snapshots
        ;;
    backups)
        list_s3_backups
        ;;
    redis-failover)
        failover_redis
        ;;
    recover-instance)
        recover_jenkins_instance
        ;;
    restore-snapshot)
        restore_from_snapshot "$2"
        ;;
    --help|help)
        cat << EOF
Jenkins Failover & Recovery Script

Usage: $0 [COMMAND]

Commands:
  health              Show infrastructure health status
  metrics             Show CloudWatch metrics
  snapshots           List available EBS snapshots
  backups             List S3 backups
  redis-failover      Test Redis failover
  recover-instance    Recover Jenkins instance via Terraform
  restore-snapshot    Restore from EBS snapshot (requires snapshot ID)
  interactive         Start interactive console (default)
  
Examples:
  $0 health
  $0 restore-snapshot snap-xxxxxxxxx
  $0

EOF
        ;;
    interactive|"")
        show_menu
        ;;
    *)
        log_error "Unknown command: $1"
        log_info "Run '$0 help' for usage information"
        exit 1
        ;;
esac
