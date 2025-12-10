terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

variable "aws_region" {
  description = "AWS Region to deploy resources"
  default     = "eu-central-1"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "BiddingExchangeMVP"
      Owner   = "StudentTeam"
      ManagedBy = "Terraform"
    }
  }
}
