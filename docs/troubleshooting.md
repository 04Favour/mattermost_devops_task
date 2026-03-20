# Troubleshooting

Real errors encountered during this deployment and how they were resolved.

---

## Terraform

### EKS requires at least 2 subnets in different AZs
**Error:** EKS cluster creation fails with a subnet validation error.

**Cause:** Only one subnet was defined, in a single Availability Zone.

**Fix:** Add a second subnet in a different AZ and reference both in `vpc_config.subnet_ids`.

---

### `use_lockfile` not supported
**Error:** Terraform init fails referencing `use_lockfile`.

**Cause:** `required_version = ">= 1.2"` is too low. `use_lockfile` requires Terraform 1.10+.

**Fix:**
```hcl
required_version = ">= 1.10"
```

---

### `encrypt = "true"` should be boolean
**Cause:** S3 backend `encrypt` was set as a string `"true"` instead of a boolean.

**Fix:**
```hcl
encrypt = true
```

---

### Subnet CIDR conflict on apply
**Error:**
```
InvalidSubnet.Conflict: The CIDR '10.0.1.0/24' conflicts with another subnet
```

**Cause:** A previous partial `terraform apply` created the subnet in AWS but crashed before saving it to the statefile. Terraform no longer knows about it but AWS does.

**Fix:** Import the existing subnet into state:
```bash
aws ec2 describe-subnets \
  --filters "Name=cidrBlock,Values=10.0.1.0/24" \
  --query "Subnets[*].SubnetId" \
  --output text

terraform import aws_subnet.public_subnet_a <subnet-id>
```

---

### Reference to undeclared resource
**Error:**
```
A managed resource "aws_subnet" "aws_subnet" has not been declared
```

**Cause:** Resource reference was written as `aws_subnet.aws_subnet.public_subnet_b.id` — the resource type was doubled.

**Fix:** Terraform references follow the format `resource_type.resource_name.attribute`:
```hcl
aws_subnet.public_subnet_b.id   # correct
aws_subnet.aws_subnet.public_subnet_b.id   # wrong
```

---

## Kubernetes

### `clusterIP: None` rejected
**Error:**
```
spec.clusterIPs[0]: Invalid value: "none": must be a valid IP address
```

**Cause:** `None` is case-sensitive in Kubernetes. Lowercase `none` is treated as an invalid IP.

**Fix:**
```yaml
clusterIP: None   # capital N
```

---

### `type: clusterIP` rejected
**Error:**
```
spec.type: Unsupported value: "clusterIP"
```

**Cause:** Service type values are case-sensitive. `clusterIP` is wrong.

**Fix:**
```yaml
type: ClusterIP   # capital C
```

---

### PVC stuck in Pending — no StorageClass
**Symptom:** PVC shows `Pending` with empty `STORAGECLASS` column.

**Cause:** No default StorageClass was set on the cluster, and the PVC didn't specify one explicitly.

**Fix:**
1. Patch `gp2` as the default:
```bash
kubectl patch storageclass gp2 \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```
2. Add `storageClassName: gp2` explicitly to `volumeClaimTemplates` in the StatefulSet.
3. Since `volumeClaimTemplates` is immutable, delete and recreate:
```bash
kubectl delete statefulset postgres
kubectl delete pvc postgres-data-postgres-0
kubectl apply -f postgres-statefulset.yaml
```

---

### PVC stuck in Pending — EBS CSI Driver missing
**Symptom:** PVC describes with:
```
Waiting for a volume to be created by the external provisioner 'ebs.csi.aws.com'
```

**Cause:** The EBS CSI Driver add-on is not installed. EKS does not include it by default.

**Fix:** Install the EBS CSI Driver add-on (see [PostgreSQL doc](./postgres.md#ebs-csi-driver-installation)).

---

### Ingress annotation deprecation warning
**Warning:**
```
annotation "kubernetes.io/ingress.class" is deprecated, please use 'spec.ingressClassName' instead
```

**Fix:** Move the class out of annotations and into the spec:
```yaml
# Remove this annotation:
# kubernetes.io/ingress.class: alb

# Add this to spec:
spec:
  ingressClassName: alb
```

---

### `apiVersion not set` on Deployment
**Error:**
```
error validating data: apiVersion not set
```

**Cause:** The `apiVersion: apps/v1` line was missing from the top of the Deployment manifest.

**Fix:** Every Kubernetes manifest must start with `apiVersion` and `kind`.