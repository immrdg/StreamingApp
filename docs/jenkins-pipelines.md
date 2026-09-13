# Jenkins Build Pipelines Setup for StreamingApp

## Overview

This guide walks through setting up Jenkins build pipelines that securely push container images to Amazon ECR using IAM instance profiles (no hardcoded credentials).

**Infrastructure Summary:**
- **Jenkins URL:** http://ec2-13-229-125-244.ap-southeast-1.compute.amazonaws.com:8080
- **Default Credentials:** admin / admin
- **Region:** ap-southeast-1 (Singapore)
- **EC2 Instance Type:** m7i-flex.large
- **EKS Cluster:** streamingapp-eks (K8s 1.36)

## Security Architecture

✅ **No AWS credentials stored in Jenkins**
- Jenkins EC2 instance has IAM instance profile with ECR access
- Pipelines use `aws sts get-caller-identity` to resolve account ID
- Docker login via `aws ecr get-login-password` with IAM temporary credentials
- All ECR operations work automatically via IAM role

## ECR Setup (Completed)

Created 5 ECR repositories in ap-southeast-1:
- `258274811560.dkr.ecr.ap-southeast-1.amazonaws.com/streamingapp-auth`
- `258274811560.dkr.ecr.ap-southeast-1.amazonaws.com/streamingapp-streaming`
- `258274811560.dkr.ecr.ap-southeast-1.amazonaws.com/streamingapp-admin`
- `258274811560.dkr.ecr.ap-southeast-1.amazonaws.com/streamingapp-chat`
- `258274811560.dkr.ecr.ap-southeast-1.amazonaws.com/streamingapp-frontend`

All repositories have:
- Image scanning enabled
- AES256 encryption
- Automatic cleanup policies (image retention: 20 builds)

## Jenkins Job Setup

### Step 1: Access Jenkins UI

```bash
# Update kubeconfig to your cluster (optional, for future EKS operations)
aws eks update-kubeconfig --region ap-southeast-1 --name streamingapp-eks --profile siraj

# Open Jenkins (via SSH tunnel if behind firewall)
# http://ec2-13-229-125-244.ap-southeast-1.compute.amazonaws.com:8080
# Login: admin / admin
```

### Step 2: Create Pipeline Jobs in Jenkins

For each microservice, create a new Pipeline job:

#### Job Configuration (example for Auth Service):

1. **Click "New Item"** → Enter job name: `StreamingApp-Auth` → Select **Pipeline** → Click OK

2. **General Tab:**
   - Enable: "This project is parameterized"
   - Add parameters:
     ```
     - String: AWS_REGION = ap-southeast-1
     - String: IMAGE_TAG = 1.0.0
     - Boolean: PUSH_TO_ECR = true
     ```

3. **Pipeline Tab:**
   - Definition: **Pipeline script from SCM** (if using Git) or **Pipeline script** (paste below)
   - Paste content from `pipelines/auth.Jenkinsfile`

4. **Repeat for all services:**
   - `StreamingApp-Streaming` → `pipelines/streaming.Jenkinsfile`
   - `StreamingApp-Admin` → `pipelines/admin.Jenkinsfile`
   - `StreamingApp-Chat` → `pipelines/chat.Jenkinsfile`
   - `StreamingApp-Frontend` → `pipelines/frontend.Jenkinsfile`

### Step 3: Configure Job Defaults (Optional)

Add these configuration steps in Jenkins **Manage Jenkins → Configure System:**

#### Job Properties:
- Set log retention: 20 builds
- Enable timestamps on all logs

#### Environment Defaults:
- `AWS_REGION`: ap-southeast-1
- `IMAGE_TAG`: 1.0.0

## Running a Pipeline Job

### Method 1: Manual Trigger

1. Select job (e.g., `StreamingApp-Auth`)
2. Click **"Build with Parameters"**
3. Modify parameters as needed:
   - `AWS_REGION`: ap-southeast-1
   - `IMAGE_TAG`: 1.0.0 (or your version)
   - `PUSH_TO_ECR`: true
4. Click **Build**
5. Monitor progress in **Build Output**

### Method 2: Trigger from Git Push (Optional)

If using GitHub:

1. Go to repo Settings → Webhooks → Add webhook
   - Payload URL: `http://jenkins-url:8080/github-webhook/`
   - Content type: `application/json`
   - Trigger on: Push events

2. In Jenkins job: **Build Triggers** → Check **GitHub hook trigger for GITScm polling**

## Pipeline Stages Explained

Each Jenkinsfile includes:

| Stage | Purpose |
|-------|---------|
| **Prepare** | Resolve AWS account ID and ECR registry from IAM role |
| **Docker Login** | Authenticate with ECR using `aws ecr get-login-password` |
| **Ensure Repository** | Create ECR repository if it doesn't exist |
| **Build Image** | Build Docker image locally with Dockerfile |
| **Push to ECR** | Push image tags to ECR (conditional) |
| **Cleanup** | Remove local images to free space |

## Example: Build Auth Service

```bash
# Manual trigger
curl -X POST http://jenkins-url:8080/job/StreamingApp-Auth/buildWithParameters \
  -u admin:admin \
  -d 'AWS_REGION=ap-southeast-1&IMAGE_TAG=1.0.0&PUSH_TO_ECR=true'

# Check build console output
# Expected output:
#   ✓ Docker Login → ECR login successful
#   ✓ Ensure Repository → Repository verified
#   ✓ Build Image → Build complete
#   ✓ Push to ECR → Push complete: 258274811560.dkr.ecr.ap-southeast-1.amazonaws.com/streamingapp-auth:1.0.0
```

## Verify Images in ECR

```bash
# List images in Auth repository
aws ecr describe-images \
  --repository-name streamingapp-auth \
  --region ap-southeast-1 \
  --profile siraj \
  --query 'imageDetails[*].[imageTags, imageSizeInBytes, imagePushedAt]' \
  --output table

# Pull an image for testing
aws ecr get-login-password --region ap-southeast-1 --profile siraj | \
  docker login --username AWS --password-stdin 258274811560.dkr.ecr.ap-southeast-1.amazonaws.com

docker pull 258274811560.dkr.ecr.ap-southeast-1.amazonaws.com/streamingapp-auth:1.0.0
```

## Jenkins Credentials (Next Steps)

Currently, pipelines use IAM roles. To add additional credentials for GitHub/EKS:

1. Go to **Manage Jenkins** → **Manage Credentials** → **(global)**
2. Click **Add Credentials** → **SSH Username with private key** (for GitHub)
3. Store GitHub SSH key or personal access token
4. Reference in pipelines:
   ```groovy
   withCredentials([sshUserPrivateKey(credentialsId: 'github-ssh-key', keyFileVariable: 'SSH_KEY')]) {
     sh 'git clone git@github.com:user/repo.git'
   }
   ```

## Monitoring & Logs

### Jenkins Logs
- **Build Console Output:** Click build → **Console Output**
- **System Logs:** **Manage Jenkins** → **System Log**

### EC2 Cloud Agents
- **View Agents:** **Manage Jenkins** → **Manage Nodes and Clouds** → **streamingapp-ec2-agents**
- **Agent Logs:** Click agent → **System Log**

### ECR Scan Results
```bash
# Check image scan findings
aws ecr describe-image-scan-findings \
  --repository-name streamingapp-auth \
  --image-id imageTag=1.0.0 \
  --region ap-southeast-1 \
  --profile siraj
```

## Troubleshooting

### Issue: "Error getting ECR login token"
**Cause:** IAM instance profile not attached or missing permissions
**Solution:** Verify Jenkins EC2 instance has `AmazonEC2ContainerRegistryPowerUser` policy

```bash
aws iam list-instance-profiles-for-role \
  --role-name streamingapp-jenkins-ec2 \
  --profile siraj
```

### Issue: "Repository not found"
**Cause:** ECR repository doesn't exist in specified region
**Solution:** Pipeline auto-creates it, or manually:

```bash
aws ecr create-repository \
  --repository-name streamingapp-auth \
  --region ap-southeast-1 \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256 \
  --profile siraj
```

### Issue: "Docker build failed"
**Cause:** Dockerfile not found or context path wrong
**Solution:** Check Jenkinsfile path and ensure agent has Docker access

```bash
# On Jenkins agent
docker ps  # Should work without sudo
```

## Next Steps

1. **GitHub Integration:** Connect repositories to Jenkins for webhook-triggered builds
2. **EKS Deployment:** Create Helm deployment pipeline that pulls ECR images
3. **Image Scanning:** Set up automated security scanning on push
4. **Retention Policy:** Implement ECR lifecycle policies to clean old images
5. **Notifications:** Add Slack/email notifications on build success/failure

## References

- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)
- [Jenkins Pipeline Documentation](https://www.jenkins.io/doc/book/pipeline/)
- [EC2 Cloud Plugin](https://plugins.jenkins.io/ec2/)
- [StreamingApp Architecture](../README.md)
