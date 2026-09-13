variable "aws_region" {
  description = "AWS region for the EKS cluster."
  type        = string
  default     = "ap-southeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use."
  type        = string
  default     = "siraj"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "streamingapp-eks"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes control-plane version."
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "CIDR block for the EKS VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "availability_zone_count" {
  description = "Number of availability zones to use."
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zone_count >= 2
    error_message = "Use at least two availability zones for EKS."
  }
}

variable "enable_nat_gateway" {
  description = "Create a single NAT gateway for private worker-node subnets."
  type        = bool
  default     = true
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "node_disk_size_gb" {
  description = "Worker node root volume size in GiB."
  type        = number
  default     = 30
}

variable "allowed_cluster_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Common tags applied to created AWS resources."
  type        = map(string)
  default = {
    Project = "StreamingApp"
    Managed = "terraform"
  }
}
