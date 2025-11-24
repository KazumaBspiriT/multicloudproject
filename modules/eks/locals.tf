locals {
  kubeconfig = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = module.eks_cluster.cluster_name
      cluster = {
        server                     = module.eks_cluster.cluster_endpoint
        certificate-authority-data = module.eks_cluster.cluster_certificate_authority_data
      }
    }]
    contexts = [{
      name = module.eks_cluster.cluster_name
      context = {
        cluster = module.eks_cluster.cluster_name
        user    = module.eks_cluster.cluster_name
      }
    }]
    "current-context" = module.eks_cluster.cluster_name
    users = [{
      name = module.eks_cluster.cluster_name
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1"
          command    = "aws"
          args       = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
        }
      }
    }]
  })
}
