# StreamingApp EKS Deployment

This deployment follows the assignment PDFs: build five images, publish each one to Amazon ECR, create an EKS cluster, and deploy the app with Helm.

## 1. Create ECR Repositories

The Jenkins pipeline creates these automatically before pushing. To create them manually:

```bash
cd infrastructure/ecr
terraform init
terraform apply -var aws_region=ap-south-1
```

Repositories:

- `streamingapp-auth`
- `streamingapp-streaming`
- `streamingapp-admin`
- `streamingapp-chat`
- `streamingapp-frontend`

## 2. Build and Push From Jenkins

Create a Jenkins Pipeline job that points at this repository and uses the root `Jenkinsfile`.

Recommended parameters:

```text
AWS_REGION=ap-south-1
IMAGE_TAG=1.0.0
APP_BASE_URL=http://streamingapp.local
DEPLOY_TO_EKS=false
```

The job builds these images and pushes them to ECR:

```text
<account>.dkr.ecr.ap-south-1.amazonaws.com/streamingapp-auth:1.0.0
<account>.dkr.ecr.ap-south-1.amazonaws.com/streamingapp-streaming:1.0.0
<account>.dkr.ecr.ap-south-1.amazonaws.com/streamingapp-admin:1.0.0
<account>.dkr.ecr.ap-south-1.amazonaws.com/streamingapp-chat:1.0.0
<account>.dkr.ecr.ap-south-1.amazonaws.com/streamingapp-frontend:1.0.0
```

## 3. Create EKS With Terraform

```bash
cd infrastructure/eks/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
terraform output -raw update_kubeconfig_command
aws eks update-kubeconfig --region ap-south-1 --name streamingapp-eks
cd ../../..
```

The Terraform stack creates:

- A dedicated VPC
- Two public subnets for load balancers
- Two private subnets for EKS worker nodes
- Internet gateway and NAT gateway
- EKS control plane
- Managed node group
- VPC CNI, CoreDNS, kube-proxy, and CloudWatch Observability addons

If you only need an `eksctl` reference, it remains at `infrastructure/eks/eksctl/cluster.yaml`.

Configure `kubectl` manually if needed:

```bash
aws eks update-kubeconfig --region ap-south-1 --name streamingapp-eks
```

Install an NGINX Ingress controller:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

## 4. Deploy With Helm

Replace `<account>` with your AWS account id:

```bash
helm upgrade --install streamingapp infrastructure/eks/helm/streamingapp \
  --namespace streamingapp \
  --create-namespace \
  --set global.imageRegistry=<account>.dkr.ecr.ap-south-1.amazonaws.com \
  --set global.imageTag=1.0.0 \
  --set ingress.host=streamingapp.local \
  --set config.clientUrls=http://streamingapp.local \
  --set config.streamingPublicUrl=http://streamingapp.local \
  --set secrets.jwtSecret='<strong-secret>' \
  --wait
```

If uploads/playback use S3, also set:

```bash
--set config.awsS3Bucket=<bucket> \
--set secrets.awsAccessKeyId=<access-key> \
--set secrets.awsSecretAccessKey=<secret-key>
```

## 5. Verify

```bash
kubectl get pods,svc,ingress -n streamingapp
kubectl rollout status deploy/streamingapp-auth -n streamingapp
kubectl rollout status deploy/streamingapp-streaming -n streamingapp
kubectl rollout status deploy/streamingapp-admin -n streamingapp
kubectl rollout status deploy/streamingapp-chat -n streamingapp
kubectl rollout status deploy/streamingapp-frontend -n streamingapp
```

Point `streamingapp.local` to the external address of the NGINX ingress load balancer:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

Then smoke test:

- Register and log in through `http://streamingapp.local`.
- Browse videos through `/api/streaming`.
- Upload a small video and thumbnail from the admin dashboard if S3 is configured.
- Open two browser tabs and confirm chat messages broadcast.
- Delete one pod and confirm Kubernetes recreates it:

```bash
kubectl delete pod -n streamingapp -l app.kubernetes.io/component=frontend
kubectl get pods -n streamingapp -w
```

## Production Notes

For production, replace in-cluster MongoDB with DocumentDB or MongoDB Atlas, enable TLS through cert-manager or AWS ACM, move static AWS keys to IRSA or External Secrets, add HPA policies, use private node groups, and ship application logs to CloudWatch Logs with retention policies.
