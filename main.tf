terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.21.0"
    }
  }
}

variable "project_name" {
  type = string
  default = "myboxfuse"
}

variable "public_key" {
  type = string
  default = "~/.ssh/id_rsa.pub"
}

variable "private_key" {
  type = string
  default = "~/.ssh/id_rsa"
}

provider "aws" {
  # Configuration options
}

resource "aws_s3_bucket" "bucket" {
  bucket = "${var.project_name}-bucket"
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  bucket = aws_s3_bucket.bucket.bucket
  acl    = "public-read"
}

resource "aws_s3_object" "index_page" {
  bucket = aws_s3_bucket.bucket.bucket
  key    = "index.html"
  source = "files/index.html"
  acl    = "public-read"
  etag   = filemd5("files/index.html")
}

resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.public_key)
}

resource "aws_security_group" "allow_ssh" {
  name        = "${var.project_name}-ssh"
  description = "Allow SSH inbound traffic"

  ingress {
    description      = "SSH"
    from_port        = 0
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_security_group" "allow_http" {
  name        = "${var.project_name}-http"
  description = "Allow HTTP inbound traffic"

  ingress {
    description      = "HTTP"
    from_port        = 0
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_http"
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

resource "aws_instance" "build" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t3.micro"
  key_name        = "${var.project_name}-key"
  security_groups = ["${var.project_name}-ssh", "${var.project_name}-http"]

  user_data = <<-EOF
    #!/bin/bash
    set -ex
    sudo apt update -y && \
      sudo apt install nginx -y && \
      sudo wget https://myboxfuse-bucket.s3.eu-north-1.amazonaws.com/index.html -O /var/www/html/index.nginx-debian.html
  EOF

  tags = {
    Name = "Builder"
  }

  depends_on = [aws_s3_bucket.bucket, aws_s3_object.index_page, aws_s3_bucket_acl.bucket_acl]
}

output "web_page_address" {
  value = "http://${aws_instance.build.public_ip}"
}