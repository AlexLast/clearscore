# Interview task

## About

My experience deploying Kubernetes clusters and kubernetes resources is with kops and spinnaker,
however I've been dying to get my hands on EKS + Terraform EKS + Terraform kubernetes provider - so this 
seemed like a good opportunity to test it out.

Overall it seems EKS and the Terraform kubernetes provider are still quite immature so a couple of workarounds were required - namely depoying resources in
kubernetes, an example of this would be the lack of ability to ability to add pod level annotations or service level annotations e.g specifying an ACM certificate ARN to use when creating a loadbalancer. I had
to use local-exec's with kubectl to work around this, however with more time I would have looked at Spinnaker or Helm.

The stack:

* EKS deployed via Terraform
* Kubernetes resources provisoned with kubectl (Terraform provider doesn't support many options)
* Example wordpress service deployed
* Node autoscaling with cluster-autoscaler
* HPA for service
* Readiness/Liveness probes for service
* SSL configured for service on test domain

## Pre-requisites
The following is required before deploying:

* Cloudflare account with domain configured and referenced in the tfvars file (Unfortunately 
the only domain I have access to for this excercise is setup with Cloudflare, otherwise I would have used route53 to make testing easier for reviewers without Cloudflare access). 
The following environment variables will need to be set:
    * ```export CLOUDFLARE_TOKEN=CLOUDFLARE_API_TOKEN```
    * ```export CLOUDFLARE_EMAIL=CLOUDFLARE_ACCOUNT_EMAIL```
* kubectl version >= v1.10.3
* heptio-authenticator-aws >=v0.3.0
* terraform >= 0.11.7
* jq >= 1.5
* AWS account with a completed credentials file or the following environment variables set at a minimum:
    * ```export AWS_ACCESS_KEY_ID=xyz```
    * ```export AWS_SECRET_ACCESS_KEY=xyz```
    * ```export AWS_DEFAULT_REGION=us-east-1```
* Must be run in a Linux type shell (Required by some local-execs)
* An S3 bucket and DynamoDB table that can be used to store terraform state and provide locking (referenced in the example init). The table must have a primary key named LockID.

## Modules

The terraform modules in this repository:

* eks - Provisions a Kubernetes cluster in AWS with EKS, as well as cluster add ons such as: Heapster, cluster-autoscaler etc
* wordpress - Provisions wordpress on said Kubernetes cluster, as well as surrounding resources such as: SSL certificates, DNS records

## Scaling

Kubernetes is running cluster-autoscaler and configured to scale up the node count if pods can
no longer be scheduled or scale down the node count if there's unused resources, this currently defaults to a minimum of 1 and maximum of 2 as a proof of concept, however
it's completely configurable via the top-level variables in ```variables.tf```, just add them to the tfvars file you're deploying with.

The WordPress pods are also configured to scale up if they're utilising more than 70% CPU via Horizontal Pod Autoscaling - This is currently set to a minimum of 3 replicas and a maximum of 10 to fix the current node size, however this can obviously be configured to a higher/lower minimum and maximum.

With more time, I would like to have implemented Autoscaling in Aurora and performed a load test to show scaling up and down.

## Deploying

The following is an example of deploying a dev environment, the same commands/tfvars files can be modified to create a staging/prod environment etc. You can find all the variables 
 that can be set and their descriptions in ```terraform/variables.tf```. You can remove any backend config options you don't wish to use.

```bash
cd terraform
terraform init -backend-config="bucket=S3_BUCKET_NAME" -backend-config="region=S3_BUCKET_REGION" -backend-config="dynamodb_table=DYNAMODB_TABLE_NAME"
terraform workspace new dev
terraform plan -var-file=clearscore-dev.tfvars -var 'master_password=secure_password' -out /tmp/dev-plan
# Apply if plan looks good, ensure the master password is recorded securely (Should be >= characters)
terraform apply /tmp/dev-plan
```

Once the above apply has completed navigate to https://```${terraform.env}```-wordpress.```${var.service_base_domain}``` in a browser to complete the WP initial install.

If you wish to interact directly with the Kubernetes cluster post installation, the kubeconfig file can be found in ```/tmp/${var.cluster_name}-kubeconfig```

## Concessions/Improvements 
Some improvements I would have made with more time/AWS credits:

* Service deployment via Spinnaker pipeline (promotion to staging/prod) or Helm (In hindsight this may even have been quicker than the local apply's)
* Implement service level caching and session storage with W3TC & Redis/Memcached
* Automated WP install with WPCLI or similar (or restore from pre-installe RDS snapshot)
* AWS Aurora autoscaling
* Create own Defanged docker image for WP
* Implement monitoring and alerting
* More fine grained modules, with versioning
* Aurora/MySQL encryption at rest and in-transit
* Vault for secret storage
* Higher starting node count
* Cloudflare as a configurable option (e.g use ELB DNS only)
* Remove any local-exec workarounds or storage in /tmp
