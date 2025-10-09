# AWS EBS CSI Driver

The AWS EBS CSI Driver enables dynamic provisioning of Amazon EBS volumes for Kubernetes persistent storage.

## Introduction

This chart deploys the AWS EBS CSI Driver on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager. The driver allows Kubernetes to dynamically provision, attach, and manage Amazon EBS volumes for persistent workloads, with support for encryption, volume types (gp3, gp2, io1, io2), and pod identity authentication.

## Features

- Dynamic EBS volume provisioning via StorageClasses
- Support for multiple volume types (gp3, gp2, io1, io2, sc1, st1)
- Volume encryption with AWS KMS
- Pod identity authentication (no IRSA required)
- Zero authentication failures via Helm hook ordering

## Prerequisites

- EKS Pod Identity Agent deployed in the cluster
- ACK EKS Controller deployed (for pod identity association management)
- ACK IAM Controller deployed (for IAM role creation)
- AWS account ID and cluster name configured as Fleet cluster labels
- IAM permissions for EBS volume operations

## Installation Notes

This chart uses two subcharts: `ack-iam-role-association` (creates IAM role with EBS permissions) and `ack-pod-identity-association` (links service account to IAM role). Helm hooks ensure proper sequencing: IAM role creation (weight -10) → pod identity association (weight -5) → driver deployment (weight 0), guaranteeing zero authentication failures on startup.

## Additional Resources

- [AWS EBS CSI Driver Documentation](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [EKS Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [Fleet GitOps Documentation](https://fleet.rancher.io/)
