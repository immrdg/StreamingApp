provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_ssm_parameter" "amazon_linux_2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  jenkins_agent_ami = var.jenkins_agent_ami != "" ? var.jenkins_agent_ami : data.aws_ssm_parameter.amazon_linux_2023_ami.value
}

resource "aws_iam_role" "jenkins" {
  name = "${var.name_prefix}-jenkins-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy" "ssm_file_transfer" {
  name = "${var.name_prefix}-jenkins-ssm-s3-transfer"
  role = aws_iam_role.jenkins.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:GetEncryptionConfiguration"
      ]
      Resource = "arn:aws:s3:::${var.ssm_transfer_bucket}/*"
    }]
  })
}

# Lets the Jenkins EC2 plugin launch/terminate/tag build agents on demand.
resource "aws_iam_role_policy" "ec2_cloud_agents" {
  name = "${var.name_prefix}-jenkins-ec2-cloud-agents"
  role = aws_iam_role.jenkins.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Ec2AgentLifecycle"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeImages",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeSpotInstanceRequests",
          "ec2:CreateTags",
          "ec2:GetConsoleOutput"
        ]
        Resource = "*"
      },
      {
        Sid      = "PassAgentRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.jenkins_agent.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.name_prefix}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

# --- EC2 cloud agents (build nodes launched on demand by the EC2 plugin) ---

resource "aws_iam_role" "jenkins_agent" {
  name = "${var.name_prefix}-jenkins-agent-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_agent_ssm" {
  role       = aws_iam_role.jenkins_agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "jenkins_agent_ecr" {
  role       = aws_iam_role.jenkins_agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_instance_profile" "jenkins_agent" {
  name = "${var.name_prefix}-jenkins-agent-profile"
  role = aws_iam_role.jenkins_agent.name
}

# SSH key pair for Jenkins controller access
resource "tls_private_key" "jenkins_controller" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "jenkins_controller" {
  key_name   = "${var.name_prefix}-jenkins-controller"
  public_key = tls_private_key.jenkins_controller.public_key_openssh
}

resource "local_sensitive_file" "jenkins_controller_private_key" {
  filename        = "${path.module}/generated/jenkins-controller.pem"
  content         = tls_private_key.jenkins_controller.private_key_pem
  file_permission = "0600"
}

# SSH key pair used by the EC2 plugin to bootstrap agent nodes (JNLP over SSH).
resource "tls_private_key" "jenkins_agent" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "jenkins_agent" {
  key_name   = "${var.name_prefix}-jenkins-agent"
  public_key = tls_private_key.jenkins_agent.public_key_openssh
}

resource "local_sensitive_file" "jenkins_agent_private_key" {
  filename        = "${path.module}/generated/jenkins-agent.pem"
  content         = tls_private_key.jenkins_agent.private_key_pem
  file_permission = "0600"
}

resource "aws_security_group" "jenkins_agent" {
  name        = "${var.name_prefix}-jenkins-agent"
  description = "Jenkins EC2 build agents - SSH only from the Jenkins controller"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "SSH from Jenkins controller"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }

  egress {
    description = "Outbound package and AWS API access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-jenkins-agent"
  }
}

resource "aws_security_group" "jenkins" {
  name        = "${var.name_prefix}-jenkins"
  description = "Allow approved users to reach the Jenkins web interface"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH access for administration"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.jenkins_allowed_cidrs
  }

  ingress {
    description = "Jenkins web interface"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.jenkins_allowed_cidrs
  }

  egress {
    description = "Outbound package, source-control, and AWS API access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-jenkins"
  }
}

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ssm_parameter.amazon_linux_2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true
  key_name                    = aws_key_pair.jenkins_controller.key_name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
    encrypted   = true
  }

  tags = {
    Name    = "${var.name_prefix}-jenkins"
    Project = "StreamingApp"
    Role    = "Jenkins"
    Managed = "terraform"
  }
}
