# Optional "demo day" EKS cluster: the same GitOps stack as the kind lab, on AWS.
# Create it only to record a video or show it live, then destroy it.
# Cost while up: ~$0.15/hour (EKS control plane $0.10 + 2 Graviton spot nodes); on-demand nodes
# ~$0.20/hour, Intel c7i-flex.large nodes on the AWS Free plan ~$0.35/hour (scripts/eks-up.sh).
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = "kubeops-sre-lab"
      ManagedBy = "terraform"
      AutoStop  = "true"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "name" {
  description = "Cluster name; IAM role names start with it (aws-foundation allows the \"kubeops\" prefix)."
  type        = string
  default     = "kubeops-eks"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Pick one in standard support: aws eks describe-cluster-versions --query 'clusterVersions[].clusterVersion'"
  type        = string
  default     = "1.35"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t4g.medium", "t4g.large"]
}

variable "node_ami_type" {
  description = "Node image: AL2023_ARM_64_STANDARD for Graviton (t4g), AL2023_x86_64_STANDARD for Intel/AMD (c7i-flex.large on the AWS Free plan). scripts/eks-up.sh sets it."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
  validation {
    condition     = contains(["AL2023_ARM_64_STANDARD", "AL2023_x86_64_STANDARD"], var.node_ami_type)
    error_message = "node_ami_type must be AL2023_ARM_64_STANDARD or AL2023_x86_64_STANDARD."
  }
}

variable "capacity_type" {
  description = "SPOT (cheapest) or ON_DEMAND. Accounts from the new AWS sign-up cannot use spot: scripts/eks-up.sh picks ON_DEMAND there."
  type        = string
  default     = "SPOT"
  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.capacity_type)
    error_message = "capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "node_count" {
  type    = number
  default = 2
}

variable "api_allowed_cidrs" {
  description = "Who may reach the Kubernetes API endpoint. Narrow this to your IP (x.x.x.x/32) when you can."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_principal_arns" {
  description = "Extra IAM roles/users that get cluster-admin (the identity that runs Terraform is admin automatically)."
  type        = list(string)
  default     = []
}

data "aws_availability_zones" "available" {
  state = "available"
}

variable "permissions_boundary_name" {
  description = "IAM permissions boundary that aws-foundation creates. Both roles here carry it; the GitHub deploy role refuses to create roles without it. Set \"\" only when you deploy without aws-foundation."
  type        = string
  default     = "gha-workload-boundary"
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
  p   = data.aws_partition.current.partition

  # Every IAM role here carries the aws-foundation permissions boundary.
  permissions_boundary = var.permissions_boundary_name == "" ? null : "arn:${local.p}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.permissions_boundary_name}"
}

# ---------------------------------------------------------------- network
# Public subnets only (no $33/month NAT gateway). Nodes get public IPs but their
# security group (managed by EKS) accepts traffic only from the cluster.
resource "aws_vpc" "this" {
  cidr_block           = "10.60.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.name}-vpc"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  map_public_ip_on_launch = true # nodes need a route to ECR/GHCR without NAT
  tags = {
    Name                     = "${var.name}-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -------------------------------------------------------------------- IAM
data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name                 = "${var.name}-cluster"
  assume_role_policy   = data.aws_iam_policy_document.eks_assume.json
  permissions_boundary = local.permissions_boundary
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${local.p}:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name                 = "${var.name}-node"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume.json
  permissions_boundary = local.permissions_boundary
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each   = toset(["AmazonEKSWorkerNodePolicy", "AmazonEKS_CNI_Policy", "AmazonEC2ContainerRegistryReadOnly"])
  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.p}:iam::aws:policy/${each.value}"
}

# ---------------------------------------------------------------- cluster
resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.api_allowed_cidrs
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Never slip into extended support (6x the control-plane price).
  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_eks_access_entry" "admins" {
  for_each      = toset(var.admin_principal_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "admins" {
  for_each      = toset(var.admin_principal_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:${local.p}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [aws_eks_access_entry.admins]
}

resource "aws_eks_addon" "pre_nodes" {
  for_each                    = toset(["vpc-cni", "kube-proxy"])
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
}

# Graviton spot nodes: ~70% cheaper than on-demand. Two instance types make a
# spot shortage less likely. (On-demand in accounts that cannot use spot; Intel
# c7i-flex.large nodes in accounts on the AWS Free plan - see scripts/eks-up.sh.)
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-${replace(lower(var.capacity_type), "_", "-")}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.public[*].id
  capacity_type   = var.capacity_type
  ami_type        = var.node_ami_type
  instance_types  = var.node_instance_types
  disk_size       = 30

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count + 1
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [aws_iam_role_policy_attachment.node, aws_eks_addon.pre_nodes]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.this]
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name} --alias kubeops-eks"
}
