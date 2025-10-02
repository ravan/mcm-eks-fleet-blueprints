# Fleet Blueprints for EKS Fleet Management

This directory contains Fleet GitRepo, ClusterGroup, and Bundle configurations for deploying AWS EKS components and ACK controllers across multiple downstream clusters managed by Rancher.

## Directory Structure

```
blueprints/
├── cluster-groups/                  # ClusterGroup definitions
│   └── all-eks-clusters.yaml
├── gitrepos/                        # GitRepo resources for Fleet
│   └── ack-controllers-repo.yaml
├── pod-identity-agent/              # Bundle 0: EKS Pod Identity Agent
│   └── fleet.yaml
├── fleet-bootstrap-ack-eks/         # Bundle 1: Bootstrap Job (wrapper Helm chart)
│   ├── chart/                       # Helm chart for bootstrap Job
│   └── fleet.yaml
├── ack-eks-controller/              # Bundle 2: ACK EKS Controller
│   ├── fleet.yaml
│   └── README.md
├── ack-iam-controller/              # Bundle 3: ACK IAM Controller (wrapper Helm chart)
│   ├── chart/                       # Wrapper Helm chart with PodIdentityAssociation
│   ├── fleet.yaml
│   └── README.md
└── README.md
```

## Components Overview

### Bundle 0: EKS Pod Identity Agent

**Purpose**: Deploys the EKS Pod Identity Agent DaemonSet to all clusters. This is required for Pod Identity to work.

**Implementation**: Direct Helm chart from Git repository

**Dependencies**: None

### Bundle 1: Fleet Bootstrap Job

**Purpose**: Creates the pod identity association for the ACK EKS controller

**Implementation**: Wrapper Helm chart that packages a Kubernetes Job. Uses Fleet's `targetCustomizations` to inject cluster-specific values from cluster labels.

**Dependencies**: Bundle 0 (Pod Identity Agent)

### Bundle 2: ACK EKS Controller

**Purpose**: Deploys the ACK EKS controller which manages EKS resources including pod identity associations.

**Implementation**: Direct deployment from OCI registry. Uses Fleet's `targetCustomizations` to inject AWS region.

**Dependencies**: Bundle 1 (Fleet Bootstrap Job)

### Bundle 3: ACK IAM Controller

**Purpose**: Deploys the ACK IAM controller which manages IAM resources (roles, policies, users, etc.)

**Implementation**: Wrapper Helm chart that packages both the ACK IAM controller (as subchart) and the PodIdentityAssociation CRD. Uses Fleet's `targetCustomizations` to inject cluster-specific values.

**Dependencies**: Bundle 2 (ACK EKS Controller)

**Special**: Fully declarative - uses `PodIdentityAssociation` CRD (no Job needed!)

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

Fleet will automatically:
- Deploy Pod Identity Agent (Bundle 0)
- Run bootstrap Job and deploy ACK EKS controller (Bundle 1)
- Create PodIdentityAssociation CRD and deploy ACK IAM controller (Bundle 2)

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
Fleet Bundle 1: Fleet Bootstrap Job (wrapper Helm chart)
         ↓
Fleet Bundle 2: ACK EKS Controller
         ↓
Fleet Bundle 3: ACK IAM Controller (wrapper Helm chart with PodIdentityAssociation CRD)
         ↓
Fleet Bundle 4+: Additional Controllers (declarative CRDs)
```

## Implementation Pattern

All bundles use **Fleet's native Helm support with targetCustomizations** to inject cluster-specific values from cluster labels:

- **Pod Identity Agent**: Direct Helm chart from Git
- **Fleet Bootstrap Job**: Wrapper Helm chart with Job template
- **ACK EKS Controller**: Direct Helm chart from OCI registry
- **ACK IAM Controller**: Wrapper Helm chart with subchart + PodIdentityAssociation CRD template

No overlays, no Kustomize, no manual configuration required - Fleet handles everything automatically!

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

### Bootstrap Job Failing

```bash
kubectl logs -n fleet-system -l app=fleet-bootstrap,component=ack-eks-pod-identity
```

Common issues:
- fleet-bootstrap service account doesn't have pod identity association
- Incorrect cluster name or role ARN in Job environment variables
- AWS API rate limiting

### ACK Controller Pod Not Starting

```bash
kubectl describe pod -n ack-system <pod-name>
kubectl logs -n ack-system <pod-name>
```

Common issues:
- Pod identity association not created
- IAM role doesn't have correct permissions
- IAM role trust policy incorrect (must use `pods.eks.amazonaws.com`)

### PodIdentityAssociation CRD Not Working

```bash
kubectl describe podidentityassociation -n ack-system ack-iam-controller-pod-identity
```

Common issues:
- ACK EKS controller not running or not healthy
- Cluster labels not correctly set or misspelled
- Cluster name mismatch
- IAM role ARN construction failed (check account ID and role name labels)

## Architecture Notes

### Wrapper Helm Chart Pattern

This implementation uses wrapper Helm charts to solve the challenge of injecting cluster-specific values into Kubernetes resources:

**Benefits**:
1. **Fleet-native**: Uses Fleet's built-in `targetCustomizations` with Helm
2. **Type-safe**: Helm templating validates values at render time
3. **Declarative**: Everything defined in Git, no manual steps
4. **Single source**: One chart works for all clusters
5. **Clean separation**: Cluster config in Fleet, templates in Helm

**When to use wrapper charts**:
- When deploying resources that need cluster-specific values (Jobs, CRDs, ConfigMaps)
- When combining multiple resources in a single deployment unit
- When adding custom resources alongside an upstream Helm chart

### Bootstrap Pattern

The bootstrap pattern solves the "chicken and egg" problem:

1. **Initial Bootstrap** (manual, once per cluster): Creates pod identity association for `fleet-bootstrap` service account
2. **Fleet Bootstrap Job** (automated): Uses `fleet-bootstrap` SA to create pod identity association for ACK EKS controller
3. **Subsequent Controllers** (automated): ACK EKS controller creates pod identity associations via CRDs

This pattern allows fully automated deployment after the initial per-cluster bootstrap.

### Dependency Ordering

Fleet's `dependsOn` ensures proper deployment order:
- Pod Identity Agent → Fleet Bootstrap Job → ACK EKS Controller → ACK IAM Controller

If a dependency fails, Fleet will not deploy dependent bundles until the issue is resolved.

## Next Steps

After successful deployment of ACK controllers:

1. **Deploy Additional ACK Controllers**: Use the same pattern (PodIdentityAssociation CRD + Helm chart)
2. **Manage IAM Resources**: Create IAM roles, policies, users via ACK IAM CRDs
3. **Manage EKS Resources**: Create clusters, node groups, addons via ACK EKS CRDs
4. **Application Deployments**: Use ACK to create IAM roles and pod identity associations for your applications

## Example: Deploy Additional ACK Controller

Create a new bundle for RDS controller:

```
blueprints/ack-rds-controller/
├── fleet.yaml
└── pod-identity-association.yaml
```

The PodIdentityAssociation CRD:

```yaml
apiVersion: eks.services.k8s.aws/v1alpha1
kind: PodIdentityAssociation
metadata:
  name: ack-rds-controller-pod-identity
  namespace: ack-system
spec:
  clusterName: my-cluster
  namespace: ack-system
  serviceAccount: ack-rds-controller
  roleARN: arn:aws:iam::123456789012:role/ACKRDSControllerRole
```

## References

- [Fleet Documentation](https://fleet.rancher.io/)
- [ACK Documentation](https://aws-controllers-k8s.github.io/community/)
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [CloudFormation](https://docs.aws.amazon.com/cloudformation/)
- [Rancher Multi-Cluster Management](https://ranchermanager.docs.rancher.com/)
