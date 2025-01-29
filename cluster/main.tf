module "networking" {
  source = "./modules/networking"
  vpc_parameters = {
    dcoppa = {
      cidr_block = "10.0.0.0/16"
    }
  }
  subnet_parameters = {
    dcoppa_pub_subnet1 = {
      cidr_block              = "10.0.1.0/24"
      vpc_name                = "dcoppa"
      availability_zone       = "eu-central-1a"
      map_public_ip_on_launch = true
      tags = {
        "subnet-type" = "public"
      }
    }
    dcoppa_pub_subnet2 = {
      cidr_block              = "10.0.2.0/24"
      vpc_name                = "dcoppa"
      availability_zone       = "eu-central-1b"
      map_public_ip_on_launch = true
      tags = {
        "subnet-type" = "public"
      }
    }
    dcoppa_pub_subnet3 = {
      cidr_block              = "10.0.3.0/24"
      vpc_name                = "dcoppa"
      availability_zone       = "eu-central-1c"
      map_public_ip_on_launch = true
      tags = {
        "subnet-type" = "public"
      }
    }
    dcoppa_priv_subnet1 = {
      cidr_block        = "10.0.4.0/24"
      vpc_name          = "dcoppa"
      availability_zone = "eu-central-1a"
      tags = {
        "subnet-type" = "private"
      }
    }
    dcoppa_priv_subnet2 = {
      cidr_block        = "10.0.5.0/24"
      vpc_name          = "dcoppa"
      availability_zone = "eu-central-1b"
      tags = {
        "subnet-type" = "private"
      }
    }
    dcoppa_priv_subnet3 = {
      cidr_block        = "10.0.6.0/24"
      vpc_name          = "dcoppa"
      availability_zone = "eu-central-1c"
      tags = {
        "subnet-type" = "private"
      }
    }
  }
  igw_parameters = {
    dcoppa_igw = {
      vpc_name = "dcoppa"
    }
  }
  ngw_parameters = {
    dcoppa_ngw_a = {
      eip_name    = "dcoppa_eip1"
      subnet_name = "dcoppa_pub_subnet1"
    }
    dcoppa_ngw_b = {
      eip_name    = "dcoppa_eip2"
      subnet_name = "dcoppa_pub_subnet2"
    }
    dcoppa_ngw_c = {
      eip_name    = "dcoppa_eip3"
      subnet_name = "dcoppa_pub_subnet3"
    }
  }
  rt_parameters = {
    dcoppa_pub_rt = {
      vpc_name = "dcoppa"
      routes = [{
        cidr_block = "0.0.0.0/0"
        use_igw    = true
        gateway_id = "dcoppa_igw"
        }
      ]
    }
    dcoppa_priv_rt_subnet1 = {
      vpc_name = "dcoppa"
      routes = [{
        cidr_block = "0.0.0.0/0"
        use_ngw    = true
        gateway_id = "dcoppa_ngw_a"
        }
      ]
    }
    dcoppa_priv_rt_subnet2 = {
      vpc_name = "dcoppa"
      routes = [{
        cidr_block = "0.0.0.0/0"
        use_ngw    = true
        gateway_id = "dcoppa_ngw_b"
        }
      ]
    }
    dcoppa_priv_rt_subnet3 = {
      vpc_name = "dcoppa"
      routes = [{
        cidr_block = "0.0.0.0/0"
        use_ngw    = true
        gateway_id = "dcoppa_ngw_c"
        }
      ]
    }
  }
  rt_association_parameters = {
    dcoppa_rt_association_pub_subnet1 = {
      subnet_name = "dcoppa_pub_subnet1"
      rt_name     = "dcoppa_pub_rt"
    }
    dcoppa_rt_association_pub_subnet2 = {
      subnet_name = "dcoppa_pub_subnet2"
      rt_name     = "dcoppa_pub_rt"
    }
    dcoppa_rt_association_pub_subnet3 = {
      subnet_name = "dcoppa_pub_subnet3"
      rt_name     = "dcoppa_pub_rt"
    }
    dcoppa_rt_association_priv_subnet1 = {
      subnet_name = "dcoppa_priv_subnet1"
      rt_name     = "dcoppa_priv_rt_subnet1"
    }
    dcoppa_rt_association_priv_subnet2 = {
      subnet_name = "dcoppa_priv_subnet2"
      rt_name     = "dcoppa_priv_rt_subnet2"
    }
    dcoppa_rt_association_priv_subnet3 = {
      subnet_name = "dcoppa_priv_subnet3"
      rt_name     = "dcoppa_priv_rt_subnet3"
    }
  }
}

resource "time_sleep" "this" {
  depends_on      = [module.networking]
  create_duration = "30s"
}

data "aws_subnets" "dcoppa_priv_subnets" {
  depends_on = [module.networking, time_sleep.this]
  for_each   = module.networking.vpcs
  filter {
    name   = "vpc-id"
    values = [each.value.id]
  }
  filter {
    name   = "tag:vpc-id"
    values = [each.value.id]
  }
  filter {
    name   = "tag:subnet-type"
    values = ["private"]
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.31.6"

  for_each = module.networking.vpcs

  cluster_name      = "${each.key}-eks"
  cluster_ip_family = "ipv4"
  cluster_version   = "1.32"

  cluster_enabled_log_types = ["api", "authenticator", "audit", "scheduler", "controllerManager"]

  cluster_endpoint_private_access          = true
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = each.value.id
  subnet_ids = data.aws_subnets.dcoppa_priv_subnets[each.key].ids

  eks_managed_node_group_defaults = {
    ami_type             = "AL2023_x86_64_STANDARD"
    force_update_version = true
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
    instance_types = ["t3a.medium"]
  }

  eks_managed_node_groups = {
    "${each.key}-ng" = {
      name         = "${each.key}-ng"
      subnet_ids   = data.aws_subnets.dcoppa_priv_subnets[each.key].ids
      min_size     = 1
      max_size     = 1
      desired_size = 1
      labels = {
        "static_node" = "true"
      }
      taints = [
        {
          key    = "static_node"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }

  cluster_addons = {
    coredns = {
      addon_version = "v1.11.4-eksbuild.2"
      configuration_values = jsonencode({
        autoScaling = {
          "enabled"     = true
          "minReplicas" = 2
          "maxReplicas" = 10
        }
        tolerations = [
          {
            "key" : "static_node",
            "operator" : "Exists",
            "effect" : "NoSchedule"
          },
          {
            "key" : "CriticalAddonsOnly",
            "operator" : "Exists"
          },
          {
            "effect" : "NoSchedule",
            "key" : "node-role.kubernetes.io/control-plane"
          }
        ]
      })
    }
    kube-proxy = {
      addon_version = "v1.32.0-eksbuild.2"
    }
    vpc-cni = {
      addon_version = "v1.19.2-eksbuild.1"
    }
  }
}
