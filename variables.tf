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
