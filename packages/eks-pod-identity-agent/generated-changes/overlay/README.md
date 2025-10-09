# EKS Pod Identity Agent

The EKS Pod Identity Agent enables Amazon EKS pods to use IAM roles for authentication to AWS services.

## Introduction

This chart deploys the EKS Pod Identity Agent on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager as a DaemonSet. The agent runs on every node and provides seamless AWS credential management for pods using EKS Pod Identity, eliminating the need for IRSA (IAM Roles for Service Accounts) and OIDC providers.

## Features

- DaemonSet deployment on all cluster nodes
- Multiple node type support (cloud, hybrid, Bottlerocket)
- System-level critical priority for high availability
- Zero-downtime credential rotation
- Integration with Fleet GitOps for multi-cluster deployments

## Prerequisites

- Amazon EKS cluster (version 1.24 or higher)
- AWS region configuration for container image pulling
- Appropriate cluster node types (cloud, hybrid, or Bottlerocket)

## Installation Notes

This chart supports three DaemonSet modes: cloud (standard AWS nodes), hybrid (on-premises nodes), and hybrid-bottlerocket (Bottlerocket hybrid nodes). Only enable the mode that matches your cluster's node types. The agent uses `system-node-critical` priority class and tolerates all taints for cluster-wide deployment.

## Additional Resources

- [EKS Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [Pod Identity Agent GitHub Repository](https://github.com/aws/eks-pod-identity-agent)
- [Fleet GitOps Documentation](https://fleet.rancher.io/)
