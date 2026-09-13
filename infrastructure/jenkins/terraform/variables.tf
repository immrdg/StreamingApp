variable "aws_region" {
  description = "AWS region for the Jenkins instance."
  type        = string
  default     = "ap-southeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use."
  type        = string
  default     = "siraj"
}

variable "name_prefix" {
  description = "Prefix used to name AWS resources."
  type        = string
  default     = "streamingapp"
}

variable "instance_type" {
  description = "EC2 instance type. t3.medium meets Jenkins' minimum practical memory requirement."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size_gb" {
  description = "Size of the encrypted gp3 root volume in GiB."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size_gb >= 20
    error_message = "The Jenkins root volume must be at least 20 GiB."
  }
}

variable "jenkins_allowed_cidrs" {
  description = "IPv4 CIDRs permitted to access Jenkins on TCP/8080. Use your public IP with /32."
  type        = list(string)

  # validation {
  #   condition     = length(var.jenkins_allowed_cidrs) > 0 && !contains(var.jenkins_allowed_cidrs, "0.0.0.0/0")
  #   error_message = "Specify at least one restricted CIDR; 0.0.0.0/0 is not permitted."
  # }
  default = ["0.0.0.0/0"]
}

variable "ssm_transfer_bucket" {
  description = "Name of the S3 bucket used by the Ansible aws_ssm connection plugin for file transfer."
  type        = string
}

variable "jenkins_agent_ami" {
  description = "AMI for EC2 cloud build agents. Defaults to the latest Amazon Linux 2023 image."
  type        = string
  default     = ""
}

variable "jenkins_agent_instance_types" {
  description = "Instance types the EC2 plugin may launch as build agents."
  type        = list(string)
  default     = ["t3.small", "c7i-flex.large"]
}

variable "jenkins_agent_max_total_instances" {
  description = "Maximum number of EC2 agent instances the Jenkins EC2 cloud may run concurrently."
  type        = number
  default     = 3
}

variable "jenkins_agent_min_idle_instances" {
  description = "Minimum number of idle EC2 agent instances kept warm at all times (per template)."
  type        = number
  default     = 1
}

# ====================================================================
# BACKUP & FAILOVER VARIABLES
# ====================================================================

variable "redis_engine_version" {
  description = "Redis engine version for session persistence"
  type        = string
  default     = "7.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.redis_engine_version))
    error_message = "Redis engine version must be in format X.Y (e.g., 7.1)"
  }
}

variable "redis_node_type" {
  description = "ElastiCache node type for Jenkins session cache"
  type        = string
  default     = "cache.t3.micro"

  validation {
    condition     = can(regex("^cache\\.", var.redis_node_type))
    error_message = "Redis node type must start with 'cache.'"
  }
}

variable "redis_num_replicas" {
  description = "Number of replica nodes for Redis high availability (primary + replicas)"
  type        = number
  default     = 2

  validation {
    condition     = var.redis_num_replicas >= 1 && var.redis_num_replicas <= 5
    error_message = "Redis replicas must be between 1 and 5"
  }
}

variable "redis_snapshot_retention_days" {
  description = "Number of days to retain Redis snapshots"
  type        = number
  default     = 35

  validation {
    condition     = var.redis_snapshot_retention_days >= 1 && var.redis_snapshot_retention_days <= 35
    error_message = "Redis snapshot retention must be between 1 and 35 days"
  }
}

variable "enable_jenkins_backup_email" {
  description = "Enable email notifications for backup events"
  type        = bool
  default     = true
}

variable "backup_email_address" {
  description = "Email address for backup and failover notifications"
  type        = string
  default     = ""
}
