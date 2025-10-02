# ACK EKS Controller Fleet Bundle

This Fleet bundle deploys the AWS Controllers for Kubernetes (ACK) EKS controller with EKS Pod Identity authentication. The deployment consists of two separate bundles:

1. **fleet-bootstrap-ack-eks**: Bootstrap Job (wrapper Helm chart) that creates the pod identity association
2. **ack-eks-controller**: ACK EKS controller Helm chart deployment

## Components

This directory contains only the ACK EKS controller deployment configuration:

1. **fleet.yaml**: Fleet configuration for deploying the ACK EKS controller via Helm from OCI registry

The bootstrap Job is located in a separate bundle: `blueprints/fleet-bootstrap-ack-eks/`

## Prerequisites

### 1. CloudFormation Stack (One-time per Account)

Deploy the CloudFormation template to create IAM roles:

```bash
aws cloudformation create-stack \
  --stack-name ack-controllers-roles \
  --template-body file://cloudformation/ack-controllers-roles.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters ParameterKey=RoleNamePrefix,ParameterValue=ACK

# Wait for stack creation
aws cloudformation wait stack-create-complete \
  --stack-name ack-controllers-roles

# Get role ARNs
aws cloudformation describe-stacks \
  --stack-name ack-controllers-roles \
  --query 'Stacks[0].Outputs'
```

### 2. Bootstrap Per-Cluster (One-time per Cluster)

Create the initial pod identity association for the fleet-bootstrap service account:

```bash
./scripts/bootstrap-cluster.sh \
  --cluster-name my-eks-cluster \
  --role-arn arn:aws:iam::123456789012:role/ACKFleetBootstrapRole \
  --region us-west-2 \
  --profile myprofile
```

### 3. Cluster Labels

Ensure your clusters in Rancher are labeled with:

- `cluster-type: eks`
- `cluster-name: <actual-eks-cluster-name>`
- `aws-region: <region>`
- `aws-account-id: <account-id>` (e.g., `074597098702`)
- `ack-eks-role-name: <role-name>` (e.g., `ACKEKSControllerRole` - not full ARN)

**Note**: Fleet will automatically construct the full IAM role ARN from the account ID and role name.

## How It Works

1. **Bootstrap Job Execution** (fleet-bootstrap-ack-eks bundle):
   - Fleet deploys the bootstrap wrapper Helm chart to the cluster
   - Fleet's `targetCustomizations` inject cluster-specific values from cluster labels
   - Job uses the `fleet-bootstrap` ServiceAccount (which has a pre-created pod identity association)
   - Job runs `aws eks create-pod-identity-association` to create association for ACK EKS controller
   - Job completes successfully

2. **ACK EKS Controller Deployment** (this bundle):
   - Fleet deploys the ACK EKS controller Helm chart from OCI registry
   - Fleet's `targetCustomizations` inject the AWS region from cluster labels
   - Controller's ServiceAccount (`ack-eks-controller`) now has a pod identity association
   - Pod Identity Agent provides AWS credentials to the controller
   - Controller starts and can manage EKS resources

## Cluster-Specific Configuration

Fleet injects cluster-specific values using `targetCustomizations` in `fleet.yaml`:

```yaml
targetCustomizations:
  - name: default
    helm:
      values:
        aws:
          region: "${ index .ClusterLabels \"aws-region\" }"
```

The bootstrap Job (in `fleet-bootstrap-ack-eks` bundle) receives these cluster-specific values:

```yaml
targetCustomizations:
  - name: default
    helm:
      values:
        clusterName: "${ index .ClusterLabels \"cluster-name\" }"
        awsRegion: "${ index .ClusterLabels \"aws-region\" }"
        awsAccountId: "${ index .ClusterLabels \"aws-account-id\" | quote }"
        ackEksRoleArn: "${ index .ClusterLabels \"ack-eks-role-arn\" }"
```

### Implementation Details

Both bundles use **Fleet's native Helm support** with `targetCustomizations` to inject cluster-specific values:

**Advantages of this approach:**
- Fully automated - Fleet injects values from cluster labels
- Fleet-native - uses built-in Helm value injection
- Single source of truth - one chart for all clusters
- Type-safe - Helm templating validates values
- No manual configuration required per cluster

## Dependencies

This bundle depends on:
- `eks-pod-identity-agent` bundle (Bundle 0)

## Next Steps

After this bundle is successfully deployed:
1. ACK EKS controller can create `PodIdentityAssociation` CRDs
2. Deploy ACK IAM controller (Bundle 2) using a PodIdentityAssociation CRD
3. Deploy additional ACK controllers using PodIdentityAssociation CRDs
