variable "master_username" {
  description = "MySQL master username"
  default     = "wordpress"
}

variable "aurora_instances" {
  description = "How many Aurora instances to deploy"
}

variable "master_password" {
  description = "MySQL master password"
}

variable "cluster_name" {
  description = "EKS cluster name"
}

variable "instance_type" {
  description = "Aurora instance type"
}

variable "private_subnets" {
  description = "List of private subnets in which to deploy Aurora"
  type        = "list"
}

variable "node_sg" {
  description = "Node security group ID used for Aurora whitelisting"
}

variable "vpc_id" {
  description = "VPC ID to deploy in"
}

variable "service_base_domain" {
  description = "Base domain name to use for the service e.g example.com"
}

variable "kubeconfig" {
  description = "Path to kubeconfig file"
}
