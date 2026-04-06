# Mattermost on AWS EKS — Practical DevOps Bootcamp (Week 6-7)

> Deploying enterprise-grade Mattermost on Amazon EKS using Terraform and Kubernetes

---

## Overview

This project provisions a production-ready Kubernetes environment on AWS EKS and deploys [Mattermost](https://github.com/mattermost/mattermost.git) — a self-hosted team collaboration platform — with a persistent PostgreSQL database backend.

It is part of the **Practical DevOps Advanced Bootcamp** Week 6-7 track, focused on:
- Terraform EKS cluster provisioning
- Node groups, IAM roles, VPC configuration
- Kubernetes Deployments, Services, Ingress
- StatefulSets for PostgreSQL

---

## Architecture

```
Internet
   │
   ▼
AWS ALB (Ingress)
   │
   ▼
Mattermost Deployment (port 8065)
   │
   ▼
PostgreSQL StatefulSet (port 5432)
   │
   ▼
EBS PersistentVolume (10Gi, gp2)
```

All resources run inside an EKS cluster provisioned across two public subnets in separate Availability Zones.

---

## Project Structure

```
mattermost/
├── terraform/                  # Infrastructure as Code
│   ├── versions.tf             # Provider and backend config
│   ├── vpc.tf                  # VPC
│   ├── igw.tf                  # Internet Gateway
│   ├── subnets.tf              # Public subnets (us-east-1a, us-east-1b)
│   ├── route_tables.tf         # Route tables and associations
│   ├── eks_cluster.tf          # EKS cluster
│   ├── node_group.tf           # EKS node group + launch template
│   └── iam.tf                  # IAM roles and policy attachments
│
└── k8s/                        # Kubernetes manifests
    ├── postgres/
    │   ├── postgres-secret.yaml
    │   ├── postgres-statefulset.yaml
    │   └── postgres-service.yaml
    └── mattermost/
        ├── mattermost-secret.yaml
        ├── mattermost-deployment.yaml
        ├── mattermost-service.yaml
        └── mattermost-ingress.yaml
```

---

## Documentation

| Guide | Description |
|---|---|
| [Terraform Infrastructure](./docs/terraform.md) | VPC, EKS cluster, IAM, node groups |
| [PostgreSQL StatefulSet](./docs/postgres.md) | Persistent database setup on Kubernetes |
| [Mattermost Deployment](./docs/mattermost.md) | App deployment, service, and ingress |
| [Troubleshooting](./docs/troubleshooting.md) | Common errors and fixes encountered |
| [Teardown Guide](./docs/teardown.md) | Clean destroy order to avoid orphaned AWS resources |
| [EBS-CSI-DRIVER CrashLoopBackOff](./docs/troubleshooting__ii.md) | Steps to resolve EBS-CSI CrashLoopBack |

---

## Prerequisites

| Tool | Purpose |
|---|---|
| Terraform >= 1.10 | Infrastructure provisioning |
| AWS CLI | AWS authentication and resource management |
| kubectl | Kubernetes cluster management |
| eksctl | EKS-specific operations (OIDC, IAM service accounts) |
| Helm | Installing Kubernetes controllers |

---

## Quick Start

### 1. Provision Infrastructure
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### 2. Connect kubectl to the cluster
```bash
aws eks update-kubeconfig --region us-east-1 --name mattermost-cluster
```

### 3. Install the EBS CSI Driver
```bash
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster mattermost-cluster \
  --approve

eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster mattermost-cluster \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

aws eks create-addon \
  --cluster-name mattermost-cluster \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::<YOUR_ACCOUNT_ID>:role/AmazonEKS_EBS_CSI_DriverRole \
  --region us-east-1 \
  --force
```

### 4. Deploy PostgreSQL
```bash
kubectl apply -f k8s/postgres/postgres-secret.yaml
kubectl apply -f k8s/postgres/postgres-statefulset.yaml
kubectl apply -f k8s/postgres/postgres-service.yaml
```

### 5. Deploy Mattermost
```bash
kubectl apply -f k8s/mattermost/mattermost-secret.yaml
kubectl apply -f k8s/mattermost/mattermost-deployment.yaml
kubectl apply -f k8s/mattermost/mattermost-service.yaml
kubectl apply -f k8s/mattermost/mattermost-ingress.yaml
```

### 6. Get the ALB URL
```bash
kubectl get ingress mattermost-ingress
```

Open the `ADDRESS` value in your browser to access Mattermost.

---

## Key Concepts Learned

- **StatefulSet vs Deployment** — StatefulSets give pods stable, predictable names and their own PVCs that persist across restarts
- **PVC / PV / StorageClass** — How Kubernetes abstracts storage provisioning on AWS EBS
- **EBS CSI Driver** — Required add-on for EKS to dynamically provision EBS volumes
- **Headless Service** — `clusterIP: None` enables stable DNS for StatefulSet pods
- **AWS Load Balancer Controller** — Provisions an ALB from a Kubernetes Ingress resource
- **IMDSv2** — Enforced on node launch template for EC2 metadata security

---

# mattermostDevops
# mattermost_devops_task
