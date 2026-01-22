#!/bin/bash
# S3 Template Upload Script
# This script uploads CloudFormation templates to S3

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="eu-west-2"
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

# Generate bucket name with timestamp to ensure uniqueness
BUCKET_NAME="${BUCKET_PREFIX}-$(date +%s)"

print_status "Creating S3 bucket: $BUCKET_NAME"
if aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION; then
  print_status "S3 bucket created successfully"
else
  print_error "Failed to create S3 bucket"
  exit 1
fi

# Wait a moment for bucket to be ready
sleep 2

print_status "Uploading CloudFormation templates to S3..."
if aws s3 cp templates/ s3://$BUCKET_NAME/templates/ --recursive --region $AWS_REGION; then
  print_status "Templates uploaded successfully"
else
  print_error "Failed to upload templates"
  exit 1
fi

print_status "S3 bucket name: $BUCKET_NAME"
print_status "Use this bucket name when deploying:"
echo -e "${GREEN}./deploy-stack.sh $BUCKET_NAME${NC}"

# Save bucket name to file for reference
echo $BUCKET_NAME > .s3-bucket-name
print_status "Bucket name saved to .s3-bucket-name file"

print_status "Upload complete!"
