terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Default VPC
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group for PKI server
resource "aws_security_group" "pki_server" {
  name        = "acme-pki-ec2-sg"
  description = "Security group for PKI server (Path B)"
  vpc_id      = data.aws_vpc.default.id
  
  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
    description = "SSH access"
  }
  
  # HTTPS for API
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS API access"
  }
  
  # HTTP for CRL/API
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP for CRL distribution and API"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }
  
  tags = merge(var.tags, {
    Name = "ACME-PKI-EC2-SG"
  })
}

# IAM role for EC2
resource "aws_iam_role" "pki_server" {
  name = "acme-pki-ec2-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

# SSM policy for Session Manager access
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.pki_server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "pki_server" {
  name = "acme-pki-ec2-profile"
  role = aws_iam_role.pki_server.name
}

# EC2 instance for PKI
resource "aws_instance" "pki_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.pki_server.id]
  iam_instance_profile   = aws_iam_instance_profile.pki_server.name
  
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }
  
  # User data now only sets up Intermediate CA (not Root)
  user_data = templatefile("${path.module}/../scripts/user_data.sh", {
    organization     = var.organization_name
    org_unit         = var.organizational_unit
    country          = var.country
    state            = var.state
    locality         = var.locality
    inter_validity   = var.intermediate_ca_validity_days
    sub_validity     = var.subscriber_cert_validity_days
  })
  
  tags = merge(var.tags, {
    Name = "ACME-PKI-EC2-Server"
  })
}

# Elastic IP for stable endpoint
resource "aws_eip" "pki_server" {
  instance = aws_instance.pki_server.id
  domain   = "vpc"
  
  tags = merge(var.tags, {
    Name = "ACME-PKI-EC2-EIP"
  })
}
