let
  # Personal laptop
  hyperion-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion";
  hyperion-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILIl+K6+k3TmEzx3N1Wjh8ILoGU2X9MAmr/EkgTOPFLO root@hyperion";

  # WSL keys
  wsl-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEAi2UjaWUsDVY6wUMMcIjDXzyizhax86Z0J2I6fYM0 nixos@nixos";
  wsl-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICbW6OhxPYPuJTZAgbpL3+PwHPNvdL2dw8+KqA1QeF47 root@nixos";

  # Mac cluster configuration
  laptop-vm-cluster-1-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC9Rdp+DdyYnl0+ZrVaCvWU/AG8pi6V6beuJPNd/CyoD root@nixos";
  laptop-vm-cluster-2-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPzvjKclx6MNXzTqy3sFfZgSt7hN0u7VEnxi3oS8M/Ai root@nixos";
in
{
  "smb-mount-config.age".publicKeys = [ hyperion-user hyperion-system wsl-user wsl-system ];
  "rclone-config.age".publicKeys = [ hyperion-user hyperion-system wsl-user wsl-system ];
  "kubeconfig.age".publicKeys = [ hyperion-user hyperion-system wsl-user wsl-system ];
  "adguardhome.age".publicKeys = [ hyperion-user laptop-vm-cluster-1-system laptop-vm-cluster-2-system ];
  "rke-token-mac-cluster.age".publicKeys = [ hyperion-user laptop-vm-cluster-1-system laptop-vm-cluster-2-system ];
  "hosts.age".publicKeys = [ hyperion-user hyperion-system wsl-user wsl-system laptop-vm-cluster-1-system laptop-vm-cluster-1-system ];
}
