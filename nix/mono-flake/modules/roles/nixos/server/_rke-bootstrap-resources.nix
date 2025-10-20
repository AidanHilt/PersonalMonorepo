{ inputs, globals, pkgs, machine-config, lib, ...}:

let 
  argocdManifest = pkgs.writeText "argocd-helm.yaml" ''
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: argocd
  namespace: kube-system
spec:
  repo: https://argoproj.github.io/argo-helm
  chart: argo-cd
  version: "8.2.2"
  targetNamespace: argocd
  createNamespace: true
  
  # Helm values to customize the installation
  valuesContent: |-
    extraObjects:
      - apiVersion: v1
        kind: Secret
        metadata:
          labels:
            argocd.argoproj.io/secret-type: repository
          name: truecharts
          namespace: argocd
        stringData:
          url: tccr.io/truecharts
          name: truecharts
          type: helm
          enableOCI: "true"

      - apiVersion: v1
        kind: ConfigMap
        metadata:
          name: cmp-plugin
        data:
          plugin.yaml: |
            apiVersion: argoproj.io/v1alpha1
            kind: ConfigManagementPlugin
            metadata:
              name: argocd-vault-plugin-helm
            spec:
              allowConcurrency: true
              init:
                command:
                  - bash
                  - "-c"
                  - |
                    helm dependency build
              lockRepo: false
              generate:
                command:
                  - bash
                  - "-c"
                  - |
                    helm template $ARGOCD_ENV_APP_NAME -n $ARGOCD_APP_NAMESPACE -f <(echo "$ARGOCD_ENV_HELM_VALUES") . | argocd-vault-plugin generate -s argocd:argocd-vault-plugin-credentials -

    repoServer:
      env:
        - name: ARGOCD_EXEC_TIMEOUT
          value: "600"

      rbac:
        - apiGroups:
            - ""
          resources:
            - secrets
          verbs:
            - get
            - list
            - watch

      extraContainers:
        - name: avp-helm
          command: [/var/run/argocd/argocd-cmp-server]
          image: aidanhilt/atils-avp:latest
          imagePullPolicy: Always
          securityContext:
            runAsNonRoot: true
            runAsUser: 999
          env:
            - name: HELM_CONFIG_HOME
              value: /home/argocd/helm-working-dir
            - name: HELM_CACHE_HOME
              value: /home/argocd/helm-working-dir
            - name: HELM_DATA_HOME
              value: /home/argocd/helm-working-dir
          volumeMounts:
            - mountPath: /var/run/argocd
              name: var-files
            - mountPath: /home/argocd/cmp-server/plugins
              name: plugins
            - mountPath: /tmp
              name: tmp-dir
            - mountPath: /home/argocd/cmp-server/config/plugin.yaml
              name: cmp-plugin
              subPath: plugin.yaml

      volumes:
        - configMap:
            name: cmp-plugin
          name: cmp-plugin
        - name: tmp-dir
          emptyDir: {}

    configs:
      params:
        server.disable.auth: "true"
        server.basehref: "/argocd"
        server.rootpath: "/argocd"
        server.insecure: true

    applicationSet:
      enabled: false

    dex:
      enabled: false

    notifications:
      enabled: false

    server:
      initContainers:
        - name: wait-for-repo-server
          image: busybox:1.35
          command:
            - sh
            - -c
            - |
              until nc -z argocd-repo-server 8081; do
                echo "Waiting for argocd-repo-server..."
                sleep 2
              done
              echo "argocd-repo-server is ready"
  '';

  applicationManifest = pkgs.writeText "master-stack.yaml" ''
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: master-stack
  namespace: argocd
spec:
  project: default
  sources:
    - repoURL: https://github.com/AidanHilt/PersonalMonorepo
      path: kubernetes/helm-charts/k8s-resources/master-stack-new
      targetRevision: ${globals.personalMonorepoBranch}
      helm:
        valueFiles:
          - "$values/kubernetes/argocd/configuration-data/${machine-config.k8s.clusterName}/master-stack.yaml"
    - repoURL: ${globals.personalMonorepoURL}
      targetRevision: ${globals.personalMonorepoBranch}
      ref: values
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - Retry=true
    retry:
      limit: -1 # Maximum number of retries
      backoff:
        duration: 30s # Initial retry interval
        factor: 2 # Multiplication factor for the backoff
        maxDuration: 30m # Maximum retry interval
  '';

  manifestPath = "/var/lib/rancher/rke2/server/manifests";
in

{
 systemd.tmpfiles.rules = [
  "C ${manifestPath}/argocd-helm.yaml 600 - - - ${argocdManifest}"
  "C ${manifestPath}/master-stack.yaml 600 - - - ${applicationManifest}"
 ]; 
}