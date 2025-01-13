output "eks_clusters" {
  description = "EKS cluster parameters"
  value       = { for cluster in module.eks : cluster.cluster_name => { "cluster_ca_certificate" : base64decode(cluster.cluster_certificate_authority_data), "cluster_endpoint" : cluster.cluster_endpoint, "oidc_provider_arn" : cluster.oidc_provider_arn } }
}
