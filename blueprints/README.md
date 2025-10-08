# Fleet Blueprints for EKS Fleet Management

This directory contains Fleet GitRepo, ClusterGroup, and Bundle configurations for deploying AWS EKS components and ACK controllers across multiple downstream clusters managed by Rancher.

## Directory Structure

```
blueprints/
├── cluster-groups/          # ClusterGroup definitions
│   └── all-eks-clusters.yaml
├── gitrepos/                # GitRepo resources for Fleet
│   ├── pod-identity-agent-repo.yaml
│   └── ack-controllers-repo.yaml
├── pod-identity-agent/      # Bundle 0: EKS Pod Identity Agent
│   ├── fleet.yaml
│   └── README.md
├── ack-eks-controller/      # Bundle 1: ACK EKS Controller
│   ├── fleet.yaml
│   └── README.md
├── ack-iam-controller/      # Bundle 2: ACK IAM Controller
│   ├── fleet.yaml
│   └── README.md
└── README.md
```

## Components Overview

### Bundle 0: Pod Identity Agent

Deploys the EKS Pod Identity Agent DaemonSet. Required for Pod Identity authentication.

**Source**: Helm repository (`eks-pod-identity-agent`)

**Dependencies**: None

### Bundle 1: ACK EKS Controller

Deploys the ACK EKS controller which manages EKS resources including pod identity associations.

**Source**: Helm repository (`eks-chart` with `ack-eks-bootstrap` subchart)

**Pod Identity**: Created via AWS CLI by `ack-eks-bootstrap` subchart

**Dependencies**: Bundle 0

### Bundle 2: ACK IAM Controller

Deploys the ACK IAM controller which manages IAM resources (roles, policies, users, etc.)

**Source**: Helm repository (`iam-chart` with `ack-pod-identity-association` subchart)

**Pod Identity**: Created declaratively via PodIdentityAssociation CRD by `ack-pod-identity-association` subchart

**Dependencies**: Bundle 1

## Architecture: Multi-Stage Deployment

### Stage 1: Account-Level Setup (One-Time)

1. **Deploy CloudFormation Stack**:
   ```bash
   aws cloudformation create-stack \
     --stack-name ack-controllers-roles \
     --template-body file://cloudformation/ack-controllers-roles.yaml \
     --capabilities CAPABILITY_NAMED_IAM

   # Get role ARNs
   aws cloudformation describe-stacks \
     --stack-name ack-controllers-roles \
     --query 'Stacks[0].Outputs'
   ```

   This creates:
   - IAM role for ACK IAM Controller
   - IAM role for ACK EKS Controller
   - IAM role for Fleet Bootstrap operations

### Stage 2: Per-Cluster Setup (One-Time per Cluster)

1. **Run Bootstrap Script**:
   ```bash
   ./scripts/bootstrap-cluster.sh \
     --cluster-name my-eks-cluster \
     --role-arn <fleet-bootstrap-role-arn> \
     --region us-west-2
   ```

   This creates ONE pod identity association for the `fleet-bootstrap` service account.

### Stage 3: Fleet Deployment (Fully Automated)

1. **Apply ClusterGroup**:
   ```bash
   kubectl apply -f blueprints/cluster-groups/all-eks-clusters.yaml
   ```

2. **Commit and Push**:
   ```bash
   git add blueprints/
   git commit -m "Add ACK controllers Fleet blueprints"
   git push
   ```

3. **Apply GitRepo Resources**:
   ```bash
   # Update repo URL in gitrepos/*.yaml first!
   kubectl apply -f blueprints/gitrepos/pod-identity-agent-repo.yaml
   kubectl apply -f blueprints/gitrepos/ack-controllers-repo.yaml
   ```

Fleet automatically deploys all bundles in order with proper dependency management.

## Prerequisites

### Rancher Setup
- Rancher Manager installed and configured
- Fleet controllers running (installed by default with Rancher)
- Downstream EKS clusters registered with Rancher

### Cluster Labels

Clusters must be labeled in Rancher with:

| Label | Description | Example |
|-------|-------------|---------|
| `cluster-type` | Cluster type | `eks` |
| `cluster-name` | EKS cluster name | `my-eks-cluster` |
| `aws-region` | AWS region | `us-west-2` |
| `aws-account-id` | AWS account ID | `123456789012` |
| `ack-iam-role-name` | ACK IAM controller role name (not full ARN) | `ACKIAMControllerRole` |
| `ack-eks-role-name` | ACK EKS controller role name (not full ARN) | `ACKEKSControllerRole` |

**Note**: Fleet will automatically construct the full IAM role ARNs from the account ID and role names.
Format: `arn:aws:iam::{aws-account-id}:role/{role-name}`

#### How to Label Clusters in Rancher

**Via Rancher UI**:
1. Go to Cluster Management
2. Select your cluster
3. Click "Edit Config" or the three-dot menu → "Edit Config"
4. Add labels in the Labels & Annotations section

**Via kubectl**:
```bash
kubectl label cluster <cluster-id> \
  cluster-type=eks \
  cluster-name=my-eks-cluster \
  aws-region=us-west-2 \
  aws-account-id=123456789012 \
  ack-iam-role-name=ACKIAMControllerRole \
  ack-eks-role-name=ACKEKSControllerRole \
  -n fleet-default
```

**Important**: Use role names only (not full ARNs). Kubernetes labels cannot contain special characters like `:` or `/` that are present in ARNs.

## Deployment Flow

```
CloudFormation (IAM Roles)
         ↓
Bootstrap Script (One Pod Identity Association per Cluster)
         ↓
Fleet Bundle 0: Pod Identity Agent
         ↓
Fleet Bundle 1: ACK EKS Controller (with bootstrap hook)
         ↓
Fleet Bundle 2: ACK IAM Controller (with bootstrap hook)
         ↓
Additional Controllers (optional)
```

## Implementation Pattern

All bundles use Fleet's `targetCustomizations` to inject cluster-specific values from cluster labels. Charts are published to a Helm repository and include subcharts for pod identity management.

## Monitoring Deployment

### Check GitRepo Status

```bash
kubectl get gitrepo -n fleet-default
kubectl describe gitrepo -n fleet-default ack-controllers
```

### Check Bundles

```bash
kubectl get bundles -n fleet-default
```

### Check BundleDeployments

```bash
kubectl get bundledeployments -A
```

### Check on Downstream Cluster

```bash
# Switch to downstream cluster
export KUBECONFIG=<path-to-downstream-kubeconfig>

# Check Pod Identity Agent
kubectl get daemonset -n kube-system eks-pid-agent

# Check ACK Controllers
kubectl get pods -n ack-system

# Check Pod Identity Associations (via ACK CRDs)
kubectl get podidentityassociations -A

# Check IAM Roles (via ACK CRDs)
kubectl get roles.iam.services.k8s.aws -A
```

## Troubleshooting

### GitRepo Not Syncing

```bash
kubectl describe gitrepo -n fleet-default ack-controllers
kubectl logs -n fleet-default -l gitjob.fleet.cattle.io/gitrepo=ack-controllers
```

### Pod Identity Issues

Common issues:
- fleet-bootstrap service account doesn't have pod identity association (run bootstrap script first)
- Incorrect cluster labels
- IAM role doesn't have correct permissions or trust policy

### ACK Controller Pod Not Starting

```bash
kubectl describe pod -n ack-system <pod-name>
kubectl logs -n ack-system <pod-name>
```

Check that pod identity association exists and IAM role trust policy uses `pods.eks.amazonaws.com`.

### PodIdentityAssociation CRD Not Reconciling

```bash
kubectl describe podidentityassociation -n ack-system
```

Ensure ACK EKS controller is running and cluster labels are correct.

## Architecture Notes

### Subchart Pattern

Charts use subcharts to handle pod identity association creation:
- **ack-eks-bootstrap**: Used by EKS controller, creates association via AWS CLI
- **ack-pod-identity-association**: Reusable subchart for other controllers, creates association declaratively via CRD

### Bootstrap Pattern

Solves the "chicken and egg" problem:

1. Manual bootstrap (once per cluster): Creates pod identity for `fleet-bootstrap` service account
2. Automated deployment: Subcharts use `fleet-bootstrap` SA to create pod identity for controllers
3. Subsequent controllers: Use declarative PodIdentityAssociation CRDs (no manual bootstrap)

### Dependency Ordering

Fleet's `dependsOn` ensures: Pod Identity Agent → ACK EKS Controller → ACK IAM Controller

## Adding New ACK Controllers

To add additional ACK service controllers (RDS, S3, etc.), see the detailed guide in `packages/ack-pod-identity-association/README.md` which provides complete instructions for:

1. Creating package definitions
2. Adding the `ack-pod-identity-association` subchart dependency
3. Building charts
4. Creating Fleet bundles with proper configuration

This reusable pattern enables declarative pod identity management for all controllers.

## References

- [Fleet Documentation](https://fleet.rancher.io/)
- [ACK Documentation](https://aws-controllers-k8s.github.io/community/)
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [CloudFormation](https://docs.aws.amazon.com/cloudformation/)
- [Rancher Multi-Cluster Management](https://ranchermanager.docs.rancher.com/)
