# MVP Documentation

## Overview
This document describes the Minimum Viable Product (MVP) implementation and testing procedures for our application deployment using GitOps principles with ArgoCD.

## Testing Procedures

### 1. GitOps ArgoCD Application Demo
The following demonstration shows the automatic update process through GitOps using ArgoCD for the demoapp application.

![ArgoCD Demo](../.data/argocd.gif)

The demo showcases:
- Initial deployment of the application
- Automatic synchronization of changes
- Deployment history tracking

### 2. Application Demo
The following demonstration shows the actual application in action, highlighting its core features and functionality.

![Application Demo](../.data/app_demo.gif)

The demo showcases:
- Core application features

## Implementation Details
The implementation follows GitOps principles using ArgoCD for continuous deployment. The configuration is managed through Kubernetes manifests and ArgoCD Application resources, ensuring consistent and reproducible deployments.
