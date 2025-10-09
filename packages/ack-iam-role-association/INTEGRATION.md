# Integration Guide: Adding ack-iam-role-association to AWS Service Packages

This guide provides step-by-step instructions for integrating the `ack-iam-role-association` chart into new AWS service packages that require IAM role authentication via EKS Pod Identity.

## Overview

The `ack-iam-role-association` chart automates IAM role creation using ACK (AWS Controllers for Kubernetes) IAM Controller. By adding this chart as a dependency, your AWS service package can:

1. **Declaratively create IAM roles** with specific policies
2. **Ensure IAM roles exist before application pods start** (via Helm hooks)
3. **Eliminate authentication failures** from missing IAM roles
4. **Support both shared and per-cluster IAM roles** via Fleet cluster labels
5. **Handle IAM role updates** when policies change

## Prerequisites

Before integrating this chart:

- [ ] **ACK IAM Controller deployed**: The `ack-iam-controller` Fleet bundle must be available and ready
- [ ] **Package structure exists**: Your AWS service package directory is set up with `package.yaml`
- [ ] **IAM permissions identified**: You know which AWS policies your service needs
- [ ] **Service account name known**: You know the Kubernetes service account name your service uses

## Integration Steps

### Step 1: Create Dependency Reference

Add `ack-iam-role-association` as a local chart dependency to your package.

```bash
# Navigate to your package directory
cd packages/<your-aws-service>

# Create dependency directory
mkdir -p generated-changes/dependencies/ack-iam-role-association

# Create dependency.yaml pointing to local chart
cat > generated-changes/dependencies/ack-iam-role-association/dependency.yaml <<'EOF'
url: packages/ack-iam-role-association
EOF
```

**Result**: When you run `charts-build-scripts prepare`, the `ack-iam-role-association` chart will be copied into your package as a subchart.

---

### Step 2: Configure Fleet Bundle Values

Edit your Fleet bundle (`blueprints/<your-service>/fleet.yaml`) to configure IAM role creation.

#### Add Cluster-Specific Values

First, extract cluster information from Fleet labels:

```yaml
targetCustomizations:
  - name: my-service-enabled-clusters
    clusterSelector:
      matchLabels:
        addon-my-service: "true"  # Your service's enable label
    helm:
      values:
        # Cluster information from Fleet labels
        clusterName: ${ index .ClusterLabels "cluster-name" }
        awsRegion: ${ index .ClusterLabels "aws-region" }
        awsAccountId: ${ index .ClusterLabels "aws-account-id" | quote }
```

#### Add IAM Role Subchart Configuration

Next, configure the `ack-iam-role-association` subchart:

```yaml
        # IAM Role Configuration (ack-iam-role-association subchart)
        ack-iam-role-association:
          # Enable IAM role creation
          enabled: true

          # Controller name (used for labeling)
          controllerName: <your-service-name>

          # Optional: Override resource names to avoid 63-char Kubernetes limit
          fullnameOverride: "<short-name>-iam-role"

          iamRole:
            # IAM role name (configurable via cluster label with default fallback)
            # Use 'default' function to provide default if label missing
            name: ${ default "MCM<YourService>Role" (get .ClusterLabels "<your-service>-role-name") }

            # Human-readable description
            description: "IAM role for <YourService> with pod identity authentication (managed by Fleet)"

            # Trust policy for EKS pod identity (standard configuration)
            trustPolicy:
              servicePrincipal: pods.eks.amazonaws.com
              actions:
                - "sts:AssumeRole"
                - "sts:TagSession"

            # AWS-managed policy ARNs required by your service
            policies:
              - arn:aws:iam::aws:policy/<YourServicePolicy>
              # Add additional managed policies as needed

            # Optional: Custom inline policies for permissions not in managed policies
            # inlinePolicies:
            #   CustomPermissions: |
            #     {
            #       "Version": "2012-10-17",
            #       "Statement": [{
            #         "Effect": "Allow",
            #         "Action": ["service:Action"],
            #         "Resource": "*"
            #       }]
            #     }

            # Maximum session duration (1-12 hours in seconds)
            maxSessionDuration: 3600

            # Tags for cost tracking
            tags:
              - key: "managed-by"
                value: "fleet"
              - key: "component"
                value: "<your-service-name>"
              - key: "cluster"
                value: ${ index .ClusterLabels "cluster-name" }

          # Helm hook configuration (weight -10 ensures IAM role exists before pod identity)
          hook:
            weight: -10
            backoffLimit: 10
            ttlSecondsAfterFinished: 86400  # 24 hours for debugging
            image: alpine/k8s:1.29.2
```

**Template Syntax Notes**:

- Use `${ index .ClusterLabels "label-name" }` for labels with hyphens
- Use `${ get .ClusterLabels "label-name" }` for labels without special characters
- Use `${ default "DefaultValue" (get .ClusterLabels "optional-label") }` for optional labels
- Use `| quote` filter for numeric values like AWS account IDs

---

### Step 3: Rebuild Package

Run the `charts-build-scripts` workflow to incorporate the dependency.

```bash
# macOS users: Ensure GNU patch is in PATH
export PATH="/opt/homebrew/bin:$PATH"

# Set package name
export PACKAGE=<your-service>

# Step 1: Fetch upstream chart and copy dependencies
./bin/charts-build-scripts prepare

# Step 2: Apply any custom patches
./bin/charts-build-scripts patch

# Step 3: Build final chart with dependencies
./bin/charts-build-scripts charts
```

**Expected Output**:

- `packages/<your-service>/charts/` contains the upstream chart with `ack-iam-role-association` as a subchart
- `charts/<your-service>-<version>.tgz` is the packaged chart ready for deployment

---

### Step 4: Ensure Correct Hook Weight Ordering

**Critical**: Helm hook weights must follow this order:

| Hook Type | Weight | Purpose | Chart |
|-----------|--------|---------|-------|
| IAM Role Creation | `-10` | Creates IAM roles in AWS | `ack-iam-role-association` |
| Pod Identity Association | `-5` | Links service accounts to IAM roles | `ack-pod-identity-association` |
| Application Resources | `0` | Deploys your service (default weight) | Your upstream chart |

**Why This Matters**:

- IAM roles must exist before pod identity associations can reference them
- Pod identity associations must exist before application pods start
- Incorrect ordering causes authentication failures

**How to Verify**:

Check your Fleet bundle's subchart configurations:

```yaml
# IAM role hook should have weight -10
ack-iam-role-association:
  hook:
    weight: -10  # ✅ Correct

# Pod identity hook should have weight -5
ack-pod-identity-association:
  hook:
    bootstrap:
      # Weight is set internally by the chart to -5
```

**Do NOT**:

- Change `ack-iam-role-association.hook.weight` unless you have a specific reason
- Set hook weights on your main application resources (they should use default weight 0)

---

### Step 5: Add Fleet Bundle Dependency

Ensure your Fleet bundle declares a dependency on the ACK IAM Controller bundle.

Edit `blueprints/<your-service>/fleet.yaml`:

```yaml
# Fleet Bundle Dependencies
dependsOn:
  - name: ack-iam-controller-blueprints-ack-iam-controller
```

**Why**: This ensures ACK IAM Controller is deployed and ready before your bundle attempts to create IAM Role CRDs.

**Dependency Name Format**: `<gitrepo-name>-<path-to-bundle>`

---

### Step 6: Create GitRepo Resource

Create a Fleet GitRepo resource to sync your bundle from Git.

Create `blueprints/gitrepos/<your-service>-repo.yaml`:

```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: <your-service>
  namespace: fleet-default
spec:
  repo: https://github.com/<org>/mcm-eks-fleet-blueprints
  branch: main
  paths:
    - blueprints/<your-service>
  pollingInterval: 60s
  targets:
    - clusterSelector:
        matchLabels:
          cluster-type: eks
```

---

### Step 7: Document Required Cluster Labels

Update your service's README to document required cluster labels.

Example:

```markdown
## Required Cluster Labels

| Label | Required | Description | Example |
|-------|----------|-------------|---------|
| `cluster-type` | Yes | Cluster type for targeting | `eks` |
| `addon-<your-service>` | Yes | Enable service deployment | `"true"` |
| `cluster-name` | Yes | EKS cluster name | `prod-eks-us-west-2` |
| `aws-region` | Yes | AWS region | `us-west-2` |
| `aws-account-id` | Yes | AWS account ID (numeric) | `"123456789012"` |
| `<your-service>-role-name` | No | Custom IAM role name | `ProdMyServiceRole` |

Example:

\```bash
kubectl label cluster my-cluster \
  cluster-type=eks \
  addon-<your-service>=true \
  cluster-name=prod-eks-us-west-2 \
  aws-region=us-west-2 \
  aws-account-id="123456789012"
\```
```

---

### Step 8: Test Deployment

Test the integration on a single cluster before deploying Fleet-wide.

#### Manual Testing (without Fleet)

1. Create test values file (`config/<your-service>/test-values.yaml`):

```yaml
clusterName: test-cluster
awsRegion: us-west-2
awsAccountId: "123456789012"

ack-iam-role-association:
  enabled: true
  iamRole:
    name: TestMyServiceRole
    policies:
      - arn:aws:iam::aws:policy/<YourPolicy>

# Your service's values...
```

2. Install manually:

```bash
helm install <your-service> \
  charts/<your-service>-<version>.tgz \
  -f config/<your-service>/test-values.yaml \
  -n <namespace>
```

3. Verify IAM role creation:

```bash
# Check hook job logs
kubectl logs -n <namespace> job/<short-name>-iam-role-create-role

# Verify Role CRD created
kubectl get role.iam.services.k8s.aws -n <namespace>

# Check IAM role in AWS
aws iam get-role --role-name TestMyServiceRole
```

#### Fleet Testing

1. Apply GitRepo:

```bash
kubectl apply -f blueprints/gitrepos/<your-service>-repo.yaml
```

2. Label a test cluster:

```bash
kubectl label cluster test-cluster addon-<your-service>=true
```

3. Monitor deployment:

```bash
# Check bundle status
kubectl get bundles -n fleet-default | grep <your-service>

# Check deployment to cluster
kubectl describe bundle -n fleet-default <bundle-name>
```

---

## Troubleshooting

### Hook Job Fails

**Check logs**:

```bash
kubectl logs -n <namespace> job/<iam-role-hook-job-name>
```

**Common causes**:

1. **ACK IAM Controller not deployed**: Verify dependency bundle is ready
2. **Insufficient IAM permissions**: Check ACK IAM Controller's IAM role permissions
3. **Policy ARN typo**: Verify policy ARNs are correct
4. **Hook weight ordering**: Ensure weights follow -10 (IAM) → -5 (pod identity) → 0 (app)

### IAM Role Created But Policies Not Attached

**Check in AWS**:

```bash
aws iam list-attached-role-policies --role-name <role-name>
```

**Common causes**:

- ACK IAM Controller lacks `iam:AttachRolePolicy` permission
- Policy ARN doesn't exist in AWS account
- Typographical error in policy ARN

### Pod Identity Association References Wrong Role

**Verify role name matches**:

```yaml
# In fleet.yaml, ensure role names match:
ack-iam-role-association:
  iamRole:
    name: MyServiceRole  # ← Must match

ack-pod-identity-association:
  podIdentity:
    roleName: MyServiceRole  # ← Must match
```

---

## Best Practices

### 1. Use Shared Roles for Scale

For deployments with 100+ clusters:

- Use shared IAM role names (e.g., `MCMMyServiceRole`)
- Avoids AWS IAM role limits (~1000 roles per account)
- Simplifies IAM policy management

```yaml
iamRole:
  # Shared role across all clusters in account
  name: MCMMyServiceRole
```

### 2. Use Per-Cluster Roles for Isolation

For compliance or least-privilege requirements:

- Use cluster-specific role names via labels
- Enables fine-grained access control per cluster

```yaml
iamRole:
  # Per-cluster role via label
  name: ${ index .ClusterLabels "cluster-name" }-MyServiceRole
```

### 3. Tag IAM Roles for Cost Tracking

Always include tags for organization and cost allocation:

```yaml
iamRole:
  tags:
    - key: managed-by
      value: fleet
    - key: cluster
      value: ${ index .ClusterLabels "cluster-name" }
    - key: cost-center
      value: platform-engineering
```

### 4. Use Least Privilege Policies

- Prefer custom inline policies over broad managed policies
- Specify resource ARNs instead of `Resource: "*"` when possible
- Regularly audit IAM role permissions

### 5. Test Hook Execution Order

Before deploying to production:

1. Deploy to test cluster
2. Check hook job timestamps:

```bash
kubectl get jobs -n <namespace> --sort-by=.metadata.creationTimestamp
```

3. Verify IAM role hook (weight -10) executes before pod identity hook (weight -5)

---

## Examples of Integrated Services

### Example 1: AWS EBS CSI Driver

See `blueprints/aws-ebs-csi-driver/fleet.yaml` for a complete working example.

**Key configuration**:

- IAM role: `MCMAWSEBSCSIDriverRole`
- Policy: `arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy`
- Service account: `ebs-csi-controller-sa`
- Namespace: `kube-system`

### Example 2: AWS EFS CSI Driver (Hypothetical)

```yaml
ack-iam-role-association:
  enabled: true
  controllerName: aws-efs-csi-driver
  iamRole:
    name: ${ default "MCMAWSEFSCSIDriverRole" (get .ClusterLabels "efs-role-name") }
    policies:
      - arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy
```

### Example 3: AWS Load Balancer Controller (Hypothetical)

```yaml
ack-iam-role-association:
  enabled: true
  controllerName: aws-load-balancer-controller
  iamRole:
    name: MCMAWSLoadBalancerControllerRole
    inlinePolicies:
      ALBIngressPolicy: |
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Action": [
                "ec2:DescribeVpcs",
                "elasticloadbalancing:*",
                "iam:CreateServiceLinkedRole"
              ],
              "Resource": "*"
            }
          ]
        }
```

---

## Additional Resources

- **Chart README**: `packages/ack-iam-role-association/README.md`
- **Values Schema**: `packages/ack-iam-role-association/values.schema.json`
- **Examples**: `packages/ack-iam-role-association/examples/`
- **ACK IAM Controller Reference**: https://aws-controllers-k8s.github.io/community/reference/iam/
- **Fleet Documentation**: `ref_docs/fleet/`

---

## Summary Checklist

When integrating `ack-iam-role-association`, ensure you:

- [ ] Created dependency reference in `generated-changes/dependencies/`
- [ ] Configured IAM role values in Fleet bundle (`fleet.yaml`)
- [ ] Verified hook weight is `-10` (do not change)
- [ ] Added Fleet bundle dependency on `ack-iam-controller`
- [ ] Documented required cluster labels in README
- [ ] Tested on single cluster before Fleet-wide deployment
- [ ] Verified IAM role created in AWS
- [ ] Verified application pods authenticate successfully
- [ ] Added appropriate IAM role tags for cost tracking

---

**Questions or Issues?**

- Check the troubleshooting section in `packages/ack-iam-role-association/README.md`
- Review existing implementations in `blueprints/aws-ebs-csi-driver/`
- Open an issue in the repository
