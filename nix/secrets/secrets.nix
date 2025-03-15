let
  # Personal laptop
  hyperion-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion";
  hyperion-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILIl+K6+k3TmEzx3N1Wjh8ILoGU2X9MAmr/EkgTOPFLO root@hyperion";

  # WSL keys
  wsl-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEAi2UjaWUsDVY6wUMMcIjDXzyizhax86Z0J2I6fYM0 nixos@nixos";
  wsl-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICbW6OhxPYPuJTZAgbpL3+PwHPNvdL2dw8+KqA1QeF47 root@nixos";

  user-machines = [hyperion-user hyperion-system wsl-user wsl-system];

  # Mac cluster configuration
  laptop-vm-cluster-1-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAZUDDd40ePKePHdJS+ZJrb/ul36ZU5yTAQkx2Th26jw root@nixos";
  laptop-vm-cluster-2-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ9KkI49t4alr1XEx2en2IUmiAJT8HqbcCppP1v58I+e root@nixos";

  mac-cluster-machines = [laptop-vm-cluster-1-system laptop-vm-cluster-2-system];
in
{
  "smb-mount-config.age".publicKeys = user-machines;
  "rclone-config.age".publicKeys = user-machines;
  "kubeconfig.age".publicKeys = user-machines;
  "adguardhome.age".publicKeys = user-machines ++ mac-cluster-machines;
  "rke-token-mac-cluster.age".publicKeys = user-machines ++ mac-cluster-machines;
  "hosts.age".publicKeys = user-machines ++ mac-cluster-machines;
}
