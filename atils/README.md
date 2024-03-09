# Atils
Atils is a set of python scripts that make it easier to work with this monorepo. It's kind of a grab bag.

## Subcommands and What They Do
`argocd`: Manages and installs argocd, using the master-stack application located in the templates folder
`build`: A wrapper around whatever build tools are needed for a project. Configured using a special `.atils_buildconfig.json` file
`helm`: Tools for managing helm, at this point just includes our auto-deploy script for development
`jobs`: Tools for managingl, running, and templating Kubernetes jobs. That's also where we threw a special job for managing a PVC
`vault`: In the future, will have tools for updating and placing secrets from a local directory into Hashi Vault. Or maybe we'll just use Terraform, that's probably easier

## Configuration and Installation
So... this isn't great right now. Atils relies on certain configurations, and it doesn't have a good way to set defaults right now. I've included an example for some basic default configs, but in the future we'll want to add some kind of install script or setup helper. This can go anywhere, I put it in my `.zshenv` so it applies on every login:

```
export ATILS_INSTALL_DIR="@jinja {{env.HOME}}/PersonalMonorepo"
export ATILS_KUBECONFIG_LOCATION="@jinja {{env.HOME}}/.kube/"
export ATILS_SCRIPT_INSTALL_DIRECTORY="@jinja {{this.INSTALL_DIR}}/atils"
export ATILS_HELM_CHARTS_DIR=kubernetes/helm-charts
export ATILS_LOG_LEVEL=INFO
export ATILS_JOBS_DIR=kubernetes/jobs
export ATILS_ARGOCD_URL=http://localhost/argocd
export ATILS_ARGOCD_USERNAME=""
export ATILS_ARGOCD_PASSWORD=""
export ATILS_CONFIG_DIRECTORY=/Users/ahilt/.atils
```