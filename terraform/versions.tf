terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # For production, configure an S3 backend after creating the bootstrap bucket.
  # backend "s3" {
  #   bucket         = "CHANGE-ME-terraform-state"
  #   key            = "devshop/terraform.tfstate"
  #   region         = "ap-south-1"
  #   use_lockfile   = true
  # }
}
