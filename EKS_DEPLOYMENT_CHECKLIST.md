# StreamingApp EKS Deployment Checklist

## Pre-Deployment Phase

### Infrastructure Setup
- [ ] AWS Account set up with proper IAM roles
- [ ] EKS cluster created and running (1.27+)
- [ ] Node group scaled appropriately (minimum 3 nodes recommended)
- [ ] Security groups configured
- [ ] VPC and subnets configured
- [ ] IAM roles for pods configured (IRSA for S3 access)

### ECR Setup
- [ ] ECR repositories created for all 5 services
- [ ] Image scanning enabled
- [ ] Lifecycle policies configured
- [ ] Repository permissions set

### Docker Images
- [ ] All 5 services built locally and tested
- [ ] Dockerfile optimizations applied (multi-stage, caching)
- [ ] Security scanning passed
- [ ] Images tagged with version and latest
- [ ] Images pushed to ECR

### Jenkins Configuration
- [ ] Jenkins server accessible
- [ ] AWS credentials configured in Jenkins
- [ ] Git repository access configured
- [ ] Jenkinsfile reviewed and tested
- [ ] Email notifications configured

## Kubernetes Cluster Setup

### Cluster Components
- [ ] kubectl configured and tested
- [ ] kubeconfig updated with EKS credentials
- [ ] Metrics server installed (for kubectl top)
- [ ] Nginx ingress controller installed
- [ ] Storage provisioner configured (gp2/gp3 StorageClass)

### RBAC & Security
- [ ] Service accounts created for pods
- [ ] IAM roles bound to service accounts
- [ ] Pod Security Policies reviewed
- [ ] Network policies considered

### Namespaces
- [ ] `streamingapp` namespace created
- [ ] `streamingapp-staging` namespace created (optional)
- [ ] `ingress-nginx` namespace verified
- [ ] Resource quotas set per namespace (optional)

## Helm Configuration

### Chart Preparation
- [ ] Helm 3.x installed and verified
- [ ] Chart dependencies resolved
- [ ] Chart values reviewed and customized
- [ ] Secrets file created and secured
- [ ] Environment-specific values files created

### Configuration Files
- [ ] `values.yaml` reviewed
- [ ] `values-prod.yaml` configured with production settings
- [ ] `values-staging.yaml` configured with staging settings
- [ ] Resource limits appropriate for workload
- [ ] Replica counts set for high availability

### Secrets Management
- [ ] JWT secret generated (min 32 chars)
- [ ] AWS credentials for S3 stored securely
- [ ] Database credentials secured
- [ ] TLS certificates ready (optional)
- [ ] Kubernetes secrets created in cluster

## Database Configuration

### MongoDB Setup
- [ ] PersistentVolumeClaim size appropriate
- [ ] StorageClass selected (gp2 for dev, gp3 for prod)
- [ ] Backup strategy defined
- [ ] Restore procedure tested
- [ ] Initial data seed prepared

### Data
- [ ] Sample videos uploaded to S3
- [ ] Thumbnails generated and uploaded
- [ ] Admin user created in database
- [ ] Database connection string verified

## AWS Infrastructure

### S3 Bucket
- [ ] Bucket created: `streamingapp-videos-1789299262`
- [ ] Bucket versioning enabled
- [ ] Server-side encryption enabled
- [ ] Public access blocked
- [ ] CORS configured for frontend domain
- [ ] Sample videos uploaded to `videos/` prefix
- [ ] Thumbnails uploaded to `thumbnails/` prefix

### IAM Permissions
- [ ] IAM user/role created with S3 access
- [ ] ECR push/pull permissions configured
- [ ] EKS cluster admin role created
- [ ] Service account IAM role created (IRSA)
- [ ] Trust relationships configured

### CloudFormation/Terraform
- [ ] Infrastructure as Code reviewed
- [ ] All resources documented
- [ ] Stack parameters validated
- [ ] Rollback procedure tested

## Networking & DNS

### Network Configuration
- [ ] VPC CIDR blocks don't overlap
- [ ] Subnet routing verified
- [ ] Security groups allow necessary traffic
- [ ] NAT gateways configured for private subnets
- [ ] VPC Flow Logs enabled (optional)

### Ingress & DNS
- [ ] Ingress class set to nginx
- [ ] Ingress rules configured
- [ ] DNS domain purchased and verified
- [ ] DNS records created (Route53 or registrar)
- [ ] TLS certificate obtained or configured (cert-manager)

### Load Balancer
- [ ] Ingress creates NLB/ALB successfully
- [ ] External IP/hostname assigned
- [ ] Load balancer health checks passing
- [ ] SSL/TLS termination verified

## Application Configuration

### Environment Variables
- [ ] MONGO_URI points to cluster MongoDB
- [ ] AWS_REGION set correctly
- [ ] AWS_S3_BUCKET set to production bucket
- [ ] JWT_SECRET set to strong value
- [ ] CLIENT_URLS points to correct domain
- [ ] STREAMING_PUBLIC_URL configured
- [ ] ADMIN_AUTH_BYPASS disabled for production

### Frontend Configuration
- [ ] REACT_APP_AUTH_API_URL correct
- [ ] REACT_APP_STREAMING_API_URL correct
- [ ] REACT_APP_ADMIN_API_URL correct
- [ ] REACT_APP_CHAT_API_URL correct
- [ ] REACT_APP_SKIP_AUTH set to false for production

### Service Discovery
- [ ] Service names resolvable from pods
- [ ] Cross-service communication tested
- [ ] Port numbers verified
- [ ] Health check endpoints verified

## Deployment Execution

### Pre-Deployment
- [ ] All checklist items above completed
- [ ] Database backed up
- [ ] Rollback plan documented
- [ ] On-call engineer identified
- [ ] Stakeholders notified of deployment window

### Helm Deployment
- [ ] Helm chart validated: `helm lint`
- [ ] Dry-run executed: `helm upgrade --dry-run`
- [ ] Deployment command prepared
- [ ] Namespace exists: `kubectl create namespace streamingapp`
- [ ] Secrets created in namespace
- [ ] Helm release installed successfully

### Post-Deployment Verification
- [ ] All pods running: `kubectl get pods -n streamingapp`
- [ ] All services running: `kubectl get svc -n streamingapp`
- [ ] Ingress routes created: `kubectl get ingress -n streamingapp`
- [ ] Pod readiness probes passing
- [ ] Pod liveness probes passing
- [ ] No pending pods or errors

## Smoke Testing

### Basic Connectivity
- [ ] kubectl can access cluster
- [ ] pods can communicate with each other
- [ ] Services have endpoints
- [ ] DNS resolution working in pods

### API Testing
- [ ] Frontend loads at domain URL
- [ ] Auth API responding: `/api/health`
- [ ] Streaming API responding: `/api/streaming/health`
- [ ] Admin API responding: `/api/admin/health`
- [ ] Chat API responding: `/api/chat/health`

### Feature Testing
- [ ] Video list loads
- [ ] Featured videos display
- [ ] Thumbnails load from S3
- [ ] Video streaming works (206 Partial Content)
- [ ] Video seeking/scrubbing works
- [ ] Admin panel accessible
- [ ] Chat functionality working

### Performance Testing
- [ ] Home page loads < 2 seconds
- [ ] API responses < 500ms
- [ ] Video streaming bitrate appropriate
- [ ] No memory leaks in pods
- [ ] CPU usage within limits

## Security Verification

### Container Security
- [ ] Images scanned for vulnerabilities
- [ ] No secrets in images
- [ ] Images signed (optional)
- [ ] Registry access restricted

### Kubernetes Security
- [ ] Network policies evaluated
- [ ] Pod Security Policy/Standards applied
- [ ] RBAC roles follow least privilege
- [ ] Secrets encrypted at rest
- [ ] Audit logging enabled

### Application Security
- [ ] HTTPS enforced
- [ ] CORS configured correctly
- [ ] SQL injection not possible (using ORM)
- [ ] Authentication working
- [ ] Authorization enforced

## Monitoring & Alerting

### Logging
- [ ] Pod logs accessible via kubectl
- [ ] Logs aggregation service configured (optional)
- [ ] Log retention policy set
- [ ] Error log alerts configured

### Metrics
- [ ] Metrics server installed and working
- [ ] kubectl top commands working
- [ ] Pod resource metrics available
- [ ] Node resource metrics available

### Monitoring Tools
- [ ] Prometheus installed (optional)
- [ ] Grafana dashboards created (optional)
- [ ] Alert rules configured (optional)
- [ ] On-call alert routing configured

## Documentation

### Deployment Documentation
- [ ] EKS_DEPLOYMENT_GUIDE.md reviewed
- [ ] Environment variables documented
- [ ] Configuration options explained
- [ ] Troubleshooting guide prepared

### Runbook Documentation
- [ ] Deployment procedure documented
- [ ] Rollback procedure documented
- [ ] Scaling procedure documented
- [ ] Troubleshooting procedures documented
- [ ] Emergency contacts documented

### Architecture Documentation
- [ ] Architecture diagram created
- [ ] Service dependencies documented
- [ ] Data flow documented
- [ ] Backup/recovery procedure documented

## Post-Deployment

### Monitoring Phase
- [ ] First 24 hours monitored closely
- [ ] No critical errors reported
- [ ] Performance metrics normal
- [ ] Logs reviewed for warnings
- [ ] User feedback collected

### Optimization Phase
- [ ] Resource utilization reviewed
- [ ] Pod replica counts optimized
- [ ] Resource limits fine-tuned
- [ ] Cache policies reviewed
- [ ] Database indexes verified

### Maintenance Tasks
- [ ] Backup schedule set up
- [ ] Security patches scheduled
- [ ] Certificate renewal scheduled
- [ ] Dependency updates scheduled
- [ ] Documentation updated

## Sign-Off

- [ ] **QA Lead**: Smoke tests passed
  - Name: ________________  Date: ________  Signature: ________________

- [ ] **DevOps Engineer**: Infrastructure verified
  - Name: ________________  Date: ________  Signature: ________________

- [ ] **Engineering Manager**: Ready for production
  - Name: ________________  Date: ________  Signature: ________________

---

## Emergency Contact Information

**On-Call Engineer**: [Name/Phone]  
**Escalation Contact**: [Name/Phone]  
**AWS Support**: [Account ID / Contact]  
**Database Admin**: [Name/Phone]  

## Rollback Authority

**Authorized to roll back without approval**: [Names]  
**Requires approval to roll back**: [Approval Chain]  
**Approval contact during non-business hours**: [Name/Phone]

---

**Deployment Date**: _____________  
**Deployed By**: _____________  
**Release Version**: _____________  
**Notes**: _________________________________________________________________

