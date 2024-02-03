# Utility Scripts

These are random, little helpful scripts. In the future, there should be some common interface to list, manage, and run these.

1. `add-conditions-to-application.sh`: This is for working on the ArgoCD app Helm chart. After you have written a template, if you forgot to wrap it in a conditional block of the form `template-name.enabled`, this can do that automatically
2. `clear-namespace.sh`: This completely purges a namespace, by getting all of the api resource types that can be deleted, and then deleting them. Hope you know what you're doing!
3. `flag-applications.sh`: This is for working on the ArgoCD app Helm chart. After you have written a template, if you forgot to put the conditional `template-name.enabled` in `values.yaml`, this script can do that for you.