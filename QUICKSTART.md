# Quick Start Guide: Fleet + ACK Controllers + Pod Identity

This guide helps you quickly deploy ACK controllers with EKS Pod Identity across multiple EKS clusters using Rancher Fleet.

## Overview

- **CloudFormation**: Creates IAM roles once per AWS account
- **Bootstrap Script**: Runs once per cluster to create initial pod identity association
- **Fleet**: Automatically deploys everything else to all clusters

## Quick Start (3 Steps)

### Step 1: Deploy CloudFormation Stack (5 minutes)

```bash
cd cloudformation/

# Deploy the stack
aws cloudformation create-stack \
  --stack-name ack-controllers-roles \
  --template-body file://ack-controllers-roles.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --profile <your-aws-profile>

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name ack-controllers-roles \
  --profile <your-aws-profile>

# Get the role ARNs (save these!)
aws cloudformation describe-stacks \
  --stack-name ack-controllers-roles \
  --query 'Stacks[0].Outputs' \
  --profile <your-aws-profile>
```

**Output**: You'll get 3 role ARNs:
- `ACKIAMControllerRoleArn`
- `ACKEKSControllerRoleArn`
- `FleetBootstrapRoleArn`

### Step 2: Bootstrap Each Cluster (2 minutes per cluster)

For each EKS cluster, run:

```bash
./scripts/bootstrap-cluster.sh \
  --cluster-name <your-cluster-name> \
  --role-arn <FleetBootstrapRoleArn-from-step-1> \
  --region <your-aws-region> \
  --profile <your-aws-profile>
```

Example:
```bash
./scripts/bootstrap-cluster.sh \
  --cluster-name prod-eks-1 \
  --role-arn arn:aws:iam::123456789012:role/ACKFleetBootstrapRole \
  --region us-west-2 \
  --profile myprofile
```

### Step 3: Deploy via Fleet (10 minutes)

1. **Label your clusters in Rancher**:

   For each cluster, add these labels in the Rancher UI:
   - `cluster-type` = `eks`
   - `cluster-name` = `<eks-cluster-name>` (e.g., `prod-eks-1`)
   - `aws-region` = `<region>` (e.g., `us-west-2`)
   - `aws-account-id` = `<account-id>`
   - `ack-iam-role-name` = `<ACKIAMControllerRoleArn from Step 1>`
   - `ack-eks-role-name` = `<ACKEKSControllerRoleArn from Step 1>`

2. **Update GitRepo URLs**:

   Edit these files to point to your Git repository:
   - `blueprints/gitrepos/pod-identity-agent-repo.yaml`
   - `blueprints/gitrepos/ack-controllers-repo.yaml`

3. **Apply ClusterGroup**:
   ```bash
   kubectl apply -f blueprints/cluster-groups/all-eks-clusters.yaml
   ```

4. **Commit and push to Git**:
   ```bash
   git add .
   git commit -m "Add Fleet blueprints for ACK controllers"
   git push origin main
   ```

5. **Apply GitRepo resources**:
   ```bash
   kubectl apply -f blueprints/gitrepos/pod-identity-agent-repo.yaml
   kubectl apply -f blueprints/gitrepos/ack-controllers-repo.yaml
   ```

## Verify Deployment

### Check Fleet Status

```bash
# Check GitRepos
kubectl get gitrepo -n fleet-default

# Check Bundles
kubectl get bundles -n fleet-default

# Check BundleDeployments
kubectl get bundledeployments -A
```

### Check Downstream Cluster

Switch to a downstream cluster and verify:

```bash
# Set kubeconfig for downstream cluster
export KUBECONFIG=<path-to-cluster-kubeconfig>

# Check Pod Identity Agent
kubectl get daemonset -n kube-system eks-pid-agent
kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent

# Check ACK Controllers
kubectl get pods -n ack-system

# Should see:
# - ack-eks-controller-xxxxx
# - ack-iam-controller-xxxxx

# Check pod identity associations
aws eks list-pod-identity-associations \
  --cluster-name <cluster-name> \
  --region <region>
```

## What Gets Deployed

After Step 3, Fleet automatically deploys to all labeled clusters:

1. **Pod Identity Agent** (DaemonSet in kube-system)
2. **ACK EKS Controller** (Deployment in ack-system)
3. **ACK IAM Controller** (Deployment in ack-system)

## Deployment Timeline

- **Bundle 0** (Pod Identity Agent): ~2-3 minutes
- **Bundle 1** (ACK EKS Controller + Bootstrap): ~3-4 minutes
- **Bundle 2** (ACK IAM Controller): ~2-3 minutes

**Total**: ~10 minutes per cluster after Fleet is configured

## Adding More Clusters

To add a new cluster:

1. Run bootstrap script (Step 2) for the new cluster
2. Label the cluster in Rancher with the required labels
3. Fleet automatically deploys everything!

## What Can You Do Next?

With ACK controllers deployed, you can now manage AWS resources via Kubernetes CRDs:

### Create an IAM Role

```yaml
apiVersion: iam.services.k8s.aws/v1alpha1
kind: Role
metadata:
  name: my-app-role
  namespace: default
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
```

### Create a Pod Identity Association

```yaml
apiVersion: eks.services.k8s.aws/v1alpha1
kind: PodIdentityAssociation
metadata:
  name: my-app-pod-identity
  namespace: default
spec:
  clusterName: my-cluster
  namespace: default
  serviceAccount: my-app-sa
  roleARN: arn:aws:iam::123456789012:role/MyAppRole
```

### Deploy More ACK Controllers

Use the same pattern to deploy additional ACK controllers (RDS, S3, Lambda, etc.):

1. Add IAM role to CloudFormation template
2. Create Fleet bundle with PodIdentityAssociation CRD
3. Commit and Fleet deploys it!

## Troubleshooting

### Common Issues

**GitRepo not syncing**:
```bash
kubectl describe gitrepo -n fleet-default <gitrepo-name>
kubectl logs -n fleet-default -l gitjob.fleet.cattle.io/gitrepo=<gitrepo-name>
```

**Bootstrap Job failing**:
```bash
kubectl logs -n fleet-system -l app=fleet-bootstrap
```
- Check that bootstrap pod identity association exists
- Verify role ARN is correct

**ACK Controller not starting**:
```bash
kubectl describe pod -n ack-system <pod-name>
```
- Check pod identity association was created
- Verify IAM role permissions

## Architecture Diagram

```
┌─────────────────────────────────────────┐
│    AWS Account (Once)                   │
│  ┌───────────────────────────────────┐  │
│  │  CloudFormation Stack             │  │
│  │  - ACK IAM Controller Role        │  │
│  │  - ACK EKS Controller Role        │  │
│  │  - Fleet Bootstrap Role           │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│    Per Cluster (Once)                   │
│  ┌───────────────────────────────────┐  │
│  │  Bootstrap Script                 │  │
│  │  Creates: fleet-bootstrap         │  │
│  │  pod identity association         │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│    Fleet (Automated)                    │
│  ┌───────────────────────────────────┐  │
│  │  Bundle 0: Pod Identity Agent     │  │
│  └───────────────────────────────────┘  │
│              ↓                          │
│  ┌───────────────────────────────────┐  │
│  │  Bundle 1: ACK EKS Controller     │  │
│  │  (Bootstrap Job creates pod       │  │
│  │   identity association)           │  │
│  └───────────────────────────────────┘  │
│              ↓                          │
│  ┌───────────────────────────────────┐  │
│  │  Bundle 2: ACK IAM Controller     │  │
│  │  (Uses PodIdentityAssociation     │  │
│  │   CRD - declarative!)             │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## Support

For detailed documentation, see:
- `blueprints/README.md` - Full documentation
- `blueprints/ack-eks-controller/README.md` - ACK EKS controller details
- `blueprints/ack-iam-controller/README.md` - ACK IAM controller details
- `cloudformation/ack-controllers-roles.yaml` - CloudFormation template

For issues, check the troubleshooting section in `blueprints/README.md`.
