# Jenkins Setup for StreamingApp CI/CD

## Overview

Jenkins is configured to build Docker images for 5 microservices and push them to AWS ECR. All pipelines use **hardcoded environment variables** (no parameters) and target the **ap-southeast-1 AWS region**.

## Jenkins Credentials Setup

### Required: AWS ECR Credentials

```
ID: aws-ecr-credentials
Type: AWS Credentials
Access Key ID: AKIA...
Secret Access Key: ***
Region: ap-southeast-1
```

**Note**: Pipeline uses `withAWS(credentials: 'aws-ecr-credentials')` to wrap AWS API calls. Account ID is retrieved dynamically via `aws sts get-caller-identity`.

### Optional: GitHub SSH Key

```
ID: github-ssh-key
Type: SSH Username with private key
Username: git
Private Key: [paste your SSH key]
```

### Optional: Slack Webhook

```
ID: slack-webhook-url
Type: Secret text
Value: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

## Creating Jenkins Jobs

### Option A: Declarative Pipeline (Recommended)

All pipelines are defined in `Jenkinsfile` at the project root and individual service directories.

To create jobs:

1. **Go to** Jenkins Dashboard > **New Item**
2. **Enter** Job Name: `streamingapp-build`
3. **Select** Pipeline
4. **Under Pipeline section**, choose **Pipeline script from SCM**
5. **Configure:**
   - **SCM:** Git
   - **Repository URL:** `https://github.com/your-repo/StreamingApp.git`
   - **Branch:** `*/main`
   - **Script Path:** `Jenkinsfile`

6. **Save and Build**

## Pipeline Workflow

### Root Pipeline: `Jenkinsfile`

Builds all 5 services in parallel:

```
Checkout (git)
  ↓
Prepare (get AWS account ID via withAWS)
  ↓
Validate (check Dockerfiles, Helm chart)
  ↓
ECR Login & Setup (create repos if missing)
  ↓
Build Images (parallel)
  ├─ Auth Service
  ├─ Streaming Service
  ├─ Admin Service
  ├─ Chat Service
  └─ Frontend
  ↓
Push to ECR (all images with tags: BUILD_NUMBER, latest, timestamp)
  ↓
Generate Artifact (build manifest)
  ↓
Summary (deployment instructions)
```

## Environment Variables (Hardcoded)

All pipelines use these hardcoded variables:

```bash
AWS_REGION = 'ap-southeast-1'
IMAGE_TAG = "${BUILD_NUMBER}"
BUILD_TIMESTAMP = "${date}"
APP_BASE_URL = 'http://streamingapp.local'
K8S_NAMESPACE = 'streamingapp'
```

**No parameters** are exposed in the UI. All builds use the same configuration.

## Running a Build

### Via Jenkins UI

1. Go to Jenkins Dashboard
2. Click **streamingapp-build** job
3. Click **Build Now** (no parameters to enter)
4. Monitor build progress in **Console Output**

### Via Jenkins CLI

```bash
java -jar jenkins-cli.jar -s http://jenkins.streamingapp.local \
  build streamingapp-build
```

### Via curl

```bash
curl -X POST http://jenkins.streamingapp.local/job/streamingapp-build/build \
  --user admin:token
```

## Build Output

After successful build, you'll see:

```
✅ BUILD COMPLETED SUCCESSFULLY

Build Details:
  Build Number:    123
  Build Timestamp: 20250913_143022
  Image Tag:       123
  Git Commit:      a1b2c3d (main)

AWS Details:
  Region:          ap-southeast-1
  Account:         123456789012
  ECR Registry:    123456789012.dkr.ecr.ap-southeast-1.amazonaws.com

Docker Images (pushed to ECR):
  ✅ streamingapp-auth:123
  ✅ streamingapp-streaming:123
  ✅ streamingapp-admin:123
  ✅ streamingapp-chat:123
  ✅ streamingapp-frontend:123

Alternative tags:
  - :latest (always points to latest build)
  - :20250913_143022 (timestamped release)

Next Step - Manual Helm Deployment:
  helm upgrade --install streamingapp \
    ./infrastructure/eks/helm/streamingapp \
    --namespace streamingapp \
    --create-namespace \
    --set global.imageRegistry="123456789012.dkr.ecr.ap-southeast-1.amazonaws.com" \
    --set global.imageTag="123" \
    --wait \
    --timeout 10m
```

## Troubleshooting

### ECR Authentication Failures

```bash
# Verify AWS credentials in Jenkins
# Manage Jenkins > Manage Credentials > System > Global credentials

# Test AWS CLI locally
aws sts get-caller-identity
aws ecr get-login-password --region ap-southeast-1
```

### Build Failures

Check logs in:
1. Jenkins Console Output
2. Docker daemon logs (if Docker issues)

### Docker Permission Issues

```bash
# Add jenkins user to docker group
sudo usermod -aG docker jenkins

# Restart Jenkins
sudo systemctl restart jenkins
```

## Production Best Practices

✅ **Implemented in this pipeline:**

- No hardcoded secrets in Jenkinsfile
- AWS credentials via `withAWS` plugin
- Parallel builds for faster execution
- Build artifact archiving (manifest.json)
- Comprehensive error handling
- Post-build cleanup (docker system prune)
- Build logging and retention
- Multiple image tags (BUILD_NUMBER, latest, timestamp)
- Deployment instructions in console output

## Next Steps

After Jenkins is fully configured:

1. **Create Jenkins job** from SCM pointing to root `Jenkinsfile`
2. **Configure aws-ecr-credentials** credential in Jenkins
3. **Trigger a build** to verify all 5 services build successfully
4. **Verify images in ECR** - 5 repos with latest tag
5. **Prepare for EKS deployment** using Helm
6. **Setup monitoring** - Jenkins + Slack/Email notifications

---

For more details, see:
- `../../Jenkinsfile` - All-services build pipeline (production grade)
- `../../backend/*/Jenkinsfile` - Individual service builds
- `../../frontend/Jenkinsfile` - Frontend build pipeline
