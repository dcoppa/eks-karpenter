locals {
  cluster_name = "dcoppa-eks"
}

terraform {
  required_version = "~> 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.83.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.17.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "= 2.1.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "= 2.35.1"
    }
  }
}

data "terraform_remote_state" "cluster" {
  backend = "s3"
  config = {
    bucket         = "terraform-state-dcoppa"
    key            = "terraform-dcoppa-cluster.state"
    dynamodb_table = "terraform-state-dcoppa-lock"
    region         = "eu-central-1"
  }
}

data "aws_eks_cluster_auth" "auth" {
  for_each = data.terraform_remote_state.cluster.outputs.eks_clusters
  name     = each.key
}

provider "aws" {
  region = "eu-central-1"
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.cluster.outputs.eks_clusters[local.cluster_name].cluster_endpoint
    cluster_ca_certificate = data.terraform_remote_state.cluster.outputs.eks_clusters[local.cluster_name].cluster_ca_certificate
    token                  = data.aws_eks_cluster_auth.auth[local.cluster_name].token
  }
}

provider "kubectl" {
  host                   = data.terraform_remote_state.cluster.outputs.eks_clusters[local.cluster_name].cluster_endpoint
  cluster_ca_certificate = data.terraform_remote_state.cluster.outputs.eks_clusters[local.cluster_name].cluster_ca_certificate
  token                  = data.aws_eks_cluster_auth.auth[local.cluster_name].token
  load_config_file       = false
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.cluster.outputs.eks_clusters[local.cluster_name].cluster_endpoint
  cluster_ca_certificate = data.terraform_remote_state.cluster.outputs.eks_clusters[local.cluster_name].cluster_ca_certificate
  token                  = data.aws_eks_cluster_auth.auth[local.cluster_name].token
}
