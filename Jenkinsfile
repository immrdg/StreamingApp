pipeline {
  agent { label 'ec2-agent' }

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    disableConcurrentBuilds()
  }

  environment {
    // Hardcoded environment variables - no parameters
    AWS_REGION = 'ap-southeast-1'
    AWS_ACCOUNT_ID = credentials('aws-account-id')
    ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    IMAGE_TAG = "${BUILD_NUMBER}"
    APP_BASE_URL = 'http://streamingapp.local'
    K8S_NAMESPACE = 'streamingapp'
  }

  stages {
    stage('Prepare') {
      steps {
        sh '''
          set -eu
          echo "=== Environment Setup ==="
          aws --version
          docker --version
          echo "AWS Account: ${AWS_ACCOUNT_ID}"
          echo "ECR Registry: ${ECR_REGISTRY}"
          echo "Build Tag: ${IMAGE_TAG}"
        '''
      }
    }

    stage('ECR Login') {
      steps {
        sh '''
          set -eu
          echo "Logging into ECR..."
          aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
          
          # Create repositories if they don't exist
          for repo in streamingapp-auth streamingapp-streaming streamingapp-admin streamingapp-chat streamingapp-frontend; do
            aws ecr describe-repositories --repository-names "$repo" --region ${AWS_REGION} >/dev/null 2>&1 ||
              aws ecr create-repository --repository-name "$repo" --region ${AWS_REGION} \
                --image-scanning-configuration scanOnPush=true \
                --encryption-configuration encryptionType=AES256 >/dev/null
          done
          echo "✅ ECR login successful"
        '''
      }
    }

    stage('Build Images') {
      parallel {
        stage('Auth Service') {
          steps {
            sh '''
              echo "Building auth service..."
              docker build -t ${ECR_REGISTRY}/streamingapp-auth:${IMAGE_TAG} \
                -t ${ECR_REGISTRY}/streamingapp-auth:latest \
                backend/authService
            '''
          }
        }
        stage('Streaming Service') {
          steps {
            sh '''
              echo "Building streaming service..."
              docker build -t ${ECR_REGISTRY}/streamingapp-streaming:${IMAGE_TAG} \
                -t ${ECR_REGISTRY}/streamingapp-streaming:latest \
                -f backend/streamingService/Dockerfile backend
            '''
          }
        }
        stage('Admin Service') {
          steps {
            sh '''
              echo "Building admin service..."
              docker build -t ${ECR_REGISTRY}/streamingapp-admin:${IMAGE_TAG} \
                -t ${ECR_REGISTRY}/streamingapp-admin:latest \
                -f backend/adminService/Dockerfile backend
            '''
          }
        }
        stage('Chat Service') {
          steps {
            sh '''
              echo "Building chat service..."
              docker build -t ${ECR_REGISTRY}/streamingapp-chat:${IMAGE_TAG} \
                -t ${ECR_REGISTRY}/streamingapp-chat:latest \
                -f backend/chatService/Dockerfile backend
            '''
          }
        }
        stage('Frontend') {
          steps {
            sh '''
              echo "Building frontend..."
              docker build -t ${ECR_REGISTRY}/streamingapp-frontend:${IMAGE_TAG} \
                -t ${ECR_REGISTRY}/streamingapp-frontend:latest \
                --build-arg REACT_APP_AUTH_API_URL="${APP_BASE_URL}/api/auth" \
                --build-arg REACT_APP_STREAMING_API_URL="${APP_BASE_URL}/api" \
                --build-arg REACT_APP_STREAMING_PUBLIC_URL="${APP_BASE_URL}" \
                --build-arg REACT_APP_ADMIN_API_URL="${APP_BASE_URL}/api/admin" \
                --build-arg REACT_APP_CHAT_API_URL="${APP_BASE_URL}/api/chat" \
                --build-arg REACT_APP_CHAT_SOCKET_URL="${APP_BASE_URL}" \
                frontend
            '''
          }
        }
      }
    }

    stage('Push Images') {
      steps {
        sh '''
          set -eu
          echo "Pushing images to ECR..."
          docker push ${ECR_REGISTRY}/streamingapp-auth:${IMAGE_TAG}
          docker push ${ECR_REGISTRY}/streamingapp-auth:latest
          docker push ${ECR_REGISTRY}/streamingapp-streaming:${IMAGE_TAG}
          docker push ${ECR_REGISTRY}/streamingapp-streaming:latest
          docker push ${ECR_REGISTRY}/streamingapp-admin:${IMAGE_TAG}
          docker push ${ECR_REGISTRY}/streamingapp-admin:latest
          docker push ${ECR_REGISTRY}/streamingapp-chat:${IMAGE_TAG}
          docker push ${ECR_REGISTRY}/streamingapp-chat:latest
          docker push ${ECR_REGISTRY}/streamingapp-frontend:${IMAGE_TAG}
          docker push ${ECR_REGISTRY}/streamingapp-frontend:latest
          echo "✅ All images pushed successfully"
        '''
      }
    }

    stage('Summary') {
      steps {
        sh '''
          cat << 'EOF'
╔═════════════════════════════════════════════════════════════╗
║              ✅ BUILD COMPLETED SUCCESSFULLY                ║
╚═════════════════════════════════════════════════════════════╝

Build Number: ${BUILD_NUMBER}
Images Tagged: ${IMAGE_TAG}
ECR Registry: ${ECR_REGISTRY}
Region: ${AWS_REGION}

Images Available:
✅ streamingapp-auth:${IMAGE_TAG}
✅ streamingapp-streaming:${IMAGE_TAG}
✅ streamingapp-admin:${IMAGE_TAG}
✅ streamingapp-chat:${IMAGE_TAG}
✅ streamingapp-frontend:${IMAGE_TAG}

Next Step: Manual deployment to EKS
  helm upgrade --install streamingapp \\
    ./infrastructure/eks/helm/streamingapp \\
    --namespace ${K8S_NAMESPACE} \\
    --set global.imageRegistry="${ECR_REGISTRY}" \\
    --set global.imageTag="${IMAGE_TAG}"

EOF
        '''
      }
    }
  }

  post {
    always {
      sh 'docker system prune -f 2>/dev/null || true'
    }
    success {
      echo "✅ Pipeline completed successfully"
    }
    failure {
      echo "❌ Pipeline failed - check logs above"
    }
  }
}
