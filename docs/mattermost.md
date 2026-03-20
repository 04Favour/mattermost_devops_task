# Mattermost Deployment

This document covers the Kubernetes deployment of Mattermost and its exposure via an AWS ALB Ingress.

---

## Overview

Mattermost connects to PostgreSQL using a connection string stored in a Kubernetes Secret. An `initContainer` ensures the pod waits for PostgreSQL to be ready before starting.

Traffic flow:
```
Internet → AWS ALB → mattermost Service (ClusterIP:8065) → mattermost Pod
```

---

## Manifests

### Secret

Holds the PostgreSQL connection string. The hostname `postgres` resolves via Kubernetes DNS to the PostgreSQL headless Service.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mattermost-secret
  namespace: default
type: Opaque
stringData:
  MM_SQLSETTINGS_DATASOURCE: "postgres://mmuser:mmpassword@postgres:5432/mattermost?sslmode=disable"
```

### Deployment

Key points:
- `initContainer` uses `busybox` to poll `postgres:5432` before the main container starts
- `MM_SERVICESETTINGS_SITEURL` should be updated to the ALB DNS name after ingress is created

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mattermost
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mattermost
  template:
    metadata:
      labels:
        app: mattermost
    spec:
      initContainers:
        - name: wait-for-postgres
          image: busybox
          command: ['sh', '-c', 'until nc -z postgres 5432; do echo waiting for postgres; sleep 2; done']
      containers:
        - name: mattermost
          image: mattermost/mattermost-team-edition:latest
          ports:
            - containerPort: 8065
          env:
            - name: MM_SQLSETTINGS_DATASOURCE
              valueFrom:
                secretKeyRef:
                  name: mattermost-secret
                  key: MM_SQLSETTINGS_DATASOURCE
            - name: MM_SERVICESETTINGS_SITEURL
              value: "http://<YOUR_ALB_DNS>"
```

### Service

Internal ClusterIP service — only reachable within the cluster. The Ingress handles external access.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mattermost
  namespace: default
spec:
  selector:
    app: mattermost
  ports:
    - port: 8065
      targetPort: 8065
  type: ClusterIP
```

### Ingress

Uses the AWS Load Balancer Controller to provision an internet-facing ALB.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mattermost-ingress
  namespace: default
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: mattermost
                port:
                  number: 8065
```

> `target-type: ip` routes traffic directly to pod IPs rather than node IPs — more efficient and required when using the VPC CNI plugin.

---

## AWS Load Balancer Controller Installation

The ALB Ingress controller must be installed before creating the Ingress resource.

```bash
# 1. Download the IAM policy
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

# 2. Create the policy
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# 3. Create the IAM service account
eksctl create iamserviceaccount \
  --cluster mattermost-cluster \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# 4. Install via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=mattermost-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# 5. Verify
kubectl get pods -n kube-system | grep aws-load-balancer
```

---

## Verification

```bash
# Check pod is running
kubectl get pods -l app=mattermost

# Check service
kubectl get service mattermost

# Get ALB address (takes 2-3 mins to provision)
kubectl get ingress mattermost-ingress
```

Once the `ADDRESS` column is populated, open the URL in a browser to access the Mattermost setup page.

---

## Post-Deployment

After getting the ALB URL, update `MM_SERVICESETTINGS_SITEURL` in the deployment:

```yaml
- name: MM_SERVICESETTINGS_SITEURL
  value: "http://k8s-default-mattermo-xxxx.us-east-1.elb.amazonaws.com"
```

Then re-apply:
```bash
kubectl apply -f k8s/mattermost/mattermost-deployment.yaml
```