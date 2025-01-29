terraform {
  required_version = "~> 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.83.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "= 0.12.1"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}
