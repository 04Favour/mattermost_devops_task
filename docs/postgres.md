# PostgreSQL StatefulSet

This document covers the PostgreSQL deployment on Kubernetes using a StatefulSet with persistent EBS storage.

---

## Why a StatefulSet?

A **StatefulSet** is used instead of a Deployment because:

- Each pod gets a **stable, predictable name** (`postgres-0`, `postgres-1`) rather than a random suffix
- Each pod gets its **own PersistentVolumeClaim** that stays bound to it across restarts
- If `postgres-0` is deleted and rescheduled, it reattaches to the same EBS volume — no data loss

This is the correct Kubernetes primitive for databases.

---

## Storage: PVC → PV → EBS

```
postgres-0 pod
    └── mounts postgres-data-postgres-0 (PVC)
              └── bound to pvc-xxxx (PV)
                        └── backed by EBS volume (gp2, 10Gi)
```

The `volumeClaimTemplates` section in the StatefulSet automatically creates a PVC per pod. The StorageClass (`gp2`) tells the EBS CSI Driver to dynamically provision an EBS volume.

> **Important:** The EBS CSI Driver must be installed as an EKS add-on for dynamic provisioning to work. Without it, PVCs stay in `Pending` indefinitely.

---

## EBS CSI Driver Installation

```bash
# 1. Associate OIDC provider
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster mattermost-cluster \
  --approve

# 2. Create IAM service account
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster mattermost-cluster \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

# 3. Install the addon
aws eks create-addon \
  --cluster-name mattermost-cluster \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::<ACCOUNT_ID>:role/AmazonEKS_EBS_CSI_DriverRole \
  --region us-east-1
```

---

## Manifests

### Secret
Credentials are stored in a Kubernetes Secret and injected via `envFrom`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: default
type: Opaque
stringData:
  POSTGRES_DB: mattermost
  POSTGRES_USER: mmuser
  POSTGRES_PASSWORD: <your-password>
```

### StatefulSet

Key points:
- `serviceName: postgres` must match the headless Service name
- `subPath: postgres` on the volume mount prevents a known permissions issue with PostgreSQL on mounted volumes
- `storageClassName: gp2` explicitly set to avoid ambiguity

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: default
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15
          ports:
            - containerPort: 5432
          envFrom:
            - secretRef:
                name: postgres-secret
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
              subPath: postgres
  volumeClaimTemplates:
    - metadata:
        name: postgres-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp2
        resources:
          requests:
            storage: 10Gi
```

### Headless Service

`clusterIP: None` makes this a headless service — Kubernetes creates a DNS record directly for the pod (`postgres-0.postgres.default.svc.cluster.local`) rather than load-balancing through a virtual IP.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: default
spec:
  clusterIP: None
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
```

> **Note:** `clusterIP: None` is case-sensitive. Lowercase `none` causes a validation error.

---

## Verification

```bash
# StatefulSet status
kubectl get statefulset postgres

# Pod status
kubectl get pods -l app=postgres

# PVC status — should show Bound
kubectl get pvc

# Logs — should end with "database system is ready to accept connections"
kubectl logs postgres-0
```

---

## Updating the StatefulSet

`volumeClaimTemplates` is **immutable** after creation. If you need to change storage config, you must delete and recreate:

```bash
kubectl delete statefulset postgres
kubectl delete pvc postgres-data-postgres-0
kubectl apply -f postgres-statefulset.yaml
```

> This will cause data loss in a dev environment. In production, migrate data first.