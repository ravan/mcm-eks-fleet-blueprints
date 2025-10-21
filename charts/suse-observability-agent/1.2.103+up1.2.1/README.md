# SUSE Observability Agent

The SUSE Observability Agent (powered by StackState) provides comprehensive monitoring for Kubernetes clusters, collecting metrics, traces, logs, and topology data for multi-cluster observability.

## Introduction

This chart deploys the SUSE Observability Agent on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager. The agent includes node agents (DaemonSet), cluster agent, logs agent, and checks agent to provide complete visibility into cluster health, resource usage, and application performance.

## Features

- Multi-agent architecture for comprehensive observability (metrics, traces, logs, topology)
- External secret integration (reads endpoint and API token from Kubernetes secrets)
- Automatic ConfigMap creation via Helm hooks (no manual configuration needed)
- Support for multiple agent types (node, cluster, logs, checks)
- Resource-efficient defaults with customizable limits
- Cross-namespace secret support

## Prerequisites

- Kubernetes cluster (EKS recommended for this deployment)
- External Kubernetes secret with observability endpoint and API token
- Secret format: `<cluster-name>-observability` with keys `endpoint` and `token`
- RBAC permissions for reading secrets and creating ConfigMaps

## Installation Notes

This chart uses **external secret mode**: instead of storing the observability URL and API key in values.yaml, it reads them from an external Kubernetes secret created by Rancher or a secret management system. A pre-install Helm hook (weight -5) creates a ConfigMap by reading the external secret. Agent pods mount this ConfigMap and the external secret for authentication. This approach enables secret rotation without Helm upgrades.

## Additional Resources

- [SUSE Observability Documentation](https://docs.suse.com/suse-observability/)
- [StackState Agent Documentation](https://docs.stackstate.com/setup/agent/about-stackstate-agent)
- [Fleet GitOps Documentation](https://fleet.rancher.io/)
