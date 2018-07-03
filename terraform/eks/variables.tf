variable "cluster_name" {
  description = "Name of the cluster to provision (will be prefixed with terraform env)"
}

variable "k8s_access_cidrs" {
  description = "List of CIDR ranges to allow access to the K8s API"
  type        = "list"
}

variable "node_min" {
  description = "Minimum node count"
}

variable "node_max" {
  description = "Maximum node count"
}

variable "node_type" {
  description = "Node instance type"
}

variable "available_zones" {
  description = "Zones my account can deploy EKS in"
  type        = "list"
}
