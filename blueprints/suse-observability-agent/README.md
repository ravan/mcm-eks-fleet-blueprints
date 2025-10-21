# SUSE Observability Agent Blueprint

## Overview

This Fleet blueprint deploys the SUSE Observability Agent (powered by StackState) to Amazon EKS clusters for multi-cluster observability monitoring. The agent collects metrics, traces, logs, and topology data from Kubernetes clusters and sends them to a centralized SUSE Observability platform.

## Features

- **External Secret Integration**: Reads observability endpoint and API token from cluster-specific Kubernetes secrets created by Rancher
- **Helm Hook-Based Configuration**: Pre-install job creates ConfigMap from external secret before agent deployment
- **Multi-Agent Architecture**: Deploys node agent (DaemonSet), cluster agent, logs agent, and checks agent for comprehensive monitoring
- **Multi-Cluster Support**: Single GitRepo can deploy to multiple EKS clusters with cluster-specific secret references
- **Zero Configuration Updates**: Secret changes are automatically reflected without Helm upgrades

## Prerequisites

### Required External Secret

Before deployment, a Kubernetes secret must exist in the target cluster with the following format:

**Secret Name**: `<cluster-name>-observability` (e.g., `prod-eks-us-west-2-observability`)
**Secret Namespace**: `suse-observability` (configurable in `fleet.yaml`)
**Secret Keys**:
- `endpoint`: SUSE Observability URL (e.g., `https://observability.example.com`)
- `token`: API key for authentication

**Example Secret Creation**:

```bash
kubectl create secret generic prod-eks-us-west-2-observability \
  -n suse-observability \
  --from-literal=endpoint='https://observability.example.com' \
  --from-literal=token='your-api-key-here'
```

**Note**: In production, this secret is typically created by Rancher or a secret management system.

### Required Cluster Labels

Clusters must have the following labels configured:

| Label | Required | Description | Example |
|-------|----------|-------------|---------|
| `cluster-type` | Yes | Cluster type for targeting | `eks` |
| `observability-agent` | Yes | Enable observability agent deployment | `"true"` |
| `cluster-name` | Yes | EKS cluster name (used to construct secret name) | `prod-eks-us-west-2` |

## Deployment Architecture

### External Secret Mode

Unlike typical Helm charts that store configuration in `values.yaml`, this deployment uses an **external secret mode**:

1. Observability endpoint and API key are stored in an external Kubernetes secret (created by Rancher)
2. Helm chart receives placeholder values for schema validation (`https://placeholder.example.com`, `placeholder-api-key`)
3. Pre-install/pre-upgrade hook (weight -10) creates a ConfigMap by reading the external secret
4. Agent pods (weight 0) mount the ConfigMap as environment variables (`STS_URL`, `STS_STS_URL`, `STS_API_KEY`)

**Benefits**:
- Secrets are managed by Rancher (not stored in Git or Helm values)
- Secret rotation doesn't require Helm upgrades
- Supports different secrets per cluster via templating (`{{ .Values.stackstate.cluster.name }}-observability`)

### Hook Execution Order

The deployment uses Helm hooks to orchestrate the sequence of resource creation:

```
1. Weight -10: RBAC for ConfigMap Creation (ServiceAccount, Role, RoleBinding/ClusterRoleBinding)
   └─ Grants permissions to read secrets and create ConfigMaps

2. Weight -5: ConfigMap Creation Job
   └─ Reads external secret: <cluster-name>-observability
   └─ Extracts endpoint and token
   └─ Creates ConfigMap: <release-name>-url-configmap with STS_URL and STS_STS_URL

3. Weight 0: Agent Resources
   └─ ServiceAccounts
   └─ Node Agent DaemonSet (runs on every node)
   └─ Cluster Agent Deployment (cluster-wide monitoring)
   └─ Logs Agent DaemonSet (log collection)
   └─ Checks Agent Deployment (cluster checks)
   └─ All pods read STS_URL from ConfigMap and STS_API_KEY from external secret
```

### Chart Dependencies

The built chart includes two upstream dependencies from StackState:

1. **http-header-injector** (https://helm.stackstate.io/charts/http-header-injector-0.0.16.tgz)
   - Injects custom HTTP headers for API requests

2. **kubernetes-rbac-agent** (https://helm.stackstate.io/charts/kubernetes-rbac-agent-0.0.20.tgz)
   - Manages RBAC permissions for agent components

## Deployment

### Option 1: Via Fleet GitRepo (Recommended)

1. Create the external secret in the target cluster:
   ```bash
   # Set kubeconfig to target EKS cluster
   export KUBECONFIG=/path/to/target-cluster-kubeconfig

   # Create namespace
   kubectl create namespace suse-observability

   # Create secret (replace values)
   kubectl create secret generic <cluster-name>-observability \
     -n suse-observability \
     --from-literal=endpoint='https://your-observability-url.com' \
     --from-literal=token='your-api-key'
   ```

2. Apply the GitRepo resource:
   ```bash
   # Set kubeconfig to Rancher management cluster
   export KUBECONFIG=/path/to/rancher-cluster-kubeconfig

   kubectl apply -f blueprints/gitrepos/suse-observability-agent-repo.yaml
   ```

3. Label target clusters:
   ```bash
   # Add required labels to enable deployment
   kubectl label cluster <cluster-name> \
     observability-agent=true \
     cluster-name=<eks-cluster-name>
   ```

4. Monitor deployment:
   ```bash
   # Check GitRepo sync status
   kubectl get gitrepo -n fleet-default suse-observability-agent

   # Check bundle status
   kubectl get bundles -n fleet-default | grep observability

   # View bundle details
   kubectl describe bundle -n fleet-default <bundle-name>
   ```

### Option 2: Manual Installation (Testing)

For testing without Fleet:

```bash
# Create external secret first (see Option 1, step 1)

# Install chart from Helm repository
helm repo add mcm-eks https://ravan.github.io/mcm-eks-fleet-blueprints/
helm repo update

helm install suse-observability-agent mcm-eks/suse-observability-agent \
  --namespace suse-observability \
  --create-namespace \
  --set stackstate.cluster.name=<cluster-name> \
  --set stackstate.observabilitySecret.enabled=true \
  --set stackstate.observabilitySecret.namespace=suse-observability \
  --set stackstate.url=https://placeholder.example.com \
  --set stackstate.apiKey=placeholder-api-key
```

## Validation

### 1. Verify External Secret Exists

```bash
kubectl get secret -n suse-observability <cluster-name>-observability
```

Expected output:
- Secret exists with keys: `endpoint`, `token`

### 2. Verify ConfigMap Created by Hook

```bash
kubectl get configmap -n suse-observability | grep url-configmap
```

Expected output:
- ConfigMap exists (e.g., `suse-observability-agent-url-configmap`)
- Contains keys: `STS_URL`, `STS_STS_URL`

Check ConfigMap contents:

```bash
kubectl get configmap -n suse-observability <release-name>-url-configmap -o yaml
```

Expected output:
```yaml
data:
  STS_STS_URL: https://observability.example.com
  STS_URL: https://observability.example.com
```

### 3. Verify Agent Pods Running

```bash
kubectl get pods -n suse-observability
```

Expected output:
- Node agent pods (DaemonSet) on each node in `Running` state
- Cluster agent pod in `Running` state
- Logs agent pods (DaemonSet) on each node in `Running` state
- Checks agent pod in `Running` state

### 4. Verify Agent Connectivity

Check agent logs for successful connection to observability platform:

```bash
# Check cluster agent logs
kubectl logs -n suse-observability -l app.kubernetes.io/component=cluster-agent --tail=50

# Check node agent logs
kubectl logs -n suse-observability -l app.kubernetes.io/component=node-agent --tail=50
```

Expected output:
- No authentication errors
- Successful connection to observability URL
- Data being sent to platform

### 5. Verify Data in Observability Platform

1. Log in to SUSE Observability platform
2. Navigate to Infrastructure → Kubernetes
3. Verify cluster appears in the cluster list
4. Verify metrics, logs, and topology data are being ingested

## Troubleshooting

### GitRepo Not Syncing

```bash
# Check GitRepo status
kubectl describe gitrepo -n fleet-default suse-observability-agent

# View GitJob logs
kubectl logs -n fleet-default -l gitjob.fleet.cattle.io/gitrepo=suse-observability-agent
```

Common issues:
- Repository URL not accessible
- Branch doesn't exist
- Path doesn't contain `fleet.yaml`

### Bundle Not Deploying

```bash
# Check bundle status
kubectl get bundles -n fleet-default | grep observability

# View bundle details
kubectl describe bundle -n fleet-default <bundle-name>
```

Common issues:
- No clusters matching label selector (`observability-agent: true`)
- Template syntax errors in `fleet.yaml`
- Missing cluster label `cluster-name`

### External Secret Not Found

The ConfigMap creation hook (weight -5) may fail if the external secret doesn't exist.

**Check Hook Job Status**:

```bash
# List jobs in namespace
kubectl get jobs -n suse-observability | grep url-configmap

# View hook job logs
kubectl logs -n suse-observability job/<release-name>-url-configmap-creator

# Check job events
kubectl describe job -n suse-observability <release-name>-url-configmap-creator
```

**Common Error Messages**:

**1. Secret Not Found**

**Error**: `Error from server (NotFound): secrets "<cluster-name>-observability" not found`

**Resolution**:

1. Verify secret exists:
   ```bash
   kubectl get secret -n suse-observability <cluster-name>-observability
   ```

2. If missing, create the secret:
   ```bash
   kubectl create secret generic <cluster-name>-observability \
     -n suse-observability \
     --from-literal=endpoint='https://observability.example.com' \
     --from-literal=token='your-api-key'
   ```

3. Re-run Helm upgrade to trigger hook:
   ```bash
   helm upgrade suse-observability-agent mcm-eks/suse-observability-agent \
     -n suse-observability --reuse-values
   ```

**2. URL Key Not Found in Secret**

**Error**: `Error: URL not found in secret suse-observability/<cluster-name>-observability with key endpoint`

**Resolution**:

1. Check secret keys:
   ```bash
   kubectl get secret -n suse-observability <cluster-name>-observability -o jsonpath='{.data}' | jq
   ```

2. Ensure secret has `endpoint` and `token` keys:
   ```bash
   kubectl delete secret -n suse-observability <cluster-name>-observability
   kubectl create secret generic <cluster-name>-observability \
     -n suse-observability \
     --from-literal=endpoint='https://observability.example.com' \
     --from-literal=token='your-api-key'
   ```

**3. RBAC Permissions Error**

**Error**: `Error from server (Forbidden): secrets "<cluster-name>-observability" is forbidden`

**Root Cause**: ServiceAccount lacks permissions to read secrets (ClusterRole/Role not created or binding failed).

**Resolution**:

1. Check RBAC resources created by hook (weight -10):
   ```bash
   kubectl get serviceaccount -n suse-observability | grep url-configmap-creator
   kubectl get role -n suse-observability | grep url-configmap-creator
   kubectl get rolebinding -n suse-observability | grep url-configmap-creator

   # If secret is in different namespace, check ClusterRole
   kubectl get clusterrole | grep url-configmap-creator
   kubectl get clusterrolebinding | grep url-configmap-creator
   ```

2. If missing, manually create or re-deploy chart.

### ConfigMap Not Created

If the hook job succeeds but ConfigMap is missing:

```bash
# Check if ConfigMap was created and deleted
kubectl get events -n suse-observability --sort-by='.lastTimestamp' | grep configmap

# Verify hook delete policy
helm get manifest suse-observability-agent -n suse-observability | grep hook-delete-policy
```

Expected hook annotations:
```yaml
helm.sh/hook: pre-install,pre-upgrade
helm.sh/hook-weight: "-5"
helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
```

The ConfigMap should persist (only the Job is deleted after success).

### Agent Pods CrashLoopBackOff

```bash
# Check pod logs
kubectl logs -n suse-observability <pod-name>

# Check pod events
kubectl describe pod -n suse-observability <pod-name>
```

Common issues:

**1. Invalid Observability URL**

**Error in logs**: `Failed to connect to https://placeholder.example.com`

**Root Cause**: External secret mode is enabled but ConfigMap contains placeholder URL.

**Resolution**:

1. Verify ConfigMap has real URL:
   ```bash
   kubectl get configmap -n suse-observability <release-name>-url-configmap -o yaml
   ```

2. If placeholder, verify external secret exists and hook job ran:
   ```bash
   kubectl get secret -n suse-observability <cluster-name>-observability
   kubectl logs -n suse-observability job/<release-name>-url-configmap-creator
   ```

**2. Authentication Failed**

**Error in logs**: `401 Unauthorized` or `Invalid API key`

**Root Cause**: API token in external secret is invalid or expired.

**Resolution**:

1. Verify token in secret:
   ```bash
   kubectl get secret -n suse-observability <cluster-name>-observability \
     -o jsonpath='{.data.token}' | base64 -d
   ```

2. Update secret with valid token:
   ```bash
   kubectl delete secret -n suse-observability <cluster-name>-observability
   kubectl create secret generic <cluster-name>-observability \
     -n suse-observability \
     --from-literal=endpoint='https://observability.example.com' \
     --from-literal=token='<new-valid-token>'
   ```

3. Restart agent pods (ConfigMap will be updated on next restart):
   ```bash
   kubectl rollout restart daemonset -n suse-observability
   kubectl rollout restart deployment -n suse-observability
   ```

**3. Resource Limits**

**Error in events**: `OOMKilled` or pod evicted

**Root Cause**: Agent pods exceed memory limits.

**Resolution**:

Increase resource limits in `fleet.yaml`:

```yaml
helm:
  values:
    nodeAgent:
      containers:
        agent:
          resources:
            limits:
              memory: "600Mi"  # Increase from default 420Mi
```

## Configuration

### Resource Limits

Default resource limits are configured for typical workloads. Adjust based on cluster size and monitoring requirements:

```yaml
helm:
  values:
    # Node agent (runs on every node)
    nodeAgent:
      containers:
        agent:
          resources:
            limits:
              cpu: "270m"
              memory: "420Mi"
            requests:
              cpu: "20m"
              memory: "180Mi"

    # Cluster agent (cluster-wide monitoring)
    clusterAgent:
      resources:
        limits:
          cpu: "400m"
          memory: "800Mi"
        requests:
          cpu: "70m"
          memory: "512Mi"

    # Logs agent (log collection)
    logsAgent:
      enabled: true
      resources:
        limits:
          cpu: "1300m"
          memory: "192Mi"

    # Checks agent (cluster checks)
    checksAgent:
      enabled: true
      resources:
        limits:
          cpu: "400m"
          memory: "600Mi"
```

**Recommendations**:
- **Small clusters** (< 50 nodes): Use default values
- **Medium clusters** (50-200 nodes): Increase memory by 50%
- **Large clusters** (> 200 nodes): Increase memory by 100%, add CPU

### Disabling Agents

Disable specific agents to reduce resource usage:

```yaml
helm:
  values:
    logsAgent:
      enabled: false  # Disable log collection

    checksAgent:
      enabled: false  # Disable cluster checks
```

**Note**: Node agent and cluster agent are required and cannot be disabled.

### Custom Secret Name Template

To use a different secret naming convention:

```yaml
helm:
  values:
    stackstate:
      observabilitySecret:
        nameTemplate: "{{ .Values.stackstate.cluster.name }}-stackstate-credentials"
        # Secret will be <cluster-name>-stackstate-credentials
```

### Cross-Namespace Secrets

By default, the external secret is read from the same namespace as the release (`suse-observability`). To read from a different namespace:

```yaml
helm:
  values:
    stackstate:
      observabilitySecret:
        enabled: true
        namespace: "default"  # Read secret from default namespace
        nameTemplate: "{{ .Values.stackstate.cluster.name }}-observability"
```

**Note**: When reading from a different namespace, the hook creates a ClusterRole/ClusterRoleBinding instead of Role/RoleBinding.

## References

- [SUSE Observability Documentation](https://docs.suse.com/suse-observability/)
- [StackState Agent Documentation](https://docs.stackstate.com/setup/agent/about-stackstate-agent)
- [Fleet Bundle Documentation](https://fleet.rancher.io/ref-bundle)
- [Helm Hooks Documentation](https://helm.sh/docs/topics/charts_hooks/)
