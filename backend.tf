
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket91"
    region         = "ap-south-1"
    key            = "awss3-github-actions/terraform.tfstate"
    encrypt = true
  }
  required_version = ">=1.5.1"
  required_providers {
    aws = {
      version = ">= 2.7.0"
      source = "hashicorp/aws"
    }
  }
}
