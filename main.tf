terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.21.0"
    }
  }
}

variable "project_name" {
  type    = string
  default = "myboxfuse"
}

variable "public_key" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

provider "aws" {
  # Configuration options
}

resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.public_key)
}

resource "aws_security_group" "default" {
  name        = "${var.project_name}-default"
  description = "Allow SSH inbound and all outbound traffic"

  ingress {
    description      = "SSH"
    from_port        = 0
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "Allow all"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.project_name}-default"
  }
}

resource "aws_security_group" "tomcat" {
  name        = "${var.project_name}-tomcat"
  description = "Allow Tomcat inbound traffic on port 8080"

  ingress {
    description      = "Tomcat"
    from_port        = 0
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "builder" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t3.micro"
  key_name        = aws_key_pair.deployer.key_name
  security_groups = [aws_security_group.default.name]

  tags = {
    Name = "${var.project_name}-builder"
  }

  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ubuntu -e 'build_ip=${self.public_ip}' -e 'run_ip=${self.public_ip}' --tags build main.yaml"
  }
}

resource "aws_instance" "runner" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t3.micro"
  key_name        = aws_key_pair.deployer.key_name
  security_groups = [aws_security_group.default.name, aws_security_group.tomcat.name]

  tags = {
    Name = "${var.project_name}-runner"
  }

  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ubuntu -e 'build_ip=${self.public_ip}' -e 'run_ip=${self.public_ip}' --tags run main.yaml"
  }
}