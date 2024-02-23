# argocd
Commands to interact with ArgoCD. A description is found below:

## install
Install ArgoCD, waits for all the pods to come up, installs the master-stack chart, then waits for all the
sub-applications to come up

### Arguments
environment: {dev-laptop,dev-cluster,prod-cluster} The name of the cluster we're installing ArgoCD to. This matters, as we disable
certain applications in different environments, and have environment-dependent syncing

## port-forward
Opens up a port forward to the ArgoCD server, and open a browser window to that server

### Arguments
None

## get-password
DEPRECATED

## disable
Disables and deletes an application in the master stack

### Arguments
application: The name of the application to disable

## enable
Enables and syncs an application in the master stack

### Argument
application: The name of the application to enable