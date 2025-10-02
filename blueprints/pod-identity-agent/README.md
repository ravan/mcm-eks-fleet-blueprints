# EKS Pod Identity Agent Fleet Bundle

This Fleet bundle deploys the EKS Pod Identity Agent DaemonSet to all EKS clusters. The Pod Identity Agent is required for EKS Pod Identity authentication to work.

## Overview

The EKS Pod Identity Agent runs as a DaemonSet on every node and provides AWS credentials to pods that have an associated pod identity association. This is the foundational component required for all ACK controllers to authenticate with AWS.

## Implementation

**Deployment Method**: Direct Helm chart from GitHub repository using Fleet's git source support

**Source**: `git::https://github.com/aws/eks-pod-identity-agent.git//charts/eks-pod-identity-agent?ref=main`

**Namespace**: `kube-system`

## Configuration

Fleet injects cluster-specific values using `targetCustomizations` in `fleet.yaml`:

```yaml
targetCustomizations:
  - name: eks-clusters
    clusterSelector:
      matchLabels:
        cluster-type: eks
    helm:
      values:
        clusterName: ${ index .ClusterLabels "cluster-name" }
        env:
          AWS_REGION: ${ index .ClusterLabels "aws-region" }
```

## Required Cluster Labels

Clusters must be labeled in Rancher with:

| Label | Description | Example |
|-------|-------------|---------|
| `cluster-type` | Cluster type | `eks` |
| `cluster-name` | EKS cluster name | `my-eks-cluster` |
| `aws-region` | AWS region | `us-west-2` |

## Verification

Check that the Pod Identity Agent is running:

```bash
# Check DaemonSet status
kubectl get daemonset -n kube-system eks-pid-agent

# Check pods are running on all nodes
kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent

# View logs
kubectl logs -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
```

## Dependencies

**None** - This is the foundational component that must be deployed first.

## Next Steps

After the Pod Identity Agent is deployed, you can deploy ACK controllers that use Pod Identity for AWS authentication. See the main [README](../README.md) for the complete deployment flow.
