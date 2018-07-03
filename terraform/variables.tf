variable "region" {
  description = "AWS region in which to deploy resources"
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the cluster to provision (will be prefixed with terraform env)"
}

variable "master_password" {
  description = "MySQL master password"
}

variable "service_base_domain" {
  description = "Base domain name to use for the service e.g example.com"
  default     = "alexla.st"
}

variable "node_type" {
  description = "Node instance type"
  default     = "m4.large"
}

variable "node_min" {
  description = "Minimum node count"
  default     = 1
}

variable "node_max" {
  description = "Maximum node count"
  default     = 2
}

variable "instance_type" {
  description = "Aurora instance type"
  default     = "db.t2.small"
}

variable "aurora_instances" {
  description = "How many Aurora instances to deploy"
  default     = 1
}

variable "available_zones" {
  description = "Zones my account can deploy EKS in"
  type        = "list"
  default     = ["us-east-1a", "us-east-1c"]
}

variable "k8s_access_cidrs" {
  description = "List of CIDR ranges to allow access to the K8s API"
  type        = "list"
  default     = [
    "82.30.216.220/32"
  ]
}