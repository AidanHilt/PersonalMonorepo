# Atils
Atils is a set of python scripts that make it easier to work with this monorepo. It's kind of a grab bag.

## Subcommands and What They Do
`argocd`: Manages and installs argocd, using the master-stack application located in the templates folder
`build`: A wrapper around whatever build tools are needed for a project. Configured using a special `.atils_buildconfig.json` file
`helm`: Tools for managing helm, at this point just includes our auto-deploy script for development
`jobs`: Tools for managingl, running, and templating Kubernetes jobs. That's also where we threw a special job for managing a PVC
`vault`: In the future, will have tools for updating and placing secrets from a local directory into Hashi Vault