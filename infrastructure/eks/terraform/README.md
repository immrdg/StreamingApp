# EKS Terraform

Creates the AWS infrastructure for StreamingApp:

- Dedicated VPC
- Two public subnets for load balancers
- Two private subnets for EKS worker nodes
- Internet gateway and one NAT gateway
- EKS control plane
- Managed node group
- Core EKS addons plus CloudWatch Observability

## Usage

```bash
cd infrastructure/eks/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Configure `kubectl`:

```bash
terraform output -raw update_kubeconfig_command
aws eks update-kubeconfig --region ap-south-1 --name streamingapp-eks
```

Then deploy the app with Helm:

```bash
helm upgrade --install streamingapp ../helm/streamingapp \
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

## Cost Note

The default private-node setup creates one NAT Gateway, which has hourly and data-processing cost. For a short assignment demo, destroy the stack when finished:

```bash
terraform destroy
```
