# ACK Pod Identity Association Chart

A reusable Helm chart for creating EKS Pod Identity Associations for AWS Controllers for Kubernetes (ACK) controllers. This chart uses Helm hooks to declaratively create PodIdentityAssociation CRDs via the ACK EKS controller.

## Overview

This is a local subchart designed to be used as a dependency by ACK controller packages. It provides:

- **Bootstrap Hook**: Pre-install/pre-upgrade job that creates a PodIdentityAssociation CRD
- **Cleanup Hook**: Pre-delete job that removes the PodIdentityAssociation CRD
- **Declarative Approach**: Uses ACK's PodIdentityAssociation CRD (not AWS API directly)

## Pattern

This chart follows the same pattern as `ack-eks-bootstrap` but is designed for reuse across multiple ACK controllers:

```
packages/ack-eks-bootstrap/        # Bootstrap via AWS API (for EKS controller itself)
packages/ack-pod-identity-association/  # Reusable subchart via ACK CRD (for other controllers)
```

## Usage as a Dependency

### 1. Add as Dependency

Create `generated-changes/dependencies/ack-pod-identity-association/dependency.yaml`:

```yaml
# Reference the local pod identity association package
url: packages/ack-pod-identity-association
```

### 2. Configure in Fleet

In your Fleet `fleet.yaml`, configure the subchart values:

```yaml
helm:
  chart: your-controller-chart
  repo: https://ravan.github.io/mcm-eks-fleet-blueprints/
  releaseName: ack-your-controller
  values:
    aws:
      region: us-west-2

    # Configure pod identity subchart
    ack-pod-identity-association:
      controllerName: "ack-your-controller"
      podIdentity:
        enabled: true
        name: "ack-your-controller-pod-identity"
        clusterName: "my-cluster"
        awsAccountId: "123456789012"
        roleName: "MCMACKYourControllerRole"
        serviceAccountName: "ack-your-controller"
        namespace: "ack-system"
```

### 3. Rebuild Chart

```bash
PATH="/opt/homebrew/bin:$PATH" PACKAGE=ack-your-controller ./bin/charts-build-scripts charts
```

## Values

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `podIdentity.enabled` | Enable pod identity association creation | No | `true` |
| `podIdentity.name` | Name of PodIdentityAssociation resource | Yes | - |
| `podIdentity.clusterName` | EKS cluster name | Yes | - |
| `podIdentity.awsAccountId` | AWS account ID | Yes (if roleArn not set) | - |
| `podIdentity.roleName` | IAM role name | Yes (if roleArn not set) | - |
| `podIdentity.roleArn` | Full IAM role ARN (overrides accountId/roleName) | No | - |
| `podIdentity.serviceAccountName` | Service account to associate | Yes | - |
| `podIdentity.namespace` | Namespace for association | No | Release namespace |
| `controllerName` | Controller name for labels | No | `ack-controller` |
| `hook.bootstrap.backoffLimit` | Bootstrap job retries | No | `10` |
| `hook.bootstrap.ttlSecondsAfterFinished` | Bootstrap job TTL | No | `86400` (24h) |
| `hook.bootstrap.image` | Bootstrap job image | No | `alpine/k8s:1.29.2` |
| `hook.cleanup.backoffLimit` | Cleanup job retries | No | `3` |
| `hook.cleanup.ttlSecondsAfterFinished` | Cleanup job TTL | No | `300` (5m) |
| `hook.cleanup.image` | Cleanup job image | No | `alpine/k8s:1.29.2` |

## How It Works

### Bootstrap Process

1. **Pre-install/Pre-upgrade Hook** (weight: -5): Creates ServiceAccount and RBAC
2. **Pre-install/Pre-upgrade Hook** (weight: 0): Runs bootstrap job
3. Bootstrap job creates PodIdentityAssociation CRD using kubectl
4. ACK EKS controller reconciles the CRD and creates actual AWS pod identity association
5. Job waits for reconciliation (checks for `status.ackResourceMetadata.arn`)
6. Additional 15-second wait for credentials to propagate
7. Main controller deployment proceeds

### Cleanup Process

1. **Pre-delete Hook**: Runs cleanup job
2. Cleanup job deletes PodIdentityAssociation CRD
3. ACK EKS controller reconciles deletion and removes AWS association

## Requirements

- ACK EKS controller must be installed and running (manages PodIdentityAssociation CRDs)
- Bootstrap service account needs pod identity already configured (via fleet-bootstrap)
- Fleet dependency on ACK EKS controller bundle

## Example: Adding RDS Controller

```bash
# 1. Create package
mkdir -p packages/ack-rds-controller

# 2. Define package.yaml
cat > packages/ack-rds-controller/package.yaml <<EOF
url: oci://public.ecr.aws/aws-controllers-k8s/rds-chart:1.x.x
packageVersion: 1
EOF

# 3. Add dependency
mkdir -p packages/ack-rds-controller/generated-changes/dependencies/ack-pod-identity-association
cat > packages/ack-rds-controller/generated-changes/dependencies/ack-pod-identity-association/dependency.yaml <<EOF
url: packages/ack-pod-identity-association
EOF

# 4. Build
PATH="/opt/homebrew/bin:$PATH" PACKAGE=ack-rds-controller ./bin/charts-build-scripts charts

# 5. Create Fleet bundle
cat > blueprints/ack-rds-controller/fleet.yaml <<EOF
defaultNamespace: ack-system
helm:
  chart: rds-chart
  repo: https://ravan.github.io/mcm-eks-fleet-blueprints/
  releaseName: ack-rds-controller
targetCustomizations:
  - name: eks-clusters
    clusterSelector:
      matchLabels:
        cluster-type: eks
    helm:
      values:
        aws:
          region: \${ index .ClusterLabels "aws-region" }
        ack-pod-identity-association:
          controllerName: "ack-rds-controller"
          podIdentity:
            enabled: true
            name: "ack-rds-controller-pod-identity"
            clusterName: \${ index .ClusterLabels "cluster-name" }
            awsAccountId: \${ index .ClusterLabels "aws-account-id" | quote }
            roleName: \${ default "MCMACKRDSControllerRole" (get .ClusterLabels "ack-rds-role-name") }
            serviceAccountName: "ack-rds-controller"
            namespace: "ack-system"
dependsOn:
  - name: ack-eks-controller-blueprints-ack-eks-controller
EOF
```

## Comparison with ack-eks-bootstrap

| Feature | ack-eks-bootstrap | ack-pod-identity-association |
|---------|-------------------|------------------------------|
| **Purpose** | Bootstrap EKS controller | Reusable for any ACK controller |
| **Method** | AWS CLI (`aws eks create-pod-identity-association`) | ACK CRD (PodIdentityAssociation) |
| **When** | Once per cluster (for EKS controller) | Per controller (IAM, RDS, etc.) |
| **Requires** | Fleet-bootstrap service account with pod identity | ACK EKS controller running |
| **Dependency** | Used by ack-eks-controller only | Used by ack-iam-controller, future controllers |

## Troubleshooting

### Job fails with "CRD was not reconciled"

Check that ACK EKS controller is running:
```bash
kubectl get pods -n ack-system -l app.kubernetes.io/name=ack-eks-controller
```

### PodIdentityAssociation stuck in pending

View the CRD status:
```bash
kubectl get podidentityassociation -n ack-system -o yaml
```

Check ACK controller logs:
```bash
kubectl logs -n ack-system -l app.kubernetes.io/name=ack-eks-controller
```

### "roleArn must be set" error

Ensure either:
- Both `podIdentity.awsAccountId` and `podIdentity.roleName` are set, OR
- `podIdentity.roleArn` is set with full ARN

## References

- [ACK EKS Controller](https://github.com/aws-controllers-k8s/eks-controller)
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [charts-build-scripts](https://github.com/rancher/charts-build-scripts)
