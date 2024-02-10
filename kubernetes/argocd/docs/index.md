# ArgoCD Configuration
This section is where we manage ArgoCD, both the applications installed and the actual configuration of ArgoCD itself.

1. App-of-apps Helm Chart: Our app of apps is a configurable Helm chart, with each template representing a possible application (including values). Each item can be individually turned on or off, but there is currently no option to change their configuration.
2. Setup Directory: This contains roles needed to interface with Vault, which may change depending on how exactly we do the interface between ArgoCD and vault
3. values.yaml: Contains the configuration for ArgoCD. This enables a plugin to let ArgoCD pull values directly from Vault. This may be dropped, in which case a lot of this will go away.