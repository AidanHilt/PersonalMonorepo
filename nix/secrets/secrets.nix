let
  # Personal laptop
  hyperion-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion";
  hyperion-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILIl+K6+k3TmEzx3N1Wjh8ILoGU2X9MAmr/EkgTOPFLO root@hyperion";

  # Work laptop
  # We don't use secrets, but we need a second machine that can run agenix to handle setup
  workvm-user = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDEgIyx4Hs7Tl3Fkg6nlqCpIzzzzsMd5ecgk5Kfh8bJ70ktcetn9OCJ/MkkR0LmHiZNh8dobHS78PqqAendqQa9Yo1SAh4Qu1G8Aw1rd3MhktM+6j22qsNpC2Tomj3Y5kEwpNjW0jEEuJM30JC7RuJshA7/kSs+3mcw1uYr89TcZJba1ZT5d6+NfRyaZ9zrwwmeDHfp73H56D6Il0ppWx9ig0r8v64xhQNTr4T3ilGjDEYj127QmpanWbihrt4uIV7kd9FGGTmeDsdqrPRmz3i9cDYY8j7s9NuCqdnGrOGEdAyGSboXYjUEOEhia/iH6/DhU8dcNlmdEdzaUMi9ewvJgiWc5bM7TC0jMFbEeRyyOsFqbDanLx2ggMVYB9vOpwJ/n/IfhIEXQff6TFXgCvcDIVf94Pq5EsRIM8D4DqArOSYL1+whXG2I/6u9lNmwkJDA7v+ocsG9he4ZlUmcJ184wqbHOibP9k2k6oluGerWGeN5pQv69BvztYYWL1i1zWU= root@Aidans-Macbook-Pro";

  # WSL keys
  wsl-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEAi2UjaWUsDVY6wUMMcIjDXzyizhax86Z0J2I6fYM0 nixos@nixos";
  wsl-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICbW6OhxPYPuJTZAgbpL3+PwHPNvdL2dw8+KqA1QeF47 root@nixos";
in
{
  "smb-mount-config.age".publicKeys = [ hyperion-user hyperion-system wsl-user wsl-system workvm-user ];
  "rclone-config.age".publicKeys = [ hyperion-user hyperion-system wsl-user wsl-system workvm-user ];
  "kubeconfig.age".publicKeys = [ hyperion-user hyperion-system wsl-user wsl-system workvm-user ];
}
