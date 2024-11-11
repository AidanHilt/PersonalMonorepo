{ inputs, pkgs, globals, ... }:

let
  gen3-cluster-setup = pkgs.writeShellScriptBin "gen3-cluster-setup" ''
  cat <<EOF | kind create cluster --config=-
  kind: Cluster
  apiVersion: kind.x-k8s.io/v1alpha4
  nodes:
  - role: control-plane
    kubeadmConfigPatches:
    - |
      kind: InitConfiguration
      nodeRegistration:
        kubeletExtraArgs:
          node-labels: "ingress-ready=true"
    extraPortMappings:
    - containerPort: 80
      hostPort: 80
      protocol: TCP
    - containerPort: 443
      hostPort: 443
      protocol: TCP
  EOF
  '';

  gen3-cluster-teardown = pkgs.writeShellScriptBin "gen3-cluster-teardown" ''
  kind delete cluster
  '';

  gen3-helm-install = pkgs.writeShellScriptBin "gen3-helm-install" ''
  cd ~/Gen3Repos/gen3-helm/helm/gen3 && helm dependency update && helm dependency build
  helm upgrade --install gen3 ~/Gen3Repos/gen3-helm/helm/gen3
  '';
in

{
  environment.systemPackages = [
    pkgs.colima
    pkgs.docker
    pkgs.docker-buildx
    gen3-cluster-setup
    gen3-cluster-teardown
    gen3-helm-install
  ];

  # Launch Colima on startup, so we always have docker working
  launchd.user.agents.colima-autostart = {
    path = [ "/bin" "/usr/bin" "/nix/var/nix/profiles/default/bin" ];

    serviceConfig = {
      Label = "com.user.colima-autostart";
      ProgramArguments = [ "colima" "start" ];
      RunAtLoad = true;
      KeepAlive = false;
      StandardOutPath = "/tmp/colima-autostart.log";
      StandardErrorPath = "/tmp/colima-autostart.error.log";
    };
  };
}