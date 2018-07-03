terraform {
  backend "s3" {
    key = "wordpress.tfstate"
  }

  required_version = ">= 0.11.7"
}

provider "aws" {
  region = "${var.region}"
}

module "eks" {
  source           = "eks"
  cluster_name     = "${var.cluster_name}"
  node_max         = "${var.node_max}"
  node_min         = "${var.node_min}"
  node_type        = "${var.node_type}"
  k8s_access_cidrs = "${var.k8s_access_cidrs}"
  available_zones  = "${var.available_zones}"
}

module "wordpress" {
  source              = "wordpress"
  private_subnets     = "${module.eks.private_subnets}"
  vpc_id              = "${module.eks.vpc_id}"
  master_password     = "${var.master_password}"
  node_sg             = "${module.eks.node_sg}"
  cluster_name        = "${module.eks.cluster_name}"
  kubeconfig          = "${module.eks.kubeconfig_file}"
  service_base_domain = "${var.service_base_domain}"
  instance_type       = "${var.instance_type}"
  aurora_instances    = "${var.aurora_instances}"
}
