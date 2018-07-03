resource "aws_rds_cluster_instance" "wordpress" {
  count                = "${var.aurora_instances}"
  identifier           = "${var.cluster_name}-${count.index}"
  cluster_identifier   = "${aws_rds_cluster.wordpress.id}"
  instance_class       = "${var.instance_type}"
  publicly_accessible  = false
  db_subnet_group_name = "${aws_db_subnet_group.wordpress.name}"
  engine               = "${aws_rds_cluster.wordpress.engine}"
  engine_version       = "${aws_rds_cluster.wordpress.engine_version}"
}

resource "aws_rds_cluster" "wordpress" {
  cluster_identifier     = "${var.cluster_name}"
  database_name          = "wordpress"
  master_username        = "${var.master_username}"
  master_password        = "${var.master_password}"
  engine                 = "aurora-mysql"
  engine_version         = "5.7.12"
  db_subnet_group_name   = "${aws_db_subnet_group.wordpress.name}"
  vpc_security_group_ids = ["${aws_security_group.aurora.id}"]
  skip_final_snapshot    = true # For dev cost saving purposes
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "${var.cluster_name}"
  subnet_ids = ["${var.private_subnets}"]

  tags {
    Name = "${var.cluster_name}"
  }
}

resource "aws_security_group" "aurora" {
  name        = "${var.cluster_name}-aurora"
  description = "Allow nodes to communicate with Aurora"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port       = 3306
    protocol        = "tcp"
    to_port         = 3306
    security_groups = ["${var.node_sg}"]
  }

  tags {
    Name = "${var.cluster_name}"
  }
}

resource "aws_acm_certificate" "wordpress" {
  domain_name       = "${var.cluster_name}.${var.service_base_domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_record" "cert-validation" {
  domain  = "${var.service_base_domain}"
  name    = "${aws_acm_certificate.wordpress.domain_validation_options.0.resource_record_name}"
  value   = "${aws_acm_certificate.wordpress.domain_validation_options.0.resource_record_value}"
  type    = "${aws_acm_certificate.wordpress.domain_validation_options.0.resource_record_type}"
  proxied = false
}

resource "aws_acm_certificate_validation" "wordpress" {
  certificate_arn         = "${aws_acm_certificate.wordpress.arn}"
  validation_record_fqdns = ["${cloudflare_record.cert-validation.hostname}"]
}

data "template_file" "service" {
  template = "${file("${path.module}/templates/k8s/service.yaml.tpl")}"

  vars {
    acm_arn = "${aws_acm_certificate.wordpress.arn}"
  }
}

resource "local_file" "service" {
  filename = "/tmp/${var.cluster_name}-service.yaml"
  content  = "${data.template_file.service.rendered}"
}

data "template_file" "secrets" {
  template = "${file("${path.module}/templates/k8s/secrets.yaml.tpl")}"

  vars {
    mysql_user = "${base64encode(var.master_username)}"
    mysql_pass = "${base64encode(var.master_password)}"
    mysql_host = "${base64encode(aws_rds_cluster.wordpress.endpoint)}"
    mysql_db   = "${base64encode(aws_rds_cluster.wordpress.database_name)}"
  }
}

resource "local_file" "secrets" {
  filename = "/tmp/${var.cluster_name}-secrets.yaml"
  content  = "${data.template_file.secrets.rendered}"
}

resource "local_file" "deployment" {
  filename = "/tmp/${var.cluster_name}-deployment.yaml"
  content  = "${file("${path.module}/templates/k8s/deployment.yaml")}"
}

resource "local_file" "namespace" {
  filename = "/tmp/${var.cluster_name}-namespace.yaml"
  content  = "${file("${path.module}/templates/k8s/namespace.yaml")}"
}

resource "null_resource" "deploy-wordpress" {
  #TODO: Move to terraform native resources once fully supported
  triggers {
    always = "${uuid()}"
  }

  depends_on = ["aws_rds_cluster_instance.wordpress"]

  provisioner "local-exec" {
    command = <<KUBECTL
        kubectl apply -f ${local_file.namespace.filename} --kubeconfig ${var.kubeconfig} && \
        kubectl apply -f ${local_file.service.filename} --kubeconfig ${var.kubeconfig} && \
        kubectl apply -f ${local_file.secrets.filename} --kubeconfig ${var.kubeconfig} && \
        kubectl apply -f ${local_file.deployment.filename} --kubeconfig ${var.kubeconfig}
KUBECTL
  }
}

resource "null_resource" "destroy-service" {
  #TODO: Move to terraform native resources once fully supported
  # Ensure K8s provisioned LB's are destroyed
  provisioner "local-exec" {
    when    = "destroy"
    command = "kubectl delete -f ${local_file.service.filename} --kubeconfig ${var.kubeconfig}"
  }
}

resource "null_resource" "hpa" {
  #TODO: Move to terraform native resources once fully supported
  depends_on = ["null_resource.deploy-wordpress"]

  provisioner "local-exec" {
    command = "kubectl autoscale deploy wordpress -n wordpress --min=3 --max=10 --cpu-percent=70 --kubeconfig ${var.kubeconfig}"
  }
}

resource "null_resource" "lb-ingress" {
  # Unfortunate work around as there is no good way of extracting the LB ingress without using the K8S native provider
  #TODO: Move to terraform native resources once fully supported
  depends_on = ["null_resource.deploy-wordpress"]

  triggers {
    always = "${uuid()}"
  }

  provisioner "local-exec" {
    # Let's ensure the LB has been provisioned
    command = "sleep 60; kubectl get svc wordpress -o json -n wordpress --kubeconfig ${var.kubeconfig} | jq -rj '.status.loadBalancer.ingress[0].hostname' > ${path.module}/tmp/lb-ingress"
  }
}

resource "cloudflare_record" "wordpress" {
  domain     = "${var.service_base_domain}"
  name       = "${var.cluster_name}"
  value      = "${file("${path.module}/tmp/lb-ingress")}" # This is required even with the depends_on, the file interpolation happens at plan
  type       = "CNAME"
  proxied    = false
  depends_on = ["null_resource.lb-ingress"]
}
