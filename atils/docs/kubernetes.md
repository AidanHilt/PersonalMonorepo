# Kubernetes
Contains utilities for running and manaing Kubernetes

## rke-setup
DEPRECATED. Will be replaced with a system-agnostic setup, for our different methods

## secrets
Commands for interacting with Kubernetes secrets

### decode
Decodes and pretty prints all the keys in a given secret

#### Arguments
secret_name: The name of the secret to operate on
--namespace NAMESPACE, -n NAMESPACE: The namespace of the secret to operate on. Defaults to the current namespace