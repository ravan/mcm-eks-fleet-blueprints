# ACK EKS Controller

AWS Controllers for Kubernetes (ACK) EKS Controller enables declarative management of Amazon EKS resources from Kubernetes.

## Introduction

This chart deploys the ACK EKS Controller on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager. The controller allows you to create and manage EKS clusters, node groups, Fargate profiles, and pod identity associations using Kubernetes custom resources, enabling infrastructure-as-code workflows for EKS.

## Features

- Declarative management of EKS clusters and node groups
- Pod identity association creation and management
- EKS add-on lifecycle management
- Cross-account resource management (CARM) support
- Integration with Fleet GitOps for multi-cluster deployments

## Prerequisites

- EKS Pod Identity Agent deployed in the cluster
- IAM role created with EKS permissions (via CloudFormation template)
- Bootstrap pod identity association for the controller service account
- AWS account ID and cluster name configured as Fleet cluster labels

## Installation Notes

This chart includes a bootstrap subchart that creates the initial pod identity association for the controller. Ensure the `fleet-bootstrap` service account has pod identity configured before deploying. The controller requires elevated IAM permissions to manage EKS resources across clusters.

## Additional Resources

- [ACK EKS Controller Documentation](https://aws-controllers-k8s.github.io/community/docs/community/services/eks/)
- [Fleet GitOps Documentation](https://fleet.rancher.io/)
- [EKS Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
