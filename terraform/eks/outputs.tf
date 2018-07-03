output "kubeconfig_file" {
  value = "${local_file.kubeconfig.filename}"
}

output "private_subnets" {
  value = ["${aws_subnet.wordpress.*.id}"]
}

output "vpc_id" {
  value = "${aws_vpc.wordpress.id}"
}

output "node_sg" {
  value = "${aws_security_group.wordpress-node.id}"
}

output "cluster_name" {
  value = "${aws_eks_cluster.wordpress.name}"
}
