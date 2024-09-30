# ================================
# Terraform Configuration for EC2 Instance with Packer Support
# ================================

# ================================
# Providers
# ================================
provider "aws" {
  region = var.aws_region
}

# ================================
# Variables
# ================================
variable "aws_region" {
  description = "AWS region to deploy resources."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Type of EC2 instance."
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance."
  type        = string
  default     = "ami-0ebfd941bbafe70c6"  # Replace with your desired AMI
}

variable "key_name" {
  description = "Name of the SSH key pair."
  type        = string
  default     = "terraform_key"
}

variable "ssh_key_path" {
  description = "Path to store the SSH private key."
  type        = string
  default     = "~/.ssh/terraform_key"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_name" {
  description = "Name tag for the VPC."
  type        = string
  default     = "packer_vpc"
}

variable "igw_name" {
  description = "Name tag for the Internet Gateway."
  type        = string
  default     = "packer_igw"
}

variable "subnet_cidr_block" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_name" {
  description = "Name tag for the public subnet."
  type        = string
  default     = "packer_public_subnet"
}

variable "route_table_name" {
  description = "Name tag for the Route Table."
  type        = string
  default     = "packer_public_rt"
}

variable "security_group_name" {
  description = "Name tag for the Security Group."
  type        = string
  default     = "packer_ssh_sg"
}

# ================================
# Data Sources
# ================================

# Fetch the current public IP of the user
data "http" "my_ip" {
  url = "https://api.ipify.org?format=text"
}

# ================================
# Locals
# ================================

locals {
  my_public_ip     = trimspace(data.http.my_ip.response_body)
  ssh_key_dir      = pathexpand("~/.ssh")
  private_key_path = "${local.ssh_key_dir}/terraform_key"
  public_key_path  = "${local.private_key_path}.pub"
}

# ================================
# SSH Key Generation
# ================================

# Generate an SSH private key
resource "tls_private_key" "terraform_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save the private key to the specified path
resource "local_file" "private_key" {
  content         = tls_private_key.terraform_key.private_key_pem
  filename        = local.private_key_path
  file_permission = "0600"
}

# Save the public key to the specified file (for AWS Key Pair)
resource "local_file" "public_key" {
  content         = tls_private_key.terraform_key.public_key_openssh
  filename        = local.public_key_path
  file_permission = "0644"
}

# ================================
# AWS Key Pair
# ================================

resource "aws_key_pair" "terraform_key" {
  key_name   = var.key_name
  public_key = local_file.public_key.content

  # Ensure the public key file is created before attaching
  depends_on = [local_file.public_key]
}

# ================================
# VPC and Networking Resources
# ================================

# Create a new VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc_name
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = var.igw_name
  }
}

# Create a public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_block
  map_public_ip_on_launch = true  # Enable public IP assignment

  tags = {
    Name = var.subnet_name
  }
}

# Create a route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = var.route_table_name
  }
}

# Create a default route to the Internet Gateway
resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id

  depends_on = [aws_internet_gateway.gw]
}

# Associate the route table with the public subnet
resource "aws_route_table_association" "public_subnet" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ================================
# Security Group
# ================================

resource "aws_security_group" "allow_ssh" {
  name        = var.security_group_name
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${local.my_public_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.security_group_name
  }
}

# ================================
# IAM Role and Policy for Packer
# ================================

resource "aws_iam_role" "packer_role" {
  name = "PackerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "PackerRole"
  }
}

resource "aws_iam_policy" "packer_policy" {
  name        = "PackerPolicy"
  description = "Policy to allow Packer to create and manage AMIs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = [
          "ec2:CreateKeyPair",
          "ec2:DeleteKeyPair",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeVolumes",
          "ec2:StopInstances",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:CreateTags",
          "ec2:CreateImage",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeRegions",
          "ec2:DeleteSecurityGroup",
          "ec2:CreateSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "iam:PassRole",
          "sts:GetCallerIdentity"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })

  tags = {
    Name = "PackerPolicy"
  }
}

resource "aws_iam_role_policy_attachment" "packer_policy_attach" {
  role       = aws_iam_role.packer_role.name
  policy_arn = aws_iam_policy.packer_policy.arn
}

resource "aws_iam_instance_profile" "packer_profile" {
  name = "PackerInstanceProfile"
  role = aws_iam_role.packer_role.name
}

# ================================
# EC2 Instance
# ================================

resource "aws_instance" "packer_instance" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.terraform_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.packer_profile.name
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]
  subnet_id              = aws_subnet.public.id

  # User data to install Packer and AWS CLI
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y packer awscli
              EOF

  tags = {
    Name = "PackerInstance"
  }

  depends_on = [
    aws_key_pair.terraform_key,
    aws_security_group.allow_ssh,
    aws_iam_role_policy_attachment.packer_policy_attach,
    aws_route.default_route,
    aws_route_table_association.public_subnet
  ]
}

# ================================
# Outputs
# ================================

output "instance_public_ip" {
  description = "The public IP of the EC2 instance."
  value       = aws_instance.packer_instance.public_ip
}

output "ssh_private_key_path" {
  description = "Path to the SSH private key."
  value       = local.private_key_path
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "The ID of the Subnet"
  value       = aws_subnet.public.id
}