terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  description = "AWS Region to deploy resources"
  default     = "eu-central-1"
}

variable "enable_firehose" {
  description = "Enable Kinesis Firehose for analytics (requires AWS subscription)"
  type        = bool
  default     = false
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
