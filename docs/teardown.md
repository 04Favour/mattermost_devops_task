# Teardown Guide

How to cleanly destroy all resources provisioned for this project to avoid ongoing AWS costs.

> **Order matters.** Kubernetes resources must be deleted before Terraform destroy. If the ALB is not deprovisioned first, it leaves orphaned resources inside the VPC that block Terraform from deleting the VPC.

---

## Step 1: Delete Kubernetes Resources

Delete in this order — ingress first to trigger ALB deprovisioning:

```bash
kubectl delete -f k8s/mattermost/mattermost-ingress.yaml
kubectl delete -f k8s/mattermost/mattermost-deployment.yaml
kubectl delete -f k8s/mattermost/mattermost-service.yaml
kubectl delete -f k8s/mattermost/mattermost-secret.yaml
kubectl delete -f k8s/postgres/postgres-statefulset.yaml
kubectl delete -f k8s/postgres/postgres-service.yaml
kubectl delete -f k8s/postgres/postgres-secret.yaml
kubectl delete pvc postgres-data-postgres-0
```

---

## Step 2: Confirm ALB is Deprovisioned

Wait until the ALB is fully removed before proceeding. This usually takes 1-2 minutes:

```bash
kubectl get ingress
# Wait until output shows: No resources found in default namespace.
```

You can also verify in the AWS console under **EC2 → Load Balancers** — the ALB should disappear.

---

## Step 3: Destroy Terraform Infrastructure

```bash
cd terraform/
terraform destroy
```

Type `yes` when prompted. This removes:
- EKS cluster and node group
- EC2 worker nodes
- VPC, subnets, internet gateway, route tables
- IAM roles and policy attachments
- EBS volumes (provisioned by PVCs)

---

## Step 4: Verify in AWS Console

Check these services to confirm nothing is lingering:

| Service | What to check |
|---|---|
| EKS | No clusters remaining |
| EC2 | No running instances, no load balancers, no EBS volumes |
| VPC | No VPCs named `mattermost-vpc` |
| IAM | Roles `eks-role-cluster` and `eks-node-group-example` are deleted |

---

## Step 5: Clean Up Manual Resources

These were created outside of Terraform and must be deleted manually:

```bash
# EBS CSI Driver addon
aws eks delete-addon \
  --cluster-name mattermost-cluster \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1

# IAM roles created by eksctl
aws iam detach-role-policy \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

aws iam delete-role --role-name AmazonEKS_EBS_CSI_DriverRole

aws iam detach-role-policy \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy

aws iam delete-role --role-name AmazonEKSLoadBalancerControllerRole

# ALB Controller IAM policy
aws iam delete-policy \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy
```

---

## Note on S3 Backend

The S3 bucket (`mattermost-devid-bucket`) and the statefile inside it are **not** destroyed by `terraform destroy` — Terraform never deletes its own backend. If you want to clean it up:

```bash
# Delete the statefile
aws s3 rm s3://mattermost-devid-bucket/workspace/terraform.tfstate

# Delete the bucket (must be empty first)
aws s3 rb s3://mattermost-devid-bucket --force
```

> Only do this if you are fully done with the project. If you plan to redeploy, keep the bucket — Terraform will reuse it.