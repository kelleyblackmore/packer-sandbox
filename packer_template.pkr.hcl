packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "packer-example-{{timestamp}}"
  instance_type = "t2.micro"
  region        = var.aws_region
  source_ami_filter {
    filters = {
      virtualization-type = "hvm"
      name                = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
      root-device-type    = "ebs"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }
  ssh_username = "ubuntu"
  ssh_keypair  = var.ssh_key_name
  ssh_private_key_file = var.ssh_private_key_path

  tags = {
    Name = "Packer Example AMI"
  }
}

build {
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "ansible" {
    playbook_file = "packer_playbook.yml"

    extra_arguments = [
      "--extra-vars",
      "packer_build=true"
    ]
  }
}