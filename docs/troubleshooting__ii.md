## EBS-CSI-DRIVER CrashLoopBackOff

### Problem

The `ebs-csi-controller` pods were stuck in `CrashLoopBackOff` with only `1/6` containers
ready. All containers (`ebs-plugin`, `csi-provisioner`, `csi-attacher`, `csi-snapshotter`,
`csi-resizer`) were failing with:
AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity
The root cause was that the IAM role `AmazonEKS_EBS_CSI_DriverRole` referenced in the pod
environment variables **did not exist** in the AWS account. Without it, the driver could not
assume the role via IRSA (IAM Roles for Service Accounts) to authenticate with AWS APIs.

---

### Resolution

**1. Ensure the OIDC provider is registered in IAM:**
```bash
eksctl utils associate-iam-oidc-provider \
  --cluster mattermost-cluster \
  --region us-east-1 \
  --approve
```

**2. Create the trust policy:**
```bash
cat > ebs-csi-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/<OIDC_ID>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-east-1.amazonaws.com/id/<OIDC_ID>:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa",
          "oidc.eks.us-east-1.amazonaws.com/id/<OIDC_ID>:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
```

**3. Create the IAM role and attach the required policy:**
```bash
aws iam create-role \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --assume-role-policy-document file://ebs-csi-trust-policy.json

aws iam attach-role-policy \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
```

**4. Annotate the service account:**
```bash
kubectl annotate serviceaccount ebs-csi-controller-sa \
  -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::<ACCOUNT_ID>:role/AmazonEKS_EBS_CSI_DriverRole \
  --overwrite
```

**5. Restart the controller:**
```bash
kubectl rollout restart deployment/ebs-csi-controller -n kube-system
kubectl rollout status deployment/ebs-csi-controller -n kube-system
```

All pods should now show `6/6 Running`.

**Just In case serviceaccount for loadbalancer acts up:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::032098306215:role/AmazonEKSLoadBalancerControllerRole
EOF
```