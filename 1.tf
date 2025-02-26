provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default     = "ap-south-1"
  description = "AWS Region"
}

variable "aws_key_name" {
  description = "AWS Key Pair Name for SSH Access"
}

variable "ami_id" {
  description = "Ubuntu AMI ID"
}

resource "spacelift_worker_pool" "private_pool" {
  name        = "private-worker-pool"
  description = "Private worker pool for running Terraform jobs"
}

resource "null_resource" "generate_csr" {
  provisioner "local-exec" {
    command = <<EOT
      openssl req -new -newkey rsa:4096 -nodes -keyout worker.key -out worker.csr -subj "/CN=spacelift-worker"
    EOT
  }
}

resource "spacelift_uploaded_certificate" "csr_upload" {
  worker_pool_id       = spacelift_worker_pool.private_pool.id
  certificate_request  = file("worker.csr")
}

resource "aws_instance" "spacelift_worker" {
  ami           = var.ami_id
  instance_type = "t3.small"
  key_name      = var.aws_key_name

  user_data = <<-EOF
              #!/bin/bash
              set -eux
              
              # Update system and install dependencies
              apt update -y
              apt install -y docker.io curl unzip openssl
              
              # Start Docker
              systemctl start docker
              systemctl enable docker
              
              # Save worker key and cert to the system
              echo "${spacelift_uploaded_certificate.csr_upload.signed_certificate}" > /root/worker.crt
              mv worker.key /root/worker.key
              chmod 600 /root/worker.key /root/worker.crt
              
              # Download and install Spacelift worker launcher
              curl -Lo /usr/local/bin/spacelift-launcher https://downloads.spacelift.io/spacelift-launcher-x86_64
              chmod +x /usr/local/bin/spacelift-launcher
              
              # Register the worker
              /usr/local/bin/spacelift-launcher register --worker-pool ${spacelift_worker_pool.private_pool.id} --certificate /root/worker.crt --private-key /root/worker.key
              EOF

  tags = {
    Name = "Spacelift-Worker"
  }
}

resource "aws_iam_role" "worker_role" {
  name = "SpaceliftWorkerRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "SpaceliftWorkerProfile"
  role = aws_iam_role.worker_role.name
}

output "worker_instance_ip" {
  value = aws_instance.spacelift_worker.public_ip
}
