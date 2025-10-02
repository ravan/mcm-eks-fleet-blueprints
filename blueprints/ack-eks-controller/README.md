# ACK EKS Controller Fleet Bundle

This Fleet bundle deploys the AWS Controllers for Kubernetes (ACK) EKS controller with EKS Pod Identity authentication.

## Overview

The ACK EKS controller enables management of AWS EKS resources (clusters, node groups, Fargate profiles, pod identity associations) through Kubernetes CRDs. This controller is essential for creating pod identity associations for other ACK controllers declaratively.

## Components

1. **chart/**: Wrapper Helm chart containing:
   - `templates/bootstrap-hook.yaml`: Pre-install Helm hook (bootstrap Job)
   - `Chart.yaml`: Declares eks-chart subchart dependency from OCI registry
   - `values.yaml`: Default values and bootstrap configuration
2. **fleet.yaml**: Fleet configuration with cluster-specific value injection

## Prerequisites

See the main [README](../README.md#prerequisites) for complete setup instructions including:

1. CloudFormation stack deployment (creates IAM roles)
2. Per-cluster bootstrap script (creates pod identity association for fleet-bootstrap SA)
3. Pod Identity Agent deployment (Bundle 0)

### Required Cluster Labels

- `cluster-type: eks`
- `cluster-name: <eks-cluster-name>`
- `aws-region: <region>`
- `aws-account-id: <account-id>`
- `ack-eks-role-name: <role-name>` (e.g., `ACKEKSControllerRole` - not full ARN)

## How It Works

### Bootstrap Hook (Pre-Install)

1. Fleet deploys the wrapper Helm chart with `targetCustomizations` injecting cluster-specific values
2. Helm pre-install hook creates fleet-bootstrap ServiceAccount (if not exists)
3. Bootstrap Job executes using fleet-bootstrap SA:
   - Uses AWS CLI to check for existing pod identity association
   - Creates or updates pod identity association for `ack-eks-controller` ServiceAccount
   - Associates with IAM role: `arn:aws:iam::{aws-account-id}:role/{ack-eks-role-name}`
   - Waits for credentials to propagate
4. Hook completes successfully

### Controller Deployment

5. Helm deploys eks-chart subchart from OCI registry
6. Controller pod starts with `ack-eks-controller` ServiceAccount
7. Pod Identity Agent provides AWS credentials via the pod identity association
8. Controller starts successfully and can manage EKS resources

## Fleet Configuration

Fleet injects cluster-specific values via `targetCustomizations`:

```yaml
targetCustomizations:
  - name: eks-clusters
    clusterSelector:
      matchLabels:
        cluster-type: eks
    helm:
      values:
        clusterName: ${ index .ClusterLabels "cluster-name" }
        awsRegion: ${ index .ClusterLabels "aws-region" }
        awsAccountId: ${ index .ClusterLabels "aws-account-id" | quote }
        ackEksRoleName: ${ index .ClusterLabels "ack-eks-role-name" }
        eks-chart:
          aws:
            region: ${ index .ClusterLabels "aws-region" }
```

The bootstrap hook uses these values to construct the IAM role ARN and create the pod identity association.

## Dependencies

- **Pod Identity Agent** (Bundle 0): Must be deployed first - defined in `fleet.yaml`:
  ```yaml
  dependsOn:
    - name: eks-pod-identity-agent-blueprints-pod-identity-agent
  ```

## Verification

```bash
# Check bootstrap Job status
kubectl get jobs -n cattle-fleet-system -l app.kubernetes.io/component=bootstrap

# Check bootstrap Job logs
kubectl logs -n cattle-fleet-system -l app.kubernetes.io/component=bootstrap

# Check controller deployment
kubectl get pods -n ack-system -l app.kubernetes.io/name=eks-chart

# Verify pod identity association was created
kubectl get podidentityassociations -n ack-system
```

## Troubleshooting

See the main [README Troubleshooting section](../README.md#troubleshooting) for common issues.

## Next Steps

Once deployed, the ACK EKS controller can manage:
- **PodIdentityAssociation CRDs**: Create pod identity associations for other controllers declaratively
- **EKS Clusters**: Manage EKS clusters as Kubernetes resources
- **Node Groups**: Manage EKS node groups
- **Fargate Profiles**: Manage EKS Fargate profiles

Deploy ACK IAM controller next (Bundle 2), which uses a PodIdentityAssociation CRD for authentication.
