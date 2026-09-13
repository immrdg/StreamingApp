# StreamingApp EKS Deployment Testing Guide

## Pre-Deployment Checks

### 1. Verify ECR Images Exist

```bash
# Set variables
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="123456789012"
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# List available images
aws ecr describe-repositories --region ${AWS_REGION} --query 'repositories[*].repositoryName' --output text

# Check specific image tags
aws ecr describe-images \
  --repository-name streamingapp-frontend \
  --region ${AWS_REGION} \
  --query 'imageDetails[*].[imageTags,imageSizeInBytes]' \
  --output table
```

### 2. Verify EKS Cluster

```bash
# Get cluster info
aws eks describe-cluster \
  --name streamingapp-eks \
  --region ${AWS_REGION} \
  --query 'cluster.[name,status,endpoint]' \
  --output table

# Update kubeconfig
aws eks update-kubeconfig \
  --name streamingapp-eks \
  --region ${AWS_REGION}

# Test connection
kubectl cluster-info
kubectl get nodes
kubectl get namespaces
```

### 3. Verify Ingress Controller

```bash
# Check if nginx ingress is installed
kubectl get namespace ingress-nginx

# If not, install it:
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values - <<EOF
controller:
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
EOF
```

## Deployment Testing

### Step 1: Deploy to Staging

```bash
export K8S_NAMESPACE="streamingapp-staging"
export IMAGE_TAG="1.0.0"

# Create namespace
kubectl create namespace ${K8S_NAMESPACE}

# Deploy using staging values
helm upgrade --install streamingapp \
  ./infrastructure/eks/helm/streamingapp \
  -f ./infrastructure/eks/helm/streamingapp/values-staging.yaml \
  --namespace ${K8S_NAMESPACE} \
  --set global.imageRegistry="${ECR_REGISTRY}" \
  --set global.imageTag="${IMAGE_TAG}" \
  --wait \
  --timeout 10m
```

### Step 2: Monitor Deployment

```bash
# Watch pods coming up
kubectl get pods -n ${K8S_NAMESPACE} -w

# Check deployment status
kubectl get deployments -n ${K8S_NAMESPACE}

# Describe deployments to see events
kubectl describe deployment streamingapp-auth -n ${K8S_NAMESPACE}
kubectl describe deployment streamingapp-streaming -n ${K8S_NAMESPACE}
kubectl describe deployment streamingapp-frontend -n ${K8S_NAMESPACE}

# Check services
kubectl get svc -n ${K8S_NAMESPACE}

# Check ingress
kubectl get ingress -n ${K8S_NAMESPACE}
```

### Step 3: Verify Pod Health

```bash
# Check all pod statuses
kubectl get pods -n ${K8S_NAMESPACE} \
  -o custom-columns=NAME:.metadata.name,READY:.status.conditions[?(@.type=='Ready')].status,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount

# Check logs for each service
kubectl logs -n ${K8S_NAMESPACE} -l app.kubernetes.io/component=auth --tail=50
kubectl logs -n ${K8S_NAMESPACE} -l app.kubernetes.io/component=streaming --tail=50
kubectl logs -n ${K8S_NAMESPACE} -l app.kubernetes.io/component=admin --tail=50
kubectl logs -n ${K8S_NAMESPACE} -l app.kubernetes.io/component=chat --tail=50
kubectl logs -n ${K8S_NAMESPACE} -l app.kubernetes.io/component=frontend --tail=50
```

### Step 4: Test Internal Connectivity

```bash
# Port forward to test services locally
kubectl port-forward svc/streamingapp-auth 3001:3001 -n ${K8S_NAMESPACE} &
kubectl port-forward svc/streamingapp-streaming 3002:3002 -n ${K8S_NAMESPACE} &
kubectl port-forward svc/streamingapp-frontend 3000:80 -n ${K8S_NAMESPACE} &

# Test auth service
curl -X GET http://localhost:3001/health 2>/dev/null | jq .

# Test streaming service
curl -X GET http://localhost:3002/api/health 2>/dev/null | jq .

# Test frontend
curl -X GET http://localhost:3000/ 2>/dev/null | head -20

# Kill port forwards
pkill -f "port-forward"
```

### Step 5: Test External Access via Ingress

```bash
# Get ingress details
kubectl get ingress -n ${K8S_NAMESPACE} -o wide

# Get external IP/hostname
INGRESS_HOSTNAME=$(kubectl get ingress streamingapp-frontend -n ${K8S_NAMESPACE} \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Ingress hostname: ${INGRESS_HOSTNAME}"

# Test endpoints through ingress
curl -X GET "http://${INGRESS_HOSTNAME}/api/health" 2>/dev/null | jq .
curl -X GET "http://${INGRESS_HOSTNAME}/" 2>/dev/null | head -20
```

### Step 6: Database Connectivity Test

```bash
# Connect to MongoDB pod
kubectl exec -it streamingapp-mongo-0 -n ${K8S_NAMESPACE} -- mongosh

# In mongosh shell:
# > show dbs
# > use streamingapp
# > db.videos.find({}).pretty()
# > exit
```

### Step 7: API Endpoint Tests

```bash
# Get all videos
curl -X GET "http://${INGRESS_HOSTNAME}/api/streaming/videos" | jq .

# Get featured videos
curl -X GET "http://${INGRESS_HOSTNAME}/api/streaming/videos/featured" | jq .

# Get video by ID (replace VIDEO_ID)
curl -X GET "http://${INGRESS_HOSTNAME}/api/streaming/stream/{VIDEO_ID}" -i

# Test thumbnail endpoint
curl -X GET "http://${INGRESS_HOSTNAME}/api/streaming/thumbnails/react-1" -i
```

## Performance & Load Testing

### 1. Horizontal Pod Autoscaling (Optional)

```bash
# Check current HPA status
kubectl get hpa -n ${K8S_NAMESPACE}

# Create HPA for streaming service
kubectl autoscale deployment streamingapp-streaming \
  --min=2 \
  --max=5 \
  --cpu-percent=70 \
  -n ${K8S_NAMESPACE}

# Monitor HPA
kubectl get hpa -n ${K8S_NAMESPACE} -w
```

### 2. Load Testing with Apache Bench

```bash
# Install ab if needed
sudo apt-get install apache2-utils

# Test homepage
ab -n 100 -c 10 "http://${INGRESS_HOSTNAME}/"

# Test video endpoint
ab -n 100 -c 10 "http://${INGRESS_HOSTNAME}/api/streaming/videos"

# Check pod metrics
kubectl top pods -n ${K8S_NAMESPACE}
kubectl top nodes
```

## Smoke Tests Checklist

- [ ] **Frontend loads**: Homepage accessible and renders
- [ ] **API connectivity**: All endpoints respond with expected status codes
- [ ] **Database**: MongoDB pod running, data accessible
- [ ] **S3 integration**: Thumbnail URLs working, video streaming functional
- [ ] **Service discovery**: Pods can communicate with each other
- [ ] **Health checks**: All readiness/liveness probes passing
- [ ] **Logs**: No error spam, pod logs clean
- [ ] **Resource limits**: Pod CPU/memory within limits
- [ ] **Scaling**: Pods scale up when load increases
- [ ] **Recovery**: Pods restart gracefully after failure

## Production Deployment

### 1. Pre-Production Validation

```bash
# Run all tests from staging
# Verify SSL/TLS working
# Check performance metrics
# Validate monitoring alerts
```

### 2. Deploy to Production

```bash
export K8S_NAMESPACE="streamingapp"
export IMAGE_TAG="1.0.0"

helm upgrade --install streamingapp \
  ./infrastructure/eks/helm/streamingapp \
  -f ./infrastructure/eks/helm/streamingapp/values-prod.yaml \
  --namespace ${K8S_NAMESPACE} \
  --set global.imageRegistry="${ECR_REGISTRY}" \
  --set global.imageTag="${IMAGE_TAG}" \
  --wait \
  --timeout 15m
```

### 3. Post-Deployment Verification

```bash
# Verify all pods running
kubectl get pods -n ${K8S_NAMESPACE}

# Check service endpoints
kubectl get endpoints -n ${K8S_NAMESPACE}

# Verify ingress is active
kubectl get ingress -n ${K8S_NAMESPACE}

# Run smoke tests
# - Frontend loads
# - APIs respond
# - Video playback works
# - Thumbnails load from S3
```

## Rollback Procedure

```bash
# View Helm history
helm history streamingapp -n ${K8S_NAMESPACE}

# Rollback to previous release
helm rollback streamingapp 1 -n ${K8S_NAMESPACE}

# Verify rollback
kubectl get pods -n ${K8S_NAMESPACE}
kubectl get svc -n ${K8S_NAMESPACE}
```

## Monitoring & Alerting

### 1. Prometheus Metrics

```bash
# View pod metrics
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/${K8S_NAMESPACE}/pods | jq .

# Top pods by CPU
kubectl top pods -n ${K8S_NAMESPACE} --sort-by=cpu

# Top pods by memory
kubectl top pods -n ${K8S_NAMESPACE} --sort-by=memory
```

### 2. Logs Aggregation

```bash
# Stream logs from all pods
kubectl logs -n ${K8S_NAMESPACE} -f --all-containers=true -l app.kubernetes.io/instance=streamingapp

# View logs from specific service
kubectl logs -n ${K8S_NAMESPACE} -f -l app.kubernetes.io/component=streaming
```

## Troubleshooting

### Common Issues

#### Pods CrashLoopBackOff

```bash
# Check pod events
kubectl describe pod <pod-name> -n ${K8S_NAMESPACE}

# Check logs
kubectl logs <pod-name> -n ${K8S_NAMESPACE} --previous

# Check environment variables
kubectl exec <pod-name> -n ${K8S_NAMESPACE} -- env | grep -E 'MONGO|AWS|JWT'
```

#### Ingress Not Working

```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check ingress rules
kubectl get ingress streamingapp-frontend -n ${K8S_NAMESPACE} -o yaml

# Test ingress directly
kubectl run curl --image=curlimages/curl -it --rm -- /bin/sh
# In shell: curl http://streamingapp-frontend/
```

#### MongoDB Connection Issues

```bash
# Check MongoDB pod
kubectl describe pod streamingapp-mongo-0 -n ${K8S_NAMESPACE}

# Check persistent volume
kubectl get pv
kubectl get pvc -n ${K8S_NAMESPACE}

# Test connectivity from another pod
kubectl run -it --rm debug --image=mongo:6 --restart=Never -- \
  mongosh --host streamingapp-mongo:27017 --eval "db.adminCommand('ping')"
```

#### Image Pull Errors

```bash
# Check image pull secrets
kubectl get secrets -n ${K8S_NAMESPACE}

# Verify ECR login
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Check pod events for pull errors
kubectl describe pod <pod-name> -n ${K8S_NAMESPACE}
```

## Success Criteria

✅ All pods running and ready  
✅ All services accessible  
✅ Ingress routes traffic correctly  
✅ Frontend loads without errors  
✅ APIs responding with correct data  
✅ Video streaming works (206 Partial Content)  
✅ Thumbnails load from S3  
✅ Database persists data  
✅ No pod restarts or errors  
✅ Response times < 500ms  

## Next Steps

1. ✅ Deploy to staging environment
2. ✅ Run smoke tests
3. ✅ Validate performance
4. ✅ Setup monitoring/alerts
5. ✅ Deploy to production
6. ✅ Monitor for 24 hours
7. ✅ Document lessons learned
