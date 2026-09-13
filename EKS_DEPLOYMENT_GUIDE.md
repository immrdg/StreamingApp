# StreamingApp EKS Deployment Guide

## Prerequisites

- AWS CLI configured with credentials
- `kubectl` installed and configured
- `helm` 3.x installed
- Access to EKS cluster
- Docker images pushed to ECR

## Step 1: Prepare Environment Variables

```bash
# Set your environment variables
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="123456789012"  # Replace with your AWS account ID
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export EKS_CLUSTER_NAME="streamingapp-eks"
export K8S_NAMESPACE="streamingapp"
export IMAGE_TAG="1.0.0"  # Use your image tag from Jenkins build
export APP_BASE_URL="https://streamingapp.example.com"  # Your domain
```

## Step 2: Configure kubectl for EKS

```bash
# Update kubeconfig to connect to EKS cluster
aws eks update-kubeconfig \
  --name ${EKS_CLUSTER_NAME} \
  --region ${AWS_REGION}

# Verify connection
kubectl cluster-info
kubectl get nodes
```

## Step 3: Create Namespace

```bash
kubectl create namespace ${K8S_NAMESPACE}
kubectl label namespace ${K8S_NAMESPACE} app=streamingapp
```

## Step 4: Create Secrets

### AWS Credentials Secret (for S3 access)

```bash
kubectl create secret generic streamingapp-aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID='your-access-key' \
  --from-literal=AWS_SECRET_ACCESS_KEY='your-secret-key' \
  -n ${K8S_NAMESPACE}
```

## Step 5: Deploy with Helm

### Using Helm Command

```bash
# Extract hostname from domain
HOST="${APP_BASE_URL#http://}"
HOST="${HOST#https://}"
HOST="${HOST%%/*}"

# Deploy to EKS
helm upgrade --install streamingapp ./infrastructure/eks/helm/streamingapp \
  --namespace ${K8S_NAMESPACE} \
  --create-namespace \
  --set global.imageRegistry="${ECR_REGISTRY}" \
  --set global.imageTag="${IMAGE_TAG}" \
  --set ingress.host="${HOST}" \
  --set ingress.enabled=true \
  --set config.clientUrls="${APP_BASE_URL}" \
  --set config.streamingPublicUrl="${APP_BASE_URL}" \
  --set config.awsRegion="${AWS_REGION}" \
  --set config.awsS3Bucket="streamingapp-videos-1789299262" \
  --set config.awsCdnUrl="${APP_BASE_URL}" \
  --set secrets.jwtSecret="your-jwt-secret-key-change-this" \
  --set secrets.awsAccessKeyId="your-aws-access-key" \
  --set secrets.awsSecretAccessKey="your-aws-secret-key" \
  --wait \
  --timeout 5m
```

### Or Using Values File

Create `eks-values.yaml`:

```yaml
global:
  imageRegistry: "123456789012.dkr.ecr.us-east-1.amazonaws.com"
  imageTag: "1.0.0"
  imagePullPolicy: IfNotPresent

config:
  mongoDatabase: streamingapp
  clientUrls: "https://streamingapp.example.com"
  awsRegion: us-east-1
  awsS3Bucket: "streamingapp-videos-1789299262"
  awsCdnUrl: "https://streamingapp.example.com"
  streamingPublicUrl: "https://streamingapp.example.com"

secrets:
  jwtSecret: "your-jwt-secret-key-change-this"
  awsAccessKeyId: "your-aws-access-key"
  awsSecretAccessKey: "your-aws-secret-key"

services:
  auth:
    replicas: 2
  streaming:
    replicas: 2
  admin:
    replicas: 2
  chat:
    replicas: 2
  frontend:
    replicas: 2

mongo:
  storageSize: 20Gi
  storageClassName: "gp2"

ingress:
  enabled: true
  className: nginx
  host: streamingapp.example.com
  tls:
    enabled: true
    secretName: streamingapp-tls
```

Then deploy:

```bash
helm upgrade --install streamingapp ./infrastructure/eks/helm/streamingapp \
  -f eks-values.yaml \
  --namespace ${K8S_NAMESPACE} \
  --wait \
  --timeout 5m
```

## Step 6: Verify Deployment

```bash
# Check Helm release
helm list -n ${K8S_NAMESPACE}

# Check all pods
kubectl get pods -n ${K8S_NAMESPACE}

# Check services
kubectl get svc -n ${K8S_NAMESPACE}

# Check ingress
kubectl get ingress -n ${K8S_NAMESPACE}

# Describe ingress for external IP
kubectl describe ingress streamingapp-frontend -n ${K8S_NAMESPACE}
```

## Step 7: Monitor Services

```bash
# Watch deployment rollout
kubectl rollout status deployment/streamingapp-auth -n ${K8S_NAMESPACE}
kubectl rollout status deployment/streamingapp-streaming -n ${K8S_NAMESPACE}
kubectl rollout status deployment/streamingapp-admin -n ${K8S_NAMESPACE}
kubectl rollout status deployment/streamingapp-chat -n ${K8S_NAMESPACE}
kubectl rollout status deployment/streamingapp-frontend -n ${K8S_NAMESPACE}

# Check logs
kubectl logs -n ${K8S_NAMESPACE} -l app.kubernetes.io/component=auth -f

# Port forward for testing
kubectl port-forward svc/streamingapp-frontend 3000:80 -n ${K8S_NAMESPACE}
```

## Step 8: Configure DNS

Update your DNS records to point to the ingress controller:

```bash
# Get ingress external IP
kubectl get ingress streamingapp-frontend -n ${K8S_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Add CNAME record:
```
streamingapp.example.com CNAME <ingress-hostname>
```

## Step 9: Setup TLS Certificate (Optional)

If using cert-manager:

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: streamingapp-tls
  namespace: ${K8S_NAMESPACE}
spec:
  secretName: streamingapp-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - streamingapp.example.com
EOF
```

## Troubleshooting

### Check pod status
```bash
kubectl describe pod <pod-name> -n ${K8S_NAMESPACE}
```

### Check events
```bash
kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp'
```

### Restart deployment
```bash
kubectl rollout restart deployment/streamingapp-auth -n ${K8S_NAMESPACE}
```

### Delete and redeploy
```bash
helm uninstall streamingapp -n ${K8S_NAMESPACE}
helm install streamingapp ./infrastructure/eks/helm/streamingapp \
  -f eks-values.yaml \
  -n ${K8S_NAMESPACE}
```

## Accessing the Application

### Via Ingress (Recommended)
```
https://streamingapp.example.com
```

### Via Port Forward (Testing)
```bash
kubectl port-forward svc/streamingapp-frontend 3000:80 -n ${K8S_NAMESPACE}
# Access: http://localhost:3000
```

### Via LoadBalancer Service
```bash
kubectl get svc streamingapp-frontend -n ${K8S_NAMESPACE}
# Use EXTERNAL-IP:80
```

## Scaling Services

```bash
# Scale auth service to 3 replicas
kubectl scale deployment streamingapp-auth --replicas=3 -n ${K8S_NAMESPACE}

# Or update values and redeploy
helm upgrade streamingapp ./infrastructure/eks/helm/streamingapp \
  --set services.auth.replicas=3 \
  -n ${K8S_NAMESPACE}
```

## Updating Images

```bash
# After pushing new images to ECR
helm upgrade streamingapp ./infrastructure/eks/helm/streamingapp \
  --set global.imageTag="1.1.0" \
  -n ${K8S_NAMESPACE}
```

## Backup and Recovery

```bash
# Backup MongoDB data
kubectl exec -n ${K8S_NAMESPACE} streamingapp-mongo-0 -- \
  mongodump --out /backup

# Restore MongoDB data
kubectl exec -n ${K8S_NAMESPACE} streamingapp-mongo-0 -- \
  mongorestore /backup
```

## Cleanup

```bash
# Remove all resources
helm uninstall streamingapp -n ${K8S_NAMESPACE}

# Delete namespace
kubectl delete namespace ${K8S_NAMESPACE}
```

## Jenkins Integration

The Jenkinsfile supports automatic deployment to EKS:

```groovy
// In Jenkins parameters:
// DEPLOY_TO_EKS = true
// EKS_CLUSTER_NAME = streamingapp-eks
// K8S_NAMESPACE = streamingapp
// IMAGE_TAG = 1.0.0
// APP_BASE_URL = https://streamingapp.example.com
```

Helm upgrade command runs automatically when `DEPLOY_TO_EKS=true`.

## Next Steps

1. ✅ Push Docker images to ECR
2. ✅ Configure EKS cluster
3. ✅ Deploy Helm chart
4. ✅ Verify all services running
5. ✅ Configure DNS
6. ✅ Setup TLS certificate
7. ✅ Monitor and scale services
