# Terraform Infrastructure

This document covers the AWS infrastructure provisioned with Terraform for the Mattermost EKS deployment.

---

## Backend Configuration

State is stored remotely in S3 with native locking (`use_lockfile = true`, requires Terraform >= 1.10):

```hcl
terraform {
  backend "s3" {
    bucket       = "mattermost-devid-bucket"
    key          = "workspace/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

> `use_lockfile` replaces the older DynamoDB locking approach. It requires Terraform 1.10+.

---

## Networking

### VPC
- CIDR: `10.0.0.0/16`
- DNS support and hostnames enabled (required for EKS)

### Subnets
Two public subnets across separate AZs — EKS requires a minimum of two subnets in different Availability Zones:

| Subnet | CIDR | AZ |
|---|---|---|
| public_subnet_a | 10.0.1.0/24 | us-east-1a |
| public_subnet_b | 10.0.2.0/24 | us-east-1b |

Both subnets carry Kubernetes tags needed for the ALB ingress controller:
```
kubernetes.io/role/elb = 1
kubernetes.io/cluster/mattermost-cluster = shared
```

### Internet Gateway + Route Table
A single route table sends all `0.0.0.0/0` traffic through the IGW, associated with both public subnets.

---

## EKS Cluster

```hcl
resource "aws_eks_cluster" "eks_cluster" {
  name     = "mattermost-cluster"
  role_arn = aws_iam_role.cluster_role.arn
  version  = "1.31"

  vpc_config {
    subnet_ids             = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
    endpoint_public_access = true
  }
}
```

---

## Node Group

- Instance type: `t3.medium` (current gen, better price/performance than t2)
- IMDSv2 enforced via launch template (`http_tokens = "required"`)
- Scaling: min 1, desired 1, max 2

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"   # enforces IMDSv2
  http_put_response_hop_limit = 2            # required for containers to access IMDS
}
```

> `hop_limit = 2` is important — without it, containers inside the node cannot reach the EC2 metadata service.

---

## IAM Roles

### Cluster Role (`eks-role-cluster`)
Attached policy: `AmazonEKSClusterPolicy`

The cluster role trust policy includes both `sts:AssumeRole` and `sts:TagSession` — required for newer EKS versions.

### Node Group Role (`eks-node-group-example`)
Attached policies:
- `AmazonEKSWorkerNodePolicy`
- `AmazonEKS_CNI_Policy`
- `AmazonEC2ContainerRegistryReadOnly`

---

## Deployment Order

Terraform handles dependency ordering automatically via `depends_on`, but the logical order is:

```
VPC → IGW → Subnets → Route Tables → IAM Roles → EKS Cluster → Node Group
```

---

## Common Issues

See [Troubleshooting](./troubleshooting.md) for issues encountered during provisioning.