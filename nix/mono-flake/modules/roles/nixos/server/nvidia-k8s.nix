{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  hardware.nvidia-container-toolkit = {
    enable = true;
    mount-nvidia-executables = true;
  };

  services.rke2 = {
    extraFlags = [
      "--default-runtime=nvidia"
      "--container-runtime-endpoint=unix:///run/containerd/containerd.sock"
    ];
  };

  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins = {
        "io.containerd.grpc.v1.cri" = {
          cni = lib.mkForce {
            bin_dirs = ["/opt/cni/bin" "${pkgs.cni-plugins}/bin"];
            conf_dir = "/etc/cni/net.d";
          };
          containerd = {
            snapshotter = "overlayfs";
            runtimes = {
              nvidia = {
                runtime_type = "io.containerd.runc.v2";
                options = {
                  BinaryName = lib.mkForce "${pkgs.nvidia-container-toolkit.tools}/bin/nvidia-container-runtime.cdi";
                };
              };
            };
          };
        };
      };
    };
  };
}