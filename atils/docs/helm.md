# Helm
Contains utilities for building and interacting with Helm charts

## auto-deploy
Installs a Helm chart located in the HELM_CHART_DIR directory, and then watches for changes, either in the Helm chart itself, or in a values file located at `~/.atils/helm-values/<chart-name>.yaml`. Upon detecting a change, it updates the installed Helm chart to account for the change. Upon exiting with Ctrl+C, uninstalls the Helm chart.

### arguments
--chartname CHART_NAME, -cn CHART_NAME: The name of the Helm chart to watch. Must be located in HELM_CHART_DIR