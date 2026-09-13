# IAM Role for Jenkins EC2 instance to push to ECR
resource "aws_iam_role" "jenkins_ecr_role" {
  name = "streamingapp-jenkins-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "streamingapp-jenkins-ecr-role"
    Project = "StreamingApp"
  }
}

# IAM Policy for ECR access
resource "aws_iam_role_policy" "jenkins_ecr_policy" {
  name = "streamingapp-jenkins-ecr-policy"
  role = aws_iam_role.jenkins_ecr_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuthToken"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPushImage"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:*:repository/streamingapp-*"
      },
      {
        Sid    = "ECRCreateRepository"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:*:repository/streamingapp-*"
      }
    ]
  })
}

# Instance Profile to attach the role to EC2 instances
resource "aws_iam_instance_profile" "jenkins_ecr_profile" {
  name = "streamingapp-jenkins-ecr-profile"
  role = aws_iam_role.jenkins_ecr_role.name
}

# Output the role ARN for reference
output "jenkins_ecr_role_arn" {
  description = "ARN of the IAM role for Jenkins ECR access"
  value       = aws_iam_role.jenkins_ecr_role.arn
}

output "jenkins_ecr_instance_profile_arn" {
  description = "ARN of the instance profile for attaching to Jenkins EC2"
  value       = aws_iam_instance_profile.jenkins_ecr_profile.arn
}
