# ACK EKS Controller Fleet Bundle

Deploys the AWS Controllers for Kubernetes (ACK) EKS controller with EKS Pod Identity authentication.

## Overview

The ACK EKS controller manages AWS EKS resources (clusters, node groups, Fargate profiles, pod identity associations) through Kubernetes CRDs. This controller is essential for creating pod identity associations for other ACK controllers declaratively.

## Prerequisites

1. CloudFormation stack deployed (creates IAM roles)
2. Per-cluster bootstrap script executed (creates pod identity association for fleet-bootstrap SA)
3. Pod Identity Agent deployed (Bundle 0)

### Required Cluster Labels

- `cluster-type: eks`
- `cluster-name: <eks-cluster-name>`
- `aws-region: <region>`
- `aws-account-id: <account-id>`
- `ack-eks-role-name: <role-name>` (default: `MCMACKEKSControllerRole`)

## How It Works

1. Fleet deploys the chart from Helm repository with cluster-specific values injected via `targetCustomizations`
2. The `ack-eks-bootstrap` subchart creates pod identity association for the controller's service account using AWS CLI
3. Controller pod starts with AWS credentials provided by Pod Identity Agent
4. Controller reconciles PodIdentityAssociation CRDs for other ACK controllers

## Dependencies

Requires Pod Identity Agent (Bundle 0) deployed first.

## Verification

```bash
# Check controller deployment
kubectl get pods -n ack-system -l app.kubernetes.io/name=ack-eks-controller

# Verify pod identity association created
aws eks list-pod-identity-associations \
  --cluster-name <cluster-name> \
  --region <region>
```

## Capabilities

Once deployed, the controller manages:
- PodIdentityAssociation CRDs (enables declarative pod identity for other controllers)
- EKS clusters
- Node groups
- Fargate profiles
