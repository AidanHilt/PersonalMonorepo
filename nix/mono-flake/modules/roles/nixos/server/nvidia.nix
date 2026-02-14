{ inputs, globals, pkgs, machine-config, lib, ...}:

{
  virtualisation.containerd = {
    settings = {
      plugins = {
        "io.containerd.grpc.v1.cri" = {
          enable_cdi = true;
          cdi_spec_dirs = ["/etc/cdi" "/var/run/cdi"];
          containerd = {
            default_runtime_name = "nvidia";
            runtimes = {
              nvidia = {
                privileged_without_host_devices = false;
                runtime_type = "io.containerd.runc.v2";
                options = {
                  BinaryName = "${pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime";
                };
              };
            };
          };
        };
      };
    };
  };

}