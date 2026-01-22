#!/bin/bash
# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="eu-west-2"
STACK_NAME="cicd-ecr-main-stack"
ECR_REPO_NAME="cicd-ecr-app"
BUCKET_PREFIX="cicd-ecr-templates"

# Function to print colored output
print_status() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
  print_error "AWS CLI is not installed. Please install it first."
  exit 1
fi

# Check if S3 bucket name is provided, otherwise create one
if [ -z "$1" ]; then
  print_status "No S3 bucket provided. Creating and uploading templates..."
  
  # Generate bucket name with timestamp
  TEMPLATES_BUCKET="${BUCKET_PREFIX}-$(date +%s)"
  
  print_status "Creating S3 bucket: $TEMPLATES_BUCKET"
  if ! aws s3 mb s3://$TEMPLATES_BUCKET --region $AWS_REGION; then
    print_error "Failed to create S3 bucket"
    exit 1
  fi
  
  # Wait for bucket to be ready
  sleep 2
  
  print_status "Uploading CloudFormation templates to S3..."
  if ! aws s3 cp templates/ s3://$TEMPLATES_BUCKET/templates/ --recursive --region $AWS_REGION; then
    print_error "Failed to upload templates to S3"
    exit 1
  fi
else
  TEMPLATES_BUCKET="$1"
  print_status "Using provided S3 bucket: $TEMPLATES_BUCKET"
fi

# Check if ECR repository exists, create if not
print_status "Checking ECR Repository..."
if aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION 2>/dev/null; then
  print_status "ECR Repository already exists"
  ECR_URI=$(aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text)
else
  print_status "Creating ECR Repository..."
  aws ecr create-repository --repository-name $ECR_REPO_NAME --region $AWS_REGION
  ECR_URI=$(aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text)
fi

print_status "ECR Repository URI: $ECR_URI"

# Build and push Docker image
print_status "Building Docker image..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI
docker build -t $ECR_REPO_NAME:latest app/
docker tag $ECR_REPO_NAME:latest $ECR_URI:latest

print_status "Pushing image to ECR..."
docker push $ECR_URI:latest

# Deploy CloudFormation stack
print_status "Deploying CloudFormation stack..."
aws cloudformation deploy \
  --template-file infra/main.yaml \
  --stack-name $STACK_NAME \
  --parameter-overrides \
    ECRImageUri=$ECR_URI:latest \
    TemplatesBucket=$TEMPLATES_BUCKET \
  --region $AWS_REGION \
  --capabilities CAPABILITY_NAMED_IAM

if [ $? -eq 0 ]; then
  print_status "Stack deployment completed successfully!"
  
  # Get ALB DNS Name
  ALB_DNS=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $AWS_REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBDNSName`].OutputValue' \
    --output text)
  
  print_status "ALB DNS Name: http://$ALB_DNS"
  print_status "S3 Bucket Used: $TEMPLATES_BUCKET"
else
  print_error "Stack deployment failed!"
  print_error "For debugging, run:"
  echo "  aws cloudformation describe-stack-events --stack-name $STACK_NAME --region $AWS_REGION"
  exit 1
fi
