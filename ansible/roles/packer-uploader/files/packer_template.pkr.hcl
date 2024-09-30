variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_id" {
  type = string
  default = "vpc-01c826afe634e734b"
}

variable "subnet_id" {
  type = string
  default = "subnet-0b080d0599b3524d8"
}



source "amazon-ebs" "amazon_linux" {
  ami_name      = "packer-amazon-linux-2-{{timestamp}}"
  instance_type = "t2.micro"
  region        = var.aws_region

  # Source AMI using a filter
  source_ami_filter {
    filters = {
      virtualization-type = "hvm"
      name                = "amzn2-ami-hvm-*-x86_64-gp2"
      root-device-type    = "ebs"
    }
    owners      = ["137112412989"]  # Amazon
    most_recent = true
  }

  # SSH configurations
  ssh_username         = "ec2-user"


  # Networking configurations
  subnet_id                  = var.subnet_id
  associate_public_ip_address = true
  vpc_id                     = var.vpc_id

  # Tags
  tags = {
    Name = "Packer Amazon Linux 2"
  }
}

build {
  sources = ["source.amazon-ebs.amazon_linux"]

  provisioner "shell" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y awscli unzip curl"
    ]
  }

  # Additional provisioners (e.g., Ansible) can be added here
}