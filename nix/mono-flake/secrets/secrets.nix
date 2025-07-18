let
  # Machines that we use for development and management. Needs access to all files
  # ==============================================================================

  # Personal laptop
  hyperion-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion";
  hyperion-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILIl+K6+k3TmEzx3N1Wjh8ILoGU2X9MAmr/EkgTOPFLO root@hyperion";

  # WSL keys
  wsl-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEAi2UjaWUsDVY6wUMMcIjDXzyizhax86Z0J2I6fYM0 nixos@nixos";
  wsl-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICbW6OhxPYPuJTZAgbpL3+PwHPNvdL2dw8+KqA1QeF47 root@nixos";

  # Desktop VMs
  vm-desktop-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFfl8/kJbF4ntoSOq+sHgLPfZI18K6HS2p9iUFzPEtNn noname";

  # Real-life desktop machines
  big-boi-desktop-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAdaXVorsOMM9qbJnrU5lP6jCUKarqVef4M39GDANYGk noname";

  user-machines = [hyperion-user hyperion-system wsl-user wsl-system vm-desktop-system  big-boi-desktop-system];

  # Our various server clusters
  # ===========================

  # A small test cluster we run on NixOS machines running as VMs on our laptop
  laptop-cluster-1-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFIeYzag+0puS2/iB/Dfgj4CFiJFopSet0NgmQGf8nEe noname";
  laptop-cluster-2-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBYPCI2abzSHOfnDK8aZnEGG7v1Kt2xu8rpeW00RpdJl noname";

  laptop-cluster-machines = [laptop-cluster-1-system laptop-cluster-2-system];

  # Our main staging cluster, in the form of NixOS machines running on x86 hardware
  staging-cluster-1-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImXssIeNM0HqEu8ZKnpaweicauH4bYNrkwpIX/Hjcwh root@staging-cluster-1";
  staging-cluster-2-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOYRGHzNc7rYSsxveCvZAicjiPT3NHdOkXmmlH3g7Y/m root@staging-cluster-2";
  staging-cluster-3-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGoMCDJlMcyrK65E269A1cwJqO9kLMc/uVu7VfK7LcZN root@staging-cluster-3";

  staging-cluster-machines = [staging-cluster-1-system staging-cluster-2-system staging-cluster-3-system];
in
{
  "hosts.age".publicKeys = user-machines ++ laptop-cluster-machines;

  "smb-mount-config.age".publicKeys = user-machines;
  "rclone-config.age".publicKeys = user-machines;
  "kubeconfig.age".publicKeys = user-machines;

  "adguardhome.age".publicKeys = user-machines ++ laptop-cluster-machines;

  "rke-config-laptop-cluster.age".publicKeys = user-machines ++ laptop-cluster-machines;
}
