# AWS EBS CSI Driver Blueprint

## Overview

This Fleet blueprint deploys the AWS EBS CSI Driver to Amazon EKS clusters with automatic IAM role provisioning and EKS Pod Identity authentication. The driver enables dynamic provisioning of Amazon EBS volumes for Kubernetes persistent storage.

## Features

- **Automatic IAM Role Creation**: Uses ACK IAM Controller to declaratively create IAM roles with required EBS permissions
- **Pod Identity Authentication**: Eliminates need for IRSA (IAM Roles for Service Accounts) using EKS Pod Identity
- **Zero Authentication Failures**: Helm hooks ensure IAM roles exist before driver pods start
- **Multi-Cluster Support**: Single GitRepo can deploy to multiple EKS clusters with cluster-specific configuration
- **Default Storage Class**: Configures `gp3` as the default storage class with encryption enabled

## Prerequisites

### Required Fleet Bundles

This bundle has explicit dependencies that must be deployed first:

1. **ACK IAM Controller** (`ack-iam-controller-blueprints-ack-iam-controller`)
   - Provides `Role` CRD reconciliation
   - Creates IAM roles in AWS
   - Must be deployed and ready before this bundle

### Required Cluster Labels

Clusters must have the following labels configured:

| Label | Required | Description | Example |
|-------|----------|-------------|---------|
| `cluster-type` | Yes | Cluster type for targeting | `eks` |
| `addon-aws-ebs-csi-driver` | Yes | Enable EBS CSI Driver deployment | `"true"` |
| `cluster-name` | Yes | EKS cluster name | `prod-eks-us-west-2` |
| `aws-region` | Yes | AWS region for API calls | `us-west-2` |
| `aws-account-id` | Yes | AWS account ID (numeric) | `"123456789012"` |
| `aws-ebs-csi-driver-role-name` | No | Custom IAM role name (default: MCMAWSEBSCSIDriverRole) | `ProdEBSRole` |

### ACK Controller Permissions

The ACK IAM Controller needs permissions to create IAM roles and attach policies:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:UpdateRole",
        "iam:GetRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:UpdateAssumeRolePolicy",
        "iam:TagRole",
        "iam:UntagRole"
      ],
      "Resource": "arn:aws:iam::*:role/MCMAWS*"
    }
  ]
}
```

## Deployment Architecture

### Hook Execution Order

The deployment uses Helm hooks to orchestrate the sequence of resource creation:

```
1. Weight -10: IAM Role Creation (ack-iam-role-association)
   └─ Creates ACK IAM Role CRD
   └─ Waits for ACK IAM Controller to reconcile (ARN in status)

2. Weight -5: Pod Identity Association (ack-pod-identity-association)
   └─ Creates ACK PodIdentityAssociation CRD
   └─ Waits for ACK EKS Controller to reconcile (ARN in status)

3. Weight 0: EBS CSI Driver Resources
   └─ ServiceAccount (ebs-csi-controller-sa)
   └─ Deployment (controller pods)
   └─ DaemonSet (node pods)
   └─ StorageClasses (gp3, gp2, etc.)
```

### Chart Dependencies

The built chart includes two local dependencies:

1. **ack-iam-role-association** (weight -10 hooks)
   - Creates IAM roles via ACK IAM Controller
   - Waits for role reconciliation before proceeding

2. **ack-pod-identity-association** (weight -5 hooks)
   - Creates pod identity associations via ACK EKS Controller
   - Links service accounts to IAM roles

## Deployment

### Option 1: Via Fleet GitRepo (Recommended)

1. Apply the GitRepo resource:
   ```bash
   kubectl apply -f blueprints/gitrepos/aws-ebs-csi-driver-repo.yaml
   ```

2. Label target clusters:
   ```bash
   # Add required labels to enable deployment
   kubectl label cluster <cluster-name> \
     addon-aws-ebs-csi-driver=true \
     cluster-name=<eks-cluster-name> \
     aws-region=<region> \
     aws-account-id="<account-id>"
   ```

3. Monitor deployment:
   ```bash
   # Check GitRepo sync status
   kubectl get gitrepo -n fleet-default aws-ebs-csi-driver

   # Check bundle status
   kubectl get bundles -n fleet-default | grep ebs

   # View bundle details
   kubectl describe bundle -n fleet-default <bundle-name>
   ```

### Option 2: Manual Installation (Testing)

For testing without Fleet, use the Taskfile command:

```bash
# Configure .env file first with cluster settings
task install-aws-ebs-csi-driver
```

This uses the test values file at `config/aws-ebs-csi-driver/test-values.yaml`.

## Validation

### 1. Verify IAM Role Created

```bash
aws iam get-role \
  --role-name MCMAWSEBSCSIDriverRole \
  --profile <profile> \
  --region <region>
```

Expected output:
- Role exists with name `MCMAWSEBSCSIDriverRole` (or custom name)
- Trust policy allows `pods.eks.amazonaws.com` service principal
- Attached policy: `arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy`

### 2. Verify Pod Identity Association

```bash
aws eks list-pod-identity-associations \
  --cluster-name <cluster-name> \
  --region <region> \
  --profile <profile>
```

Expected output:
- Association exists for `ebs-csi-controller-sa` in `kube-system` namespace
- Role ARN matches IAM role created above

### 3. Verify Driver Pods Running

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
```

Expected output:
- 2 controller pods (replicas) in `Running` state
- Node pods (DaemonSet) on each node in `Running` state

### 4. Verify Storage Classes

```bash
kubectl get storageclass
```

Expected output:
- `gp3` storage class exists and is marked as default
- Additional storage classes: `gp2`, `io1`, `io2`, `st1`, `sc1`

### 5. Test PVC Provisioning

Create a test PVC:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 4Gi
  storageClassName: gp3
EOF
```

Verify provisioning:

```bash
# Check PVC status (should be Bound)
kubectl get pvc ebs-test-pvc

# Verify EBS volume created in AWS
aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=ebs-test-pvc" \
  --region <region> \
  --profile <profile>
```

## Troubleshooting

### GitRepo Not Syncing

```bash
# Check GitRepo status
kubectl describe gitrepo -n fleet-default aws-ebs-csi-driver

# View GitJob logs
kubectl logs -n fleet-default -l gitjob.fleet.cattle.io/gitrepo=aws-ebs-csi-driver
```

Common issues:
- Repository URL not accessible
- Branch doesn't exist
- Path doesn't contain `fleet.yaml`

### Bundle Not Deploying

```bash
# Check bundle status
kubectl get bundles -n fleet-default | grep ebs

# View bundle details
kubectl describe bundle -n fleet-default <bundle-name>
```

Common issues:
- Dependency bundle not ready (check `ack-iam-controller` status)
- No clusters matching label selector (`addon-aws-ebs-csi-driver: true`)
- Template syntax errors in `fleet.yaml`

### IAM Role Not Created

The IAM role creation hook (weight -10) may fail for several reasons. The hook provides specific error messages for each case:

#### Check Hook Job Status

```bash
# List all jobs in namespace
kubectl get jobs -n ack-system | grep iam-role

# View hook job logs
kubectl logs -n ack-system job/ebs-iam-role-create-role

# Check Role CRD status
kubectl get role.iam.services.k8s.aws -n ack-system

# View Role CRD details and reconciliation status
kubectl describe role.iam.services.k8s.aws -n ack-system ebs-iam-role
```

#### Common Failure Scenarios

**1. AccessDenied - ACK IAM Controller Lacks Permissions**

**Error Message**: `❌ ERROR: ACK IAM Controller lacks IAM permissions`

**Root Cause**: The IAM role used by the ACK IAM Controller doesn't have sufficient permissions to create/update IAM roles.

**Resolution**:

1. Check which IAM role the ACK IAM Controller is using:
   ```bash
   kubectl get pods -n ack-system -l k8s-app=ack-iam-controller -o yaml | grep -A5 serviceAccountName
   aws eks describe-pod-identity-association --cluster-name <cluster> --region <region>
   ```

2. Verify the IAM role has required permissions (see `config/aws-ebs-csi-driver/ack-iam-controller-permissions.json`):
   ```bash
   aws iam list-attached-role-policies --role-name <ack-iam-controller-role>
   aws iam get-role-policy --role-name <ack-iam-controller-role> --policy-name <inline-policy-name>
   ```

3. Add missing permissions to the ACK IAM Controller's IAM role:
   - `iam:CreateRole`
   - `iam:GetRole`
   - `iam:UpdateRole`
   - `iam:AttachRolePolicy`
   - `iam:UpdateAssumeRolePolicy`
   - `iam:TagRole`

**2. Policy ARN Not Found**

**Error Message**: `❌ ERROR: Managed policy ARN not found`

**Root Cause**: One or more policy ARNs specified in `fleet.yaml` don't exist in the AWS account.

**Resolution**:

1. Verify the policy ARN is correct (check for typos):
   ```bash
   # For AWS-managed policies (policy/service-role/...)
   aws iam get-policy --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

   # For customer-managed policies
   aws iam get-policy --policy-arn arn:aws:iam::<account-id>:policy/<policy-name>
   ```

2. If using a custom policy, ensure it exists in the same AWS account.

3. Update `fleet.yaml` with the correct policy ARN.

**3. IAM Role Already Exists (Created Manually or via CloudFormation)**

**Warning Message**: `⚠ WARNING: IAM role already exists in AWS`

**Root Cause**: An IAM role with the same name already exists but is not managed by ACK.

**Behavior**: The hook will continue waiting. ACK IAM Controller will attempt to adopt the existing role and update it to match the desired state.

**Resolution** (if adoption fails):

1. Check if the existing role has the correct trust policy:
   ```bash
   aws iam get-role --role-name MCMAWSEBSCSIDriverRole --query 'Role.AssumeRolePolicyDocument'
   ```

2. If the trust policy is different, either:
   - **Option A**: Delete the manually-created role and let ACK create it
   - **Option B**: Manually update the trust policy to allow `pods.eks.amazonaws.com`

**4. Reconciliation Timeout (5 Minutes)**

**Error Message**: `ERROR: IAM Role was not reconciled after 60 attempts (5 minutes)`

**Root Cause**: ACK IAM Controller is not reconciling the Role CRD (may be down, not watching CRDs, or experiencing AWS API throttling).

**Resolution**:

1. Check ACK IAM Controller pod status:
   ```bash
   kubectl get pods -n ack-system -l k8s-app=ack-iam-controller
   kubectl logs -n ack-system -l k8s-app=ack-iam-controller --tail=100
   ```

2. Check if controller is reconciling CRDs:
   ```bash
   kubectl logs -n ack-system -l k8s-app=ack-iam-controller | grep "reconciling"
   ```

3. Check for AWS API throttling or rate limits in controller logs:
   ```bash
   kubectl logs -n ack-system -l k8s-app=ack-iam-controller | grep -i "throttl\|rate"
   ```

4. Restart the ACK IAM Controller if needed:
   ```bash
   kubectl delete pod -n ack-system -l k8s-app=ack-iam-controller
   ```

**5. Malformed Policy Document (Trust Policy or Inline Policy)**

**Error Message**: `❌ ERROR: Trust policy or inline policy document is malformed`

**Root Cause**: Invalid JSON syntax in `fleet.yaml` trust policy or inline policies.

**Resolution**:

1. Validate JSON syntax:
   ```bash
   # Extract policy from fleet.yaml and validate
   yq '.helm.values.ack-iam-role-association.iamRole.trustPolicy' fleet.yaml | jq '.'
   ```

2. Common JSON errors:
   - Missing closing braces `}`
   - Trailing commas
   - Unquoted keys
   - Invalid escape characters

3. Use a JSON validator before deploying:
   ```bash
   cat policy.json | jq '.'
   ```

#### Additional Debugging

If the hook job failed and was cleaned up, check Helm release history:

```bash
# View release history
helm history aws-ebs-csi-driver -n kube-system

# Check for hook failures
kubectl get events -n ack-system --sort-by='.lastTimestamp' | grep iam-role
```

### Pod Identity Association Failures

```bash
# Check ACK EKS Controller status
kubectl get pods -n ack-system -l k8s-app=ack-eks-controller

# Check PodIdentityAssociation CRD status
kubectl get podidentityassociation.eks.services.k8s.aws -n ack-system

# View details
kubectl describe podidentityassociation.eks.services.k8s.aws -n ack-system <assoc-name>
```

Common issues:
- IAM role doesn't exist (check hook execution order)
- Service account name mismatch
- Cluster name incorrect

### Driver Pods CrashLoopBackOff

```bash
# Check pod logs
kubectl logs -n kube-system <ebs-csi-controller-pod>

# Check pod identity agent
kubectl get daemonset -n kube-system eks-pod-identity-agent
```

Common issues:
- Pod identity agent not deployed
- IAM role ARN not accessible
- AWS region mismatch

### PVC Stuck Pending

```bash
# Check PVC events
kubectl describe pvc <pvc-name>

# Check CSI driver logs
kubectl logs -n kube-system -l app=ebs-csi-controller -c csi-provisioner

# Check EBS quotas
aws service-quotas get-service-quota \
  --service-code ebs \
  --quota-code L-309BACF6 \
  --region <region> \
  --profile <profile>
```

Common issues:
- Storage class not found
- EBS quota exceeded in AWS region
- IAM permissions missing for volume creation
- Node not in running state (WaitForFirstConsumer)

## Configuration

### Custom IAM Role Name

To use a different IAM role name per cluster, add the cluster label:

```bash
kubectl label cluster <cluster-name> aws-ebs-csi-driver-role-name=CustomRoleName
```

### Shared vs Per-Cluster IAM Roles

By default, all clusters in the same AWS account share the same IAM role (`MCMAWSEBSCSIDriverRole`). This is recommended for:
- Simplified management
- Avoiding IAM role limits (1000 roles per account)
- Consistent permissions across clusters

Use per-cluster roles when:
- Implementing least privilege per cluster
- Different clusters need different permissions
- Compliance requires role isolation

### Storage Class Configuration

The default `gp3` storage class is configured for:
- Cost efficiency (gp3 is cheaper than gp2)
- Performance (3000 IOPS baseline, 125 MB/s throughput)
- Encryption at rest (all volumes encrypted)
- Delayed binding (`WaitForFirstConsumer` ensures correct AZ)

To add custom storage classes, modify `fleet.yaml`:

```yaml
storageClasses:
  - name: fast-ssd
    volumeBindingMode: WaitForFirstConsumer
    allowVolumeExpansion: true
    parameters:
      type: io2
      iops: "10000"
      encrypted: "true"
```

## References

- [AWS EBS CSI Driver Documentation](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [EKS Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [ACK IAM Controller](https://aws-controllers-k8s.github.io/community/reference/iam/)
- [Fleet Bundle Documentation](https://fleet.rancher.io/ref-bundle)
- [Project Quickstart](../../specs/001-i-want-to/quickstart.md)
