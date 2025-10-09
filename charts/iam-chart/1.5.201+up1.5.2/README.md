# ACK IAM Controller

AWS Controllers for Kubernetes (ACK) IAM Controller enables declarative management of AWS IAM resources from Kubernetes.

## Introduction

This chart deploys the ACK IAM Controller on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager. The controller allows you to create and manage IAM roles, policies, users, groups, and OIDC providers using Kubernetes custom resources, enabling infrastructure-as-code workflows for IAM.

## Features

- Declarative IAM role and policy management via Kubernetes CRDs
- Automatic pod identity association for AWS API authentication
- Cross-account resource management (CARM) support
- Integration with Fleet GitOps for multi-cluster deployments
- Resource adoption for importing existing IAM resources

## Prerequisites

- EKS Pod Identity Agent deployed in the cluster
- ACK EKS Controller deployed (for pod identity association reconciliation)
- IAM role created with IAM permissions (via CloudFormation template)
- AWS account ID and cluster name configured as Fleet cluster labels

## Installation Notes

This chart uses the `ack-pod-identity-association` subchart to declaratively create pod identity associations via Helm hooks. The pod identity association is created before the controller starts, ensuring zero authentication failures. The controller requires elevated IAM permissions to manage IAM resources across AWS accounts.

## Additional Resources

- [ACK IAM Controller Documentation](https://aws-controllers-k8s.github.io/community/docs/community/services/iam/)
- [Fleet GitOps Documentation](https://fleet.rancher.io/)
- [EKS Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
