output "eks_clusters" {
  description = "EKS cluster parameters"
  value       = { for cluster in module.eks : cluster.cluster_name => { "cluster_ca_certificate" : base64decode(cluster.cluster_certificate_authority_data), "cluster_endpoint" : cluster.cluster_endpoint, "cluster_version" : cluster.cluster_version, "oidc_provider_arn" : cluster.oidc_provider_arn } }
}

output "vpcs" {
  description = "VPC parameters"
  value       = { for name, parameters in module.networking.vpcs : name => parameters }
}
