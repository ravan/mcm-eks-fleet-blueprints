# ACK IAM Controller Fleet Bundle

This Fleet bundle deploys the AWS Controllers for Kubernetes (ACK) IAM controller with EKS Pod Identity authentication.

## Overview

The ACK IAM controller enables management of AWS IAM resources (roles, policies, users, groups, OIDC providers) through Kubernetes CRDs. This allows you to manage IAM infrastructure declaratively alongside your Kubernetes workloads.

## Components

1. **chart/**: Wrapper Helm chart containing:
   - `templates/bootstrap-hook.yaml`: Pre-install Helm hook (bootstrap Job)
   - `Chart.yaml`: Declares iam-chart subchart dependency from OCI registry
   - `values.yaml`: Default values and bootstrap configuration
2. **fleet.yaml**: Fleet configuration with cluster-specific value injection

## Prerequisites

See the main [README](../README.md#prerequisites) for complete setup instructions including:

1. CloudFormation stack deployment (creates IAM roles)
2. Per-cluster bootstrap script (creates pod identity association for fleet-bootstrap SA)
3. Pod Identity Agent deployment (Bundle 0)
4. **ACK EKS Controller deployment (Bundle 1)** - Required to reconcile PodIdentityAssociation CRDs

### Required Cluster Labels

- `cluster-type: eks`
- `cluster-name: <eks-cluster-name>`
- `aws-region: <region>`
- `aws-account-id: <account-id>`
- `ack-iam-role-name: <role-name>` (e.g., `ACKIAMControllerRole` - not full ARN)

## How It Works

### Bootstrap Hook (Pre-Install)

1. Fleet deploys the wrapper Helm chart with `targetCustomizations` injecting cluster-specific values
2. Helm pre-install hook creates fleet-bootstrap ServiceAccount and RBAC (if not exists)
3. Bootstrap Job executes using fleet-bootstrap SA:
   - Creates PodIdentityAssociation CRD using kubectl:
     ```yaml
     apiVersion: eks.services.k8s.aws/v1alpha1
     kind: PodIdentityAssociation
     metadata:
       name: ack-iam-controller-pod-identity
       namespace: ack-system
     spec:
       clusterName: <from-cluster-label>
       namespace: ack-system
       serviceAccount: ack-iam-controller
       roleARN: arn:aws:iam::{account-id}:role/{ack-iam-role-name}
     ```
   - Waits for ACK EKS controller to reconcile the CRD (creates actual AWS pod identity association)
   - Verifies reconciliation by checking CRD status
4. Hook completes successfully

### Controller Deployment

5. Helm deploys iam-chart subchart from OCI registry
6. Controller pod starts with `ack-iam-controller` ServiceAccount
7. Pod Identity Agent provides AWS credentials via the pod identity association
8. Controller starts successfully and can manage IAM resources

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
        ackIamRoleName: ${ index .ClusterLabels "ack-iam-role-name" }
        iam-chart:
          aws:
            region: ${ index .ClusterLabels "aws-region" }
```

The bootstrap hook uses these values to create the PodIdentityAssociation CRD with the constructed IAM role ARN.

## Dependencies

- **ACK EKS Controller** (Bundle 1): Must be deployed first - defined in `fleet.yaml`:
  ```yaml
  dependsOn:
    - name: ack-controllers-blueprints-ack-eks-controller
  ```

The ACK EKS controller is required because it reconciles PodIdentityAssociation CRDs by creating the actual AWS pod identity associations.

## Verification

```bash
# Check bootstrap Job status
kubectl get jobs -n cattle-fleet-system -l app.kubernetes.io/component=bootstrap

# Check bootstrap Job logs
kubectl logs -n cattle-fleet-system -l app.kubernetes.io/component=bootstrap

# Check PodIdentityAssociation CRD status
kubectl get podidentityassociation -n ack-system ack-iam-controller-pod-identity -o yaml

# Check controller deployment
kubectl get pods -n ack-system -l app.kubernetes.io/name=iam-chart

# Test IAM controller by creating a sample Policy
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

# Verify policy was created in AWS
kubectl get policy test-policy -o yaml
```

## Troubleshooting

See the main [README Troubleshooting section](../README.md#troubleshooting) for common issues.

**Common ACK IAM issues:**
- Bootstrap Job fails if ACK EKS controller is not running (check Bundle 1 status)
- PodIdentityAssociation CRD not reconciling (check ACK EKS controller logs)

## Next Steps

Once deployed, the ACK IAM controller can manage:
- **IAM Roles**: Create and manage IAM roles
- **IAM Policies**: Create and manage IAM policies
- **IAM Users**: Create and manage IAM users
- **IAM Groups**: Create and manage IAM groups
- **OIDC Providers**: Create and manage OIDC identity providers

You can now deploy additional ACK controllers (S3, RDS, etc.) using the same pattern, or use the IAM controller to create roles for application workloads.
