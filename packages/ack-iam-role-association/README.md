# ack-iam-role-association

**Version**: 1.0.0
**Type**: Reusable Helm Chart
**Purpose**: Declaratively create AWS IAM roles with ACK IAM Controller for EKS pod identity authentication

## Overview

This chart provides a reusable pattern for creating AWS IAM roles via ACK (AWS Controllers for Kubernetes) IAM Role CRDs. It uses Helm pre-install hooks to ensure IAM roles are created and reconciled **before** the main application resources are deployed, eliminating authentication failures due to missing IAM roles.

### Key Features

- **Declarative IAM Role Management**: Creates IAM roles using ACK IAM Controller CRDs (no AWS CLI required)
- **Pod Identity Trust Policy**: Pre-configured trust policy for EKS Pod Identity (`pods.eks.amazonaws.com`)
- **Helm Hook Orchestration**: Weight-based execution ensures IAM role exists before dependent resources
- **Reconciliation Wait Logic**: Blocks deployment until ACK IAM Controller reconciles the role with AWS
- **Idempotent**: Safe to run multiple times, handles role updates and shared roles across clusters
- **Reusable**: Add as a local chart dependency to any AWS service integration

## Architecture

```
Helm Install/Upgrade Triggered
│
├─ Weight -10: RBAC Setup (ServiceAccount, Role, RoleBinding)
│
├─ Weight -5: IAM Role Hook Job
│   ├─ Creates ACK IAM Role CRD
│   ├─ Waits for ACK IAM Controller reconciliation (status.ackResourceMetadata.arn populated)
│   └─ Waits 10 seconds for AWS IAM eventual consistency
│
├─ Weight 0: Main application resources deployed
│   └─ (e.g., pod identity associations, CSI driver pods)
│
└─ On Chart Delete: Cleanup Hook
    └─ Deletes ACK IAM Role CRD (ACK controller deletes AWS role)
```

## Values Schema

### `iamRole` (object, required)

Configuration for the AWS IAM role to create.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `name` | string | ✅ | `""` | IAM role name in AWS (must be unique within account) |
| `path` | string | ❌ | `"/"` | IAM path for organization |
| `description` | string | ❌ | `"IAM role created by ack-iam-role-association"` | Human-readable description |
| `trustPolicy.servicePrincipal` | string | ❌ | `"pods.eks.amazonaws.com"` | Service principal for assume role |
| `trustPolicy.actions` | array | ❌ | `["sts:AssumeRole", "sts:TagSession"]` | Actions allowed for assume role |
| `policies` | array | ✅ | `[]` | Managed policy ARNs to attach (e.g., `arn:aws:iam::aws:policy/...`) |
| `inlinePolicies` | object | ❌ | `{}` | Map of policy name to JSON document string |
| `maxSessionDuration` | int | ❌ | `3600` | Maximum session duration in seconds (3600-43200) |
| `tags` | array | ❌ | `[]` | Tags for cost tracking (array of `{key: "...", value: "..."}`) |

### `hook` (object)

Configuration for Helm hook jobs.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `weight` | int | ❌ | `-10` | Helm hook weight (controls execution order) |
| `backoffLimit` | int | ❌ | `10` | Job retry attempts on failure |
| `ttlSecondsAfterFinished` | int | ❌ | `86400` | Keep job for 24 hours (debugging) |
| `image` | string | ❌ | `"alpine/k8s:1.29.2"` | Container image with kubectl |
| `serviceAccountName` | string | ❌ | `""` | Service account for RBAC (auto-generated if empty) |

### `controllerName` (string)

Name used for labeling resources (typically the parent chart name, e.g., `aws-ebs-csi-driver`).

### `enabled` (boolean)

Enable IAM role creation. Default: `true`.

## Hook Execution Order

This chart is designed to work with **weight-based hook orchestration**:

1. **Weight -10**: IAM role creation hooks (this chart)
2. **Weight -5**: Pod identity association hooks (e.g., `ack-pod-identity-association`)
3. **Weight 0**: Main application resources (default)

**⚠️ IMPORTANT**: Do not change hook weights without understanding the dependency chain. IAM roles must exist before pod identity associations can reference them.

## Usage Examples

### Example 1: Basic IAM Role with Managed Policy

```yaml
ack-iam-role-association:
  enabled: true
  iamRole:
    name: MCMAWSEBSCSIDriverRole
    policies:
      - arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
  controllerName: aws-ebs-csi-driver
```

### Example 2: IAM Role with Custom Inline Policy

```yaml
ack-iam-role-association:
  enabled: true
  iamRole:
    name: CustomS3AccessRole
    description: "Custom IAM role for S3 access with pod identity"
    policies:
      - arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
    inlinePolicies:
      S3WriteAccess: |
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Action": [
                "s3:PutObject",
                "s3:DeleteObject"
              ],
              "Resource": "arn:aws:s3:::my-bucket/*"
            }
          ]
        }
    tags:
      - key: "managed-by"
        value: "fleet"
      - key: "environment"
        value: "production"
  controllerName: custom-s3-app
```

### Example 3: Shared IAM Role Across Clusters

```yaml
ack-iam-role-association:
  enabled: true
  iamRole:
    # Same role name across all clusters in the AWS account
    name: SharedEBSDriverRole
    policies:
      - arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
  controllerName: aws-ebs-csi-driver
```

## Integration Guide

### Adding to an Existing Package

1. **Create dependency reference**:

```bash
mkdir -p packages/my-aws-service/generated-changes/dependencies/ack-iam-role-association
echo "url: packages/ack-iam-role-association" > \
  packages/my-aws-service/generated-changes/dependencies/ack-iam-role-association/dependency.yaml
```

2. **Configure values in Fleet `fleet.yaml`**:

```yaml
helm:
  values:
    # Parent chart values
    aws:
      region: ${ index .ClusterLabels "aws-region" }

    # IAM role subchart values
    ack-iam-role-association:
      enabled: true
      iamRole:
        name: ${ default "MyDefaultRoleName" (get .ClusterLabels "my-service-role-name") }
        policies:
          - arn:aws:iam::aws:policy/MyServicePolicy
      controllerName: my-aws-service
```

3. **Rebuild package**:

```bash
PACKAGE=my-aws-service ./bin/charts-build-scripts prepare
PACKAGE=my-aws-service ./bin/charts-build-scripts patch
PATH="/opt/homebrew/bin:$PATH" PACKAGE=my-aws-service ./bin/charts-build-scripts charts
```

## Troubleshooting

### Issue: Hook Job Fails with "Role CRD not reconciled"

**Symptoms**:
- Hook job exits with error after 5 minutes
- Message: "ERROR: IAM Role was not reconciled after 60 attempts"

**Debug**:
```bash
# Check ACK IAM Controller status
kubectl get pods -n ack-system -l k8s-app=ack-iam-controller

# Check ACK IAM Controller logs
kubectl logs -n ack-system -l k8s-app=ack-iam-controller --tail=100

# Check IAM Role CRD status
kubectl get role <role-crd-name> -n ack-system -o yaml
```

**Common Causes**:
1. ACK IAM Controller not deployed or not running
2. ACK IAM Controller lacks IAM permissions to create roles
3. IAM role name conflicts with existing role
4. Network connectivity issues to AWS IAM API

### Issue: IAM Role Created But Policies Not Attached

**Symptoms**:
- Role exists in AWS but has no attached policies
- Pod identity authentication fails with "access denied"

**Debug**:
```bash
# Check role in AWS
aws iam get-role --role-name <role-name>
aws iam list-attached-role-policies --role-name <role-name>

# Check CRD spec vs status
kubectl get role <role-crd-name> -n ack-system -o yaml
```

**Common Causes**:
1. Policy ARN typo (check exact ARN in values)
2. ACK IAM Controller lacks `iam:AttachRolePolicy` permission
3. Policy does not exist in AWS account

### Issue: Hook Weight Ordering Violation

**Symptoms**:
- Pod identity association created before IAM role
- Pod identity association CRD stuck in "Pending" (waiting for role ARN)

**Debug**:
```bash
# Check hook execution order in job names
kubectl get jobs -n ack-system --sort-by=.metadata.creationTimestamp
```

**Fix**:
Ensure hook weights follow the pattern:
- IAM role hooks: `-10`
- Pod identity hooks: `-5`
- Main resources: `0`

## IAM Role Lifecycle

### Creation

1. Helm pre-install/pre-upgrade hook triggered (weight -10)
2. Job creates ACK IAM Role CRD
3. ACK IAM Controller watches for new Role CRDs
4. Controller creates IAM role in AWS via IAM API
5. Controller updates CRD status with `ackResourceMetadata.arn`
6. Hook job detects ARN in status (reconciliation complete)
7. Hook job waits 10 seconds for AWS IAM eventual consistency
8. Hook job exits successfully, allowing deployment to continue

### Update

- Helm upgrade triggers pre-upgrade hook
- Job applies updated Role CRD (kubectl apply is idempotent)
- ACK IAM Controller detects CRD changes
- Controller updates IAM role in AWS (attach/detach policies, update trust policy)
- Controller updates CRD status

### Deletion

- Helm uninstall triggers pre-delete hook
- Cleanup job deletes Role CRD
- ACK IAM Controller detects CRD deletion
- Controller deletes IAM role from AWS (if no other dependencies)

### Shared Roles (Multi-Cluster)

- Multiple clusters can create CRDs with the same IAM role name
- ACK IAM Controller handles idempotency (first cluster creates, others verify)
- IAM role persists in AWS until **all** clusters delete their CRDs
- Use shared role strategy to avoid AWS IAM role limits

## Reusability

This chart was designed to be reused across multiple AWS service integrations:

- **AWS EBS CSI Driver**: Attach `AmazonEBSCSIDriverPolicy`
- **AWS EFS CSI Driver**: Attach `AmazonEFSCSIDriverPolicy`
- **AWS Load Balancer Controller**: Attach custom inline policy for ALB/NLB
- **ExternalDNS**: Attach custom inline policy for Route53
- **Cluster Autoscaler**: Attach custom inline policy for EC2 Auto Scaling

For each service, simply add this chart as a dependency and configure the IAM role name and policies.

## Best Practices

1. **Unique Role Names**: Use descriptive, service-specific role names (e.g., `MCMAWSEBSCSIDriverRole`)
2. **Shared Roles at Scale**: For 100+ clusters, use shared roles to avoid IAM limits
3. **Least Privilege**: Only attach policies required for the specific service
4. **Tagging**: Always add tags for cost tracking and ownership
5. **Hook Weights**: Never modify hook weights without updating dependent charts
6. **Testing**: Test role creation on a single cluster before deploying Fleet-wide

## Related Charts

- **ack-pod-identity-association**: Creates PodIdentityAssociation CRDs (weight -5)
- **ack-eks-controller**: Provides PodIdentityAssociation CRD reconciliation
- **ack-iam-controller**: Provides Role CRD reconciliation

## Dependencies

- **ACK IAM Controller v1.5.2+**: Must be deployed to reconcile Role CRDs
- **Kubernetes 1.27+**: Required for ACK CRD API versions
- **Helm 3.x**: Required for hook weight support

## License

Part of mcm-eks-fleet-blueprints repository.
