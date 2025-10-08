# Package Management with charts-build-scripts

This directory contains Helm chart packages managed using Rancher's charts-build-scripts tool. The workflow enables forking upstream charts, applying patches, and adding dependencies while maintaining a clean separation between upstream and local modifications.

## Key Concepts

**Package Types:**
- **Upstream OCI**: Charts from OCI registries (e.g., `oci://public.ecr.aws/aws-controllers-k8s/eks-chart:1.9.3`)
- **Upstream Git**: Charts from Git repositories with specific commit hashes
- **Local**: Custom charts developed locally (e.g., `ack-eks-bootstrap`, `ack-pod-identity-association`)

**Directory Structure:**
```
packages/<package-name>/
├── package.yaml              # Package definition (upstream source, versioning)
├── generated-changes/        # Tracked modifications (committed to Git)
│   ├── patch/               # Patches applied to upstream charts
│   ├── dependencies/        # Subchart dependencies
│   │   └── <dep-name>/
│   │       └── dependency.yaml
│   └── overlay/             # File replacements (if needed)
└── charts/                  # Working directory (temporary, Git-ignored)
```

**Workflow:** The tool fetches upstream charts, applies patches, injects dependencies, and builds final charts to `charts/<package-name>/` for deployment.

## Common Commands

**Note:** macOS users must use GNU patch from Homebrew:
```bash
PATH="/opt/homebrew/bin:$PATH" PACKAGE=<name> ./bin/charts-build-scripts <command>
```

### Basic Operations

```bash
# Prepare: Fetch upstream chart and apply patches to working directory
PACKAGE=ack-eks-controller ./bin/charts-build-scripts prepare

# Patch: Generate patches from your modifications in working directory
PACKAGE=ack-eks-controller ./bin/charts-build-scripts patch

# Clean: Remove working directory (charts/)
PACKAGE=ack-eks-controller ./bin/charts-build-scripts clean

# Charts: Build final packaged chart (does prepare + package)
PATH="/opt/homebrew/bin:$PATH" PACKAGE=ack-eks-controller ./bin/charts-build-scripts charts
```

## Adding a New Package

### Option 1: Upstream OCI Chart

Create a new package from an OCI registry:

```bash
# 1. Create package directory and definition
mkdir -p packages/ack-s3-controller

cat > packages/ack-s3-controller/package.yaml << 'INNER_EOF'
url: oci://public.ecr.aws/aws-controllers-k8s/s3-chart:1.0.0
packageVersion: 1
INNER_EOF

# 2. Build the chart
PATH="/opt/homebrew/bin:$PATH" PACKAGE=ack-s3-controller ./bin/charts-build-scripts charts
```

The final chart will be in `charts/ack-s3-controller/`.

### Option 2: Upstream Git Chart

Create a package from a Git repository:

```bash
# 1. Create package directory and definition
mkdir -p packages/my-chart

cat > packages/my-chart/package.yaml << 'INNER_EOF'
url: https://github.com/example/helm-charts.git
subdirectory: charts/my-chart
commit: abc123def456  # Specific commit hash
packageVersion: 1
INNER_EOF

# 2. Build the chart
PATH="/opt/homebrew/bin:$PATH" PACKAGE=my-chart ./bin/charts-build-scripts charts
```

### Option 3: Local Chart

Create a custom local chart:

```bash
# 1. Create package directory and definition
mkdir -p packages/my-local-chart

cat > packages/my-local-chart/package.yaml << 'INNER_EOF'
url: local
version: 1.0.0
doNotRelease: true
INNER_EOF

# 2. Create chart structure
mkdir -p packages/my-local-chart/charts/my-local-chart
# Add Chart.yaml, values.yaml, templates/, etc.

# 3. Build the chart
PATH="/opt/homebrew/bin:$PATH" PACKAGE=my-local-chart ./bin/charts-build-scripts charts
```

## Modifying Upstream Charts

To customize an upstream chart:

```bash
# 1. Prepare working directory
PACKAGE=ack-eks-controller ./bin/charts-build-scripts prepare

# 2. Edit files in packages/ack-eks-controller/charts/
# Example: Add values to values.yaml
vi packages/ack-eks-controller/charts/values.yaml

# 3. Generate patches from your changes
PACKAGE=ack-eks-controller ./bin/charts-build-scripts patch

# 4. Review generated patch
cat packages/ack-eks-controller/generated-changes/patch/values.yaml.patch

# 5. Clean working directory
PACKAGE=ack-eks-controller ./bin/charts-build-scripts clean

# 6. Build final chart with patches applied
PATH="/opt/homebrew/bin:$PATH" PACKAGE=ack-eks-controller ./bin/charts-build-scripts charts
```

The patch will be automatically applied in future builds.

## Adding Dependencies

Dependencies are subcharts bundled with the main chart. This repository uses local chart dependencies for reusable components.

### Add a Local Chart Dependency

```bash
# 1. Create dependency directory
mkdir -p packages/ack-iam-controller/generated-changes/dependencies/ack-pod-identity-association

# 2. Create dependency definition
cat > packages/ack-iam-controller/generated-changes/dependencies/ack-pod-identity-association/dependency.yaml << 'INNER_EOF'
# Reference the local pod identity association package
url: packages/ack-pod-identity-association
INNER_EOF

# 3. Rebuild chart (automatically includes dependency)
PATH="/opt/homebrew/bin:$PATH" PACKAGE=ack-iam-controller ./bin/charts-build-scripts charts
```

The dependency chart will be included in `charts/ack-iam-controller/charts/ack-pod-identity-association/`.

### Configure Dependency Values

In your Fleet bundle or values file, configure the subchart using its name as the key:

```yaml
# Main chart values
aws:
  region: us-west-2

# Subchart values (uses dependency name as key)
ack-pod-identity-association:
  podIdentity:
    enabled: true
    clusterName: my-cluster
    awsAccountId: "123456789012"
```

## Updating to New Upstream Versions

To update a package to a newer upstream version:

```bash
# 1. Edit package.yaml to update version/commit
vi packages/ack-eks-controller/package.yaml
# For OCI: Change url to new version
# For Git: Update commit hash

# 2. Increment packageVersion (or reset to 1 for major upstream changes)
# packageVersion: 2

# 3. Rebuild chart (patches will be reapplied)
PATH="/opt/homebrew/bin:$PATH" PACKAGE=ack-eks-controller ./bin/charts-build-scripts charts

# 4. Test the updated chart
# If patches fail to apply, you may need to regenerate them
```

## Package Versioning

Chart versions are generated automatically:

- **Upstream packages**: `<upstream-version>+up<packageVersion>` (e.g., `1.9.3+up1`)
- **Local packages**: Uses the `version` field from package.yaml

Increment `packageVersion` when:
- You modify patches or dependencies
- You make changes to an already-released chart
- Reset to 1 when updating to a new upstream major/minor version

## Examples from This Repository

**ack-eks-controller**: Upstream OCI chart with patches and local dependency
```yaml
url: oci://public.ecr.aws/aws-controllers-k8s/eks-chart:1.9.3
packageVersion: 1
# Has: patches, ack-eks-bootstrap dependency
```

**ack-iam-controller**: Upstream OCI chart with local dependency
```yaml
url: oci://public.ecr.aws/aws-controllers-k8s/iam-chart:1.5.2
packageVersion: 1
# Has: ack-pod-identity-association dependency
```

**eks-pod-identity-agent**: Upstream Git chart
```yaml
url: https://github.com/aws/eks-pod-identity-agent.git
subdirectory: charts/eks-pod-identity-agent
commit: 6eaa5e9aefc9a34c9605ff358e0e0f93860a918f
packageVersion: 1
```

**ack-pod-identity-association**: Local reusable chart
```yaml
url: local
version: 1.0.0
doNotRelease: true
```

## Troubleshooting

**"Working directory not prepared"**: Run `PACKAGE=<name> ./bin/charts-build-scripts prepare` first

**Patches fail to apply**: Upstream chart may have changed significantly. Regenerate patches:
1. Delete old patches in `generated-changes/patch/`
2. Run `prepare`, make your changes, run `patch` again

**macOS "patch: command not found"**: Install GNU patch via Homebrew and use `PATH="/opt/homebrew/bin:$PATH"` prefix

**Dependency not found**: Ensure the dependency package exists and `dependency.yaml` has correct path

## Next Steps

After building a package:
1. Charts are generated in `charts/<package-name>/`
2. Create a Fleet bundle in `blueprints/<package-name>/fleet.yaml` to deploy via GitOps
3. Configure values in the Fleet bundle, including subchart values for dependencies
4. Commit `package.yaml`, `generated-changes/`, and built charts to Git
