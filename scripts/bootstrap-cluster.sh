#!/bin/bash

# Bootstrap script for EKS clusters
# Creates the initial pod identity association for Fleet bootstrap service account
# This needs to be run once per cluster after the cluster is created

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check required commands
for cmd in aws kubectl jq; do
    if ! command -v $cmd &> /dev/null; then
        print_error "$cmd is required but not installed"
        exit 1
    fi
done

# Parse command line arguments
CLUSTER_NAME=""
AWS_REGION=""
AWS_PROFILE=""
BOOTSTRAP_ROLE_ARN=""
NAMESPACE="cattle-fleet-system"
SERVICE_ACCOUNT="fleet-bootstrap"

usage() {
    cat << EOF
Usage: $0 --cluster-name CLUSTER_NAME --role-arn ROLE_ARN [OPTIONS]

Required arguments:
  --cluster-name NAME       EKS cluster name
  --role-arn ARN           ARN of the Fleet bootstrap IAM role

Optional arguments:
  --region REGION          AWS region (default: from AWS CLI config)
  --profile PROFILE        AWS CLI profile to use
  --namespace NAMESPACE    Kubernetes namespace (default: cattle-fleet-system)
  --service-account SA     Service account name (default: fleet-bootstrap)
  -h, --help              Show this help message

Example:
  $0 --cluster-name my-eks-cluster \\
     --role-arn arn:aws:iam::123456789012:role/ACKFleetBootstrapRole \\
     --region us-west-2 \\
     --profile myprofile
EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --role-arn)
            BOOTSTRAP_ROLE_ARN="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --service-account)
            SERVICE_ACCOUNT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$CLUSTER_NAME" ]; then
    print_error "Cluster name is required"
    usage
fi

if [ -z "$BOOTSTRAP_ROLE_ARN" ]; then
    print_error "Bootstrap role ARN is required"
    usage
fi

# Build AWS CLI command prefix
AWS_CMD="aws"
if [ -n "$AWS_PROFILE" ]; then
    AWS_CMD="$AWS_CMD --profile $AWS_PROFILE"
fi
if [ -n "$AWS_REGION" ]; then
    AWS_CMD="$AWS_CMD --region $AWS_REGION"
fi

print_info "Bootstrap configuration:"
print_info "  Cluster: $CLUSTER_NAME"
print_info "  Role ARN: $BOOTSTRAP_ROLE_ARN"
print_info "  Namespace: $NAMESPACE"
print_info "  Service Account: $SERVICE_ACCOUNT"
print_info ""

# Check if cluster exists
print_info "Verifying cluster exists..."
if ! $AWS_CMD eks describe-cluster --name "$CLUSTER_NAME" &> /dev/null; then
    print_error "Cluster '$CLUSTER_NAME' not found"
    exit 1
fi
print_info "Cluster verified ✓"

# Check if pod identity association already exists
print_info "Checking for existing pod identity association..."
EXISTING_ASSOC=$($AWS_CMD eks list-pod-identity-associations \
    --cluster-name "$CLUSTER_NAME" \
    --namespace "$NAMESPACE" \
    --service-account "$SERVICE_ACCOUNT" \
    --query 'associations[0].associationId' \
    --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_ASSOC" ] && [ "$EXISTING_ASSOC" != "None" ]; then
    print_warn "Pod identity association already exists: $EXISTING_ASSOC"
    read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deleting existing association..."
        $AWS_CMD eks delete-pod-identity-association \
            --cluster-name "$CLUSTER_NAME" \
            --association-id "$EXISTING_ASSOC"
        print_info "Waiting for deletion to complete..."
        sleep 5
    else
        print_info "Keeping existing association. Exiting."
        exit 0
    fi
fi

# Create pod identity association
print_info "Creating pod identity association..."
ASSOCIATION_ARN=$($AWS_CMD eks create-pod-identity-association \
    --cluster-name "$CLUSTER_NAME" \
    --namespace "$NAMESPACE" \
    --service-account "$SERVICE_ACCOUNT" \
    --role-arn "$BOOTSTRAP_ROLE_ARN" \
    --query 'association.associationArn' \
    --output text)

if [ $? -eq 0 ]; then
    print_info "Pod identity association created successfully ✓"
    print_info "Association ARN: $ASSOCIATION_ARN"
    print_info ""
    print_info "Next steps:"
    print_info "1. Ensure $NAMESPACE namespace exists in your cluster"
    print_info "2. The fleet-bootstrap service account will be created by Fleet bundles"
    print_info "3. Deploy Fleet bundles via GitRepo resources"
    print_info "4. Fleet will automatically deploy ACK controllers to this cluster"
else
    print_error "Failed to create pod identity association"
    exit 1
fi
