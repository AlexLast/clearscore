#data "aws_availability_zones" "available" {}
# Unfortunately us-east-1b doesn't have capacity, moving to a list of supported AZ's

resource "aws_vpc" "wordpress" {
  cidr_block = "10.0.0.0/16"
  tags       = "${map("Name", "${terraform.env}-${var.cluster_name}",
                      "kubernetes.io/cluster/${terraform.env}-${var.cluster_name}", "shared")
                }"
}

resource "aws_subnet" "wordpress" {
  count             = 2
  #availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  availability_zone = "${var.available_zones[count.index]}"
  cidr_block        = "10.0.${count.index}.0/24"
  vpc_id            = "${aws_vpc.wordpress.id}"
  tags              = "${map(
                            "Name", "${terraform.env}-${var.cluster_name}",
                            "kubernetes.io/cluster/${terraform.env}-${var.cluster_name}", "shared")
                       }"
}

resource "aws_internet_gateway" "wordpress" {
  vpc_id = "${aws_vpc.wordpress.id}"

  tags {
    Name = "${terraform.env}-${var.cluster_name}"
  }
}

resource "aws_route_table" "wordpress" {
  vpc_id = "${aws_vpc.wordpress.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.wordpress.id}"
  }
}

resource "aws_route_table_association" "wordpress" {
  count          = 2
  subnet_id      = "${aws_subnet.wordpress.*.id[count.index]}"
  route_table_id = "${aws_route_table.wordpress.id}"
}

resource "aws_iam_role" "wordpress-control-plane" {
  name               = "${terraform.env}-${var.cluster_name}-control-plane"
  assume_role_policy = "${file("${path.module}/templates/aws/control-plane-role.json")}"
}

resource "aws_iam_role_policy" "wordpress-control-plane-extra-permissions" {
  # Broad permissions, however in the interest of time and lack of EKS documentation I've left it at this for now
  role   = "${aws_iam_role.wordpress-control-plane.name}"
  policy = "${file("${path.module}/templates/aws/control-plane-extra-permissions.json")}"
}

resource "aws_iam_role_policy_attachment" "wordpress-eks-cluster" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.wordpress-control-plane.name}"
}

resource "aws_iam_role_policy_attachment" "wordpress-ecr-read" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.wordpress-node.name}"
}

resource "aws_iam_role_policy_attachment" "wordpress-eks-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.wordpress-control-plane.name}"
}

resource "aws_security_group" "control-plane" {
  name        = "${terraform.env}-${var.cluster_name}-control-plane"
  description = "Cluster communication between worker nodes"
  vpc_id      = "${aws_vpc.wordpress.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Egress node traffic"
  }

  tags {
    Name = "${terraform.env}-${var.cluster_name}"
  }
}

resource "aws_security_group_rule" "k8s-api-ingress" {
  from_port         = 443
  protocol          = "tcp"
  security_group_id = "${aws_security_group.control-plane.id}"
  description       = "Ingress access to K8s API"
  to_port           = 443
  type              = "ingress"
  cidr_blocks       = "${var.k8s_access_cidrs}"
}

resource "aws_eks_cluster" "wordpress" {
  name     = "${terraform.env}-${var.cluster_name}"
  role_arn = "${aws_iam_role.wordpress-control-plane.arn}"

  vpc_config {
    security_group_ids = ["${aws_security_group.control-plane.id}"]
    subnet_ids         = ["${aws_subnet.wordpress.*.id}"]
  }

  depends_on = [
    "aws_iam_role_policy_attachment.wordpress-eks-cluster",
    "aws_iam_role_policy_attachment.wordpress-eks-policy",
  ]
}

resource "aws_iam_role" "wordpress-node" {
  name               = "${terraform.env}-${var.cluster_name}-node"
  assume_role_policy = "${file("${path.module}/templates/aws/node-role.json")}"
}

resource "aws_iam_role_policy_attachment" "wordpress-node-eks-node-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.wordpress-node.name}"
}

resource "aws_iam_role_policy_attachment" "wordpress-node-eks-cni-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.wordpress-node.name}"
}

resource "aws_iam_role_policy" "wordpress-node-autoscaling-permissions" {
  role   = "${aws_iam_role.wordpress-node.name}"
  policy = "${file("${path.module}/templates/aws/node-autoscaling-permissions.json")}"
}

resource "aws_iam_instance_profile" "wordpress-node" {
  name = "${terraform.env}-${var.cluster_name}"
  role = "${aws_iam_role.wordpress-node.name}"
}

resource "aws_security_group" "wordpress-node" {
  name        = "${terraform.env}-${var.cluster_name}-nodes"
  description = "Node SG"
  vpc_id      = "${aws_vpc.wordpress.id}"
  tags        = "${map(
                    "Name", "${terraform.env}-${var.cluster_name}",
                    "kubernetes.io/cluster/${terraform.env}-${var.cluster_name}", "owned")
                 }"

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "wordpress-node-ingress-self" {
  description              = "Allow nodes to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.wordpress-node.id}"
  source_security_group_id = "${aws_security_group.wordpress-node.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "wordpress-node-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.wordpress-node.id}"
  source_security_group_id = "${aws_security_group.control-plane.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "wordpress-cluster-ingress-node-https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.control-plane.id}"
  source_security_group_id = "${aws_security_group.wordpress-node.id}"
  to_port                  = 443
  type                     = "ingress"
}

data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["eks-worker-*"]
  }
  most_recent = true
  owners      = ["602401143452"]
}

data "aws_region" "current" {}

data "template_file" "node-userdata" {
  template = "${file("${path.module}/templates/k8s/node-userdata.sh.tpl")}"

  vars {
    eks_ca           = "${aws_eks_cluster.wordpress.certificate_authority.0.data}"
    eks_endpoint     = "${aws_eks_cluster.wordpress.endpoint}"
    eks_cluster_name = "${aws_eks_cluster.wordpress.name}"
    aws_region       = "${data.aws_region.current.name}"
  }
}

resource "aws_launch_configuration" "wordpress" {
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.wordpress-node.name}"
  image_id                    = "${data.aws_ami.eks-worker.id}"
  instance_type               = "${var.node_type}"
  name_prefix                 = "${terraform.env}-${var.cluster_name}"
  security_groups             = ["${aws_security_group.wordpress-node.id}"]
  user_data_base64            = "${base64encode(data.template_file.node-userdata.rendered)}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress" {
  desired_capacity     = "${var.node_min}"
  launch_configuration = "${aws_launch_configuration.wordpress.id}"
  max_size             = "${var.node_max}"
  min_size             = "${var.node_min}"
  name                 = "${terraform.env}-${var.cluster_name}"
  vpc_zone_identifier  = ["${aws_subnet.wordpress.*.id}"]

  tag {
    key                 = "Name"
    value               = "${terraform.env}-${var.cluster_name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${terraform.env}-${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }
}

data "template_file" "kubeconfig" {
  template = "${file("${path.module}/templates/k8s/kubeconfig.yaml.tpl")}"

  vars {
    eks_ca           = "${aws_eks_cluster.wordpress.certificate_authority.0.data}"
    eks_endpoint     = "${aws_eks_cluster.wordpress.endpoint}"
    eks_cluster_name = "${aws_eks_cluster.wordpress.name}"
  }
}

resource "local_file" "kubeconfig" {
  filename = "/tmp/${aws_eks_cluster.wordpress.name}-kubeconfig"
  content  = "${data.template_file.kubeconfig.rendered}"
}

data "template_file" "aws-auth-configmap" {
  template = "${file("${path.module}/templates/k8s/aws-auth.yaml.tpl")}"

  vars {
    role_arn = "${aws_iam_role.wordpress-node.arn}"
  }
}

resource "local_file" "aws-auth" {
  #TODO: Move to terraform native resources once fully supported
  filename   = "/tmp/aws-auth.yaml"
  content    = "${data.template_file.aws-auth-configmap.rendered}"
  depends_on = ["local_file.kubeconfig"]

  provisioner "local-exec" {
    command = "kubectl apply -f ${self.filename} --kubeconfig ${local_file.kubeconfig.filename}"
  }
}

data "template_file" "cluster-autoscaler" {
  template = "${file("${path.module}/templates/k8s/cluster-autoscaler.yaml.tpl")}"

  vars {
    node_min = "${var.node_min}"
    node_max = "${var.node_max}"
    asg_name = "${aws_autoscaling_group.wordpress.name}"
  }
}

resource "local_file" "cluster-autoscaler" {
  #TODO: Move to terraform native resources once fully supported
  filename   = "/tmp/cluster-autoscaler.yaml"
  content    = "${data.template_file.cluster-autoscaler.rendered}"
  depends_on = [
    "local_file.kubeconfig",
    "local_file.aws-auth"
  ]

  provisioner "local-exec" {
    command = "kubectl apply -f ${self.filename} --kubeconfig ${local_file.kubeconfig.filename}"
  }
}

resource "null_resource" "add-ons" {
  #TODO: Move to terraform native resources once fully supported
  depends_on = [
    "local_file.kubeconfig",
    "local_file.aws-auth"
  ]

  provisioner "local-exec" {
    command = <<KUBECTL
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/rbac/heapster-rbac.yaml --kubeconfig ${local_file.kubeconfig.filename} && \
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/influxdb.yaml --kubeconfig ${local_file.kubeconfig.filename} && \
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/heapster.yaml --kubeconfig ${local_file.kubeconfig.filename}
KUBECTL
  }
}
