# Fleet Blueprints for EKS Fleet Management

This directory contains Fleet GitRepo, ClusterGroup, and Bundle configurations for deploying AWS EKS components across multiple downstream clusters managed by Rancher.

## Directory Structure

```
blueprints/
├── cluster-groups/          # ClusterGroup definitions
│   └── all-eks-clusters.yaml
├── gitrepos/                # GitRepo resources for Fleet
│   └── pod-identity-agent-repo.yaml
├── pod-identity-agent/      # EKS Pod Identity Agent bundle
│   └── fleet.yaml
└── README.md
```

## Components

### 1. EKS Pod Identity Agent

**Purpose**: Deploys the EKS Pod Identity Agent to all downstream EKS clusters automatically.

**Files**:
- `pod-identity-agent/fleet.yaml` - Fleet configuration for Helm deployment
- `gitrepos/pod-identity-agent-repo.yaml` - GitRepo resource to monitor this repository
- `cluster-groups/all-eks-clusters.yaml` - ClusterGroup targeting all EKS clusters

**Deployment**:
The Pod Identity Agent is deployed using the upstream Helm chart from GitHub. Fleet pulls the chart directly without requiring local vendoring.

## Prerequisites

### Rancher Setup
- Rancher Manager installed and configured
- Fleet controllers running (installed by default with Rancher)
- Downstream EKS clusters registered with Rancher

### Cluster Labels
Clusters must be labeled with the following labels in Rancher for automatic configuration:

- `cluster-type: eks` - Identifies the cluster as an EKS cluster
- `cluster-name: <eks-cluster-name>` - The actual EKS cluster name (e.g., `my-eks-cluster`)
- `aws-region: <region>` - The AWS region (e.g., `us-west-2`, `eu-west-1`)

#### How to Label Clusters in Rancher

**Via Rancher UI**:
1. Go to Cluster Management
2. Select your cluster
3. Click "Edit Config" or the three-dot menu → "Edit Config"
4. Add labels in the Labels & Annotations section:
   - `cluster-type` = `eks`
   - `cluster-name` = `your-eks-cluster-name`
   - `aws-region` = `your-aws-region`

**Via kubectl**:
```bash
# Label the cluster resource in the Rancher management cluster
kubectl label cluster <cluster-id> \
  cluster-type=eks \
  cluster-name=my-eks-cluster \
  aws-region=us-west-2 \
  -n fleet-default
```

## Deployment Instructions

### Step 1: Apply ClusterGroup

First, apply the ClusterGroup to define which clusters should receive deployments:

```bash
kubectl apply -f blueprints/cluster-groups/all-eks-clusters.yaml
```

This creates a ClusterGroup named `all-eks-clusters` that selects all clusters with `cluster-type: eks` label.

### Step 2: Commit and Push to Git

Commit the blueprint configurations to your Git repository:

```bash
git add blueprints/
git commit -m "Add Fleet blueprints for EKS Pod Identity Agent"
git push origin main
```

### Step 3: Apply GitRepo Resource

Apply the GitRepo resource to tell Fleet to monitor this repository:

```bash
kubectl apply -f blueprints/gitrepos/pod-identity-agent-repo.yaml
```

**Important**: Before applying, update the `repo` field in `pod-identity-agent-repo.yaml` to point to your actual Git repository URL.

### Step 4: Verify Deployment

Monitor the deployment status:

```bash
# Check GitRepo status
kubectl get gitrepo -n fleet-default eks-pod-identity-agent

# Check Bundle status
kubectl get bundles -n fleet-default

# Check BundleDeployments
kubectl get bundledeployments -A

# View detailed status
kubectl describe gitrepo -n fleet-default eks-pod-identity-agent
```

### Step 5: Verify on Downstream Clusters

Once deployed, verify the Pod Identity Agent is running on each downstream cluster:

```bash
# Switch to downstream cluster context
export KUBECONFIG=<path-to-downstream-kubeconfig>

# Check DaemonSet
kubectl get daemonset -n kube-system eks-pid-agent

# Check Pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent

# Check Pod logs
kubectl logs -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
```

## How It Works

1. **GitRepo Scanning**: Fleet's `gitjob-controller` scans the Git repository at the specified path (`blueprints/pod-identity-agent`)
2. **Bundle Creation**: Fleet finds `fleet.yaml` and creates a Bundle resource
3. **Target Matching**: Fleet evaluates the `targets` in the GitRepo and matches clusters via the ClusterGroup selector
4. **BundleDeployment**: For each matched cluster, Fleet creates a BundleDeployment
5. **Agent Deployment**: The Fleet agent on each downstream cluster pulls the BundleDeployment and deploys it via Helm
6. **Status Reporting**: Fleet agents continuously monitor the deployment and report status back to the management cluster

## Customization

### Adding More Clusters

Simply label new clusters with `cluster-type: eks` and the required labels (`cluster-name`, `aws-region`). Fleet will automatically deploy to them.

### Excluding Specific Clusters

Add additional labels to clusters and update the ClusterGroup selector. For example, to exclude dev clusters:

```yaml
spec:
  selector:
    matchLabels:
      cluster-type: eks
    matchExpressions:
      - key: environment
        operator: NotIn
        values:
          - dev
```

### Customizing Helm Values Per Cluster

Edit `pod-identity-agent/fleet.yaml` and add more `targetCustomizations` entries:

```yaml
targetCustomizations:
  - name: production
    helm:
      values:
        # Production-specific values
        resources:
          limits:
            memory: 256Mi
    clusterSelector:
      matchLabels:
        environment: prod

  - name: development
    helm:
      values:
        # Dev-specific values
        resources:
          limits:
            memory: 128Mi
    clusterSelector:
      matchLabels:
        environment: dev
```

## Troubleshooting

### GitRepo Not Syncing

```bash
# Check GitRepo status
kubectl describe gitrepo -n fleet-default eks-pod-identity-agent

# Check gitjob pods
kubectl get pods -n fleet-default -l gitjob.fleet.cattle.io/gitrepo=eks-pod-identity-agent

# View gitjob logs
kubectl logs -n fleet-default -l gitjob.fleet.cattle.io/gitrepo=eks-pod-identity-agent
```

### Bundle Not Created

```bash
# List bundles
kubectl get bundles -n fleet-default

# Check for errors in fleet-controller
kubectl logs -n cattle-fleet-system -l app=fleet-controller
```

### BundleDeployment Failing

```bash
# Check BundleDeployments
kubectl get bundledeployments -A

# Describe specific BundleDeployment
kubectl describe bundledeployment -n <cluster-namespace> <bundle-name>

# Check fleet-agent logs on downstream cluster
kubectl logs -n cattle-fleet-system -l app=fleet-agent
```

### Cluster Labels Not Applied

Verify cluster labels are set correctly:

```bash
# List clusters with labels
kubectl get clusters -n fleet-default --show-labels

# Check specific cluster
kubectl get cluster -n fleet-default <cluster-name> -o yaml
```

## Next Steps

After successfully deploying the Pod Identity Agent, you can:

1. Add blueprints for ACK IAM controller
2. Add blueprints for ACK EKS controller
3. Add blueprints for other AWS controllers or EKS addons
4. Create more sophisticated ClusterGroups for different deployment strategies

## References

- [Fleet Documentation](https://fleet.rancher.io/)
- [Fleet GitRepo Structure](https://fleet.rancher.io/gitrepo-structure/)
- [EKS Pod Identity Agent](https://github.com/aws/eks-pod-identity-agent)
- [Rancher Multi-Cluster Management](https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/kubernetes-clusters-in-rancher-setup)
