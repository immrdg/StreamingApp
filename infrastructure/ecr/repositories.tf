terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

variable "aws_region" {
  type        = string
  description = "AWS region for ECR repositories."
  default     = "ap-southeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use."
  type        = string
  default     = "siraj"
}

variable "repositories" {
  type        = set(string)
  description = "ECR repositories required by StreamingApp."
  default = [
    "streamingapp-auth",
    "streamingapp-streaming",
    "streamingapp-admin",
    "streamingapp-chat",
    "streamingapp-frontend",
  ]
}

resource "aws_ecr_repository" "streamingapp" {
  for_each = var.repositories

  name                 = each.value
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

output "repository_urls" {
  value = {
    for name, repo in aws_ecr_repository.streamingapp : name => repo.repository_url
  }
}
