# ACK IAM Controller Fleet Bundle

This Fleet bundle deploys the AWS Controllers for Kubernetes (ACK) IAM controller with EKS Pod Identity authentication using a declarative wrapper Helm chart approach.

## Components

1. **chart/**: Wrapper Helm chart that includes:
   - ACK IAM controller as a dependency (iam-chart subchart)
   - PodIdentityAssociation CRD template
2. **fleet.yaml**: Fleet configuration that deploys the wrapper chart and injects cluster-specific values

## Key Feature

This bundle uses the ACK EKS controller's `PodIdentityAssociation` CRD instead of a bootstrap Job. This makes the deployment **fully declarative** - everything is managed through Kubernetes manifests!

## Prerequisites

### 1. ACK EKS Controller Deployed

This bundle depends on the ACK EKS controller (Bundle 1) being deployed first. The ACK EKS controller watches for `PodIdentityAssociation` CRDs and creates the corresponding AWS EKS pod identity associations.

### 2. CloudFormation Stack

The IAM role for ACK IAM controller must exist (created via CloudFormation).

### 3. Cluster Labels

Ensure your clusters in Rancher are labeled with:

- `cluster-type: eks`
- `cluster-name: <actual-eks-cluster-name>`
- `aws-region: <region>`
- `aws-account-id: <account-id>` (e.g., `074597098702`)
- `ack-iam-role-name: <role-name>` (e.g., `ACKIAMControllerRole` - not full ARN)

**Note**: Fleet will automatically construct the full IAM role ARN from the account ID and role name.

## How It Works

1. **Wrapper Helm Chart Deployment**:
   - Fleet deploys the wrapper Helm chart to the cluster
   - Fleet's `targetCustomizations` inject cluster-specific values from cluster labels into Helm values
   - The wrapper chart renders both the PodIdentityAssociation CRD and the ACK IAM controller

2. **PodIdentityAssociation CRD Creation**:
   - The Helm chart template renders the `PodIdentityAssociation` CRD with cluster-specific values
   - ACK EKS controller watches for this CRD
   - ACK EKS controller calls AWS API to create the pod identity association
   - Association links: cluster + namespace + service-account + IAM role

3. **ACK IAM Controller Deployment**:
   - The iam-chart subchart deploys the ACK IAM controller
   - Controller's ServiceAccount (`ack-iam-controller`) now has a pod identity association
   - Pod Identity Agent provides AWS credentials to the controller
   - Controller starts and can manage IAM resources

## Cluster-Specific Configuration

Fleet injects cluster-specific values using `targetCustomizations` in `fleet.yaml`:

```yaml
targetCustomizations:
  - name: default
    helm:
      values:
        clusterName: "${ index .ClusterLabels \"cluster-name\" }"
        awsRegion: "${ index .ClusterLabels \"aws-region\" }"
        awsAccountId: "${ index .ClusterLabels \"aws-account-id\" | quote }"
        ackIamRoleName: "${ index .ClusterLabels \"ack-iam-role-arn\" }"
```

The Helm chart template then uses these values to construct the role ARN:
```yaml
roleARN: {{ printf "arn:aws:iam::%s:role/%s" (.Values.awsAccountId | toString) .Values.ackIamRoleName | quote }}
```

### Implementation Details

This implementation uses **Fleet's native Helm support** with `targetCustomizations` to inject cluster-specific values. No overlays or Kustomize needed!

**Advantages of this approach:**
- Fully declarative - no Jobs, no scripting
- Fleet-native - uses built-in Helm value injection
- Single source of truth - one chart for all clusters
- Type-safe - Helm templating validates values
- Clean separation - cluster-specific config in Fleet, templates in Helm

## Dependencies

This bundle depends on:
- `ack-eks-controller` bundle (Bundle 1)

## What You Can Do After This

Once the ACK IAM controller is deployed, you can use it to manage AWS IAM resources declaratively:

### Create IAM Roles

```yaml
apiVersion: iam.services.k8s.aws/v1alpha1
kind: Role
metadata:
  name: my-app-role
spec:
  name: MyAppRole
  assumeRolePolicyDocument: |
    {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "pods.eks.amazonaws.com"},
        "Action": ["sts:AssumeRole", "sts:TagSession"]
      }]
    }
  policies:
    - my-app-policy
```

### Create IAM Policies

```yaml
apiVersion: iam.services.k8s.aws/v1alpha1
kind: Policy
metadata:
  name: my-app-policy
spec:
  name: MyAppPolicy
  policyDocument: |
    {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Action": ["s3:GetObject"],
        "Resource": "*"
      }]
    }
```

### Create Pod Identity Associations for Other Controllers

```yaml
apiVersion: eks.services.k8s.aws/v1alpha1
kind: PodIdentityAssociation
metadata:
  name: my-controller-pod-identity
spec:
  clusterName: my-cluster
  namespace: default
  serviceAccount: my-controller
  roleARN: arn:aws:iam::123456789012:role/MyControllerRole
```

## Next Steps

1. Deploy additional ACK controllers (RDS, S3, etc.) using the same pattern
2. Use ACK IAM controller to create roles for application workloads
3. Use ACK EKS controller to manage pod identity associations for applications
