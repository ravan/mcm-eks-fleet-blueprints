# ACK IAM Controller Fleet Bundle

Deploys the AWS Controllers for Kubernetes (ACK) IAM controller with EKS Pod Identity authentication.

## Overview

The ACK IAM controller manages AWS IAM resources (roles, policies, users, groups, OIDC providers) through Kubernetes CRDs, enabling declarative IAM infrastructure management.

## Prerequisites

1. CloudFormation stack deployed (creates IAM roles)
2. Per-cluster bootstrap script executed (creates pod identity association for fleet-bootstrap SA)
3. Pod Identity Agent deployed (Bundle 0)
4. **ACK EKS Controller deployed (Bundle 1)** - Required to reconcile PodIdentityAssociation CRDs

### Required Cluster Labels

- `cluster-type: eks`
- `cluster-name: <eks-cluster-name>`
- `aws-region: <region>`
- `aws-account-id: <account-id>`
- `ack-iam-role-name: <role-name>` (default: `MCMACKIAMControllerRole`)

## How It Works

1. Fleet deploys the chart from Helm repository with cluster-specific values injected via `targetCustomizations`
2. The `ack-pod-identity-association` subchart creates a PodIdentityAssociation CRD
3. ACK EKS controller reconciles the CRD and creates the actual AWS pod identity association
4. Controller pod starts with AWS credentials provided by Pod Identity Agent
5. Controller manages IAM resources via CRDs

## Dependencies

Requires ACK EKS Controller (Bundle 1) to reconcile PodIdentityAssociation CRDs.

## Verification

```bash
# Check controller deployment
kubectl get pods -n ack-system -l app.kubernetes.io/name=ack-iam-controller

# Check PodIdentityAssociation CRD
kubectl get podidentityassociation -n ack-system

# Test with a sample IAM Policy
kubectl apply -f - <<EOF
apiVersion: iam.services.k8s.aws/v1alpha1
kind: Policy
metadata:
  name: test-policy
spec:
  name: TestPolicy
  policyDocument: |
    {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Action": ["s3:ListBucket"],
        "Resource": "*"
      }]
    }
EOF

kubectl get policy test-policy
```

## Capabilities

Once deployed, the controller manages:
- IAM Roles
- IAM Policies
- IAM Users
- IAM Groups
- OIDC Providers
