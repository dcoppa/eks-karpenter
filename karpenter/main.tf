module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.31.6"

  for_each = data.terraform_remote_state.cluster.outputs.eks_clusters

  cluster_name = each.key

  enable_irsa            = true
  irsa_oidc_provider_arn = each.value.oidc_provider_arn

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

resource "helm_release" "karpenter" {
  for_each         = data.terraform_remote_state.cluster.outputs.eks_clusters
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.1.2"
  namespace        = "karpenter"
  create_namespace = true
  force_update     = true
  wait             = true
  set {
    name  = "replicas"
    value = 1
  }
  set {
    name  = "settings.clusterEndpoint"
    value = data.terraform_remote_state.cluster.outputs.eks_clusters[each.key].cluster_endpoint
  }
  set {
    name  = "settings.clusterName"
    value = each.key
  }
  set {
    name  = "settings.interruptionQueue"
    value = module.karpenter[each.key].queue_name
  }
  values = [
    <<EOT
    nodeSelector:
      "static_node": "true"
    serviceAccount:
      annotations:
        "eks.amazonaws.com/role-arn": "${module.karpenter[each.key].iam_role_arn}"
    tolerations:
    - key: "static_node"
      operator: "Exists"
      effect: "NoSchedule"
    EOT
  ]
  depends_on = [module.karpenter]
}

resource "kubectl_manifest" "karpenter_node_class" {
  for_each   = data.terraform_remote_state.cluster.outputs.eks_clusters
  yaml_body  = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiFamily: AL2023
      amiSelectorTerms:
        - name: "amazon-eks-node-al2023-x86_64-standard-${each.value.cluster_version}-*"
      role: ${module.karpenter[each.key].node_iam_role_name}
      securityGroupSelectorTerms:
        - tags:
            "kubernetes.io/cluster/${each.key}": "owned"
            "Name": "${each.key}-node"
      subnetSelectorTerms:
        - tags:
            "vpc-id": "${data.terraform_remote_state.cluster.outputs.vpcs[replace(each.key, "/-eks$/", "")].id}"
            "subnet-type": "private"
  YAML
  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body  = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 1m
      template:
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r", "t"]
            - key: "karpenter.k8s.aws/instance-family"
              operator: NotIn
              values: ["t2"]
            - key: karpenter.k8s.aws/instance-size
              operator: In
              values: ["small", "medium", "large", "xlarge", "2xlarge", "4xlarge", "8xlarge", "12xlarge", "16xlarge"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
  YAML
  depends_on = [kubectl_manifest.karpenter_node_class]
}

resource "kubernetes_cluster_role" "costsaver" {
  metadata {
    name = "costsaver"
  }
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "patch", "delete", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["nodes/status"]
    verbs      = ["patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "delete"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/eviction"]
    verbs      = ["create"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["daemonsets"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["karpenter.sh"]
    resources  = ["nodepools"]
    verbs      = ["get", "list", "patch"]
  }
}

resource "kubernetes_service_account" "costsaver" {
  metadata {
    name      = "costsaver"
    namespace = "karpenter"
  }
  depends_on = [helm_release.karpenter]
}

resource "kubernetes_cluster_role_binding" "costsaver" {
  metadata {
    name = "costsaver"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "costsaver"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "costsaver"
    namespace = "karpenter"
  }
  depends_on = [kubernetes_cluster_role.costsaver, kubernetes_service_account.costsaver]
}

resource "kubernetes_cron_job_v1" "costsaver" {
  for_each = { off = "0 7 * * 1-5", on = "0 20 * * *" }
  metadata {
    name      = "costsaver-${each.key}"
    namespace = "karpenter"
  }
  spec {
    concurrency_policy            = "Replace"
    failed_jobs_history_limit     = 5
    schedule                      = each.value
    timezone                      = "Europe/Berlin"
    starting_deadline_seconds     = 10
    successful_jobs_history_limit = 10
    job_template {
      metadata {}
      spec {
        ttl_seconds_after_finished = 10
        template {
          metadata {}
          spec {
            container {
              name    = "kubectl-dash"
              image   = "dcoppa/kubectl-dash:v1.32.1"
              command = [each.key]
              security_context {
                allow_privilege_escalation = "false"
                read_only_root_filesystem  = "true"
                run_as_group               = "65532"
                run_as_non_root            = "true"
                run_as_user                = "65532"
              }
            }
            node_selector = {
              "static_node" = "true"
            }
            security_context {
              fs_group        = "0"
              run_as_group    = "65532"
              run_as_non_root = "true"
              run_as_user     = "65532"
            }
            service_account_name = "costsaver"
            toleration {
              effect   = "NoSchedule"
              key      = "static_node"
              operator = "Exists"
            }
          }
        }
      }
    }
  }
  lifecycle {
    create_before_destroy = false
  }
  depends_on = [kubernetes_cluster_role_binding.costsaver]
}
