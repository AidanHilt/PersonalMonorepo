let
  hyperion = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion";
  # We don't use secrets, but we need a second machine that can run agenix to handle setup
  workvm = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDEgIyx4Hs7Tl3Fkg6nlqCpIzzzzsMd5ecgk5Kfh8bJ70ktcetn9OCJ/MkkR0LmHiZNh8dobHS78PqqAendqQa9Yo1SAh4Qu1G8Aw1rd3MhktM+6j22qsNpC2Tomj3Y5kEwpNjW0jEEuJM30JC7RuJshA7/kSs+3mcw1uYr89TcZJba1ZT5d6+NfRyaZ9zrwwmeDHfp73H56D6Il0ppWx9ig0r8v64xhQNTr4T3ilGjDEYj127QmpanWbihrt4uIV7kd9FGGTmeDsdqrPRmz3i9cDYY8j7s9NuCqdnGrOGEdAyGSboXYjUEOEhia/iH6/DhU8dcNlmdEdzaUMi9ewvJgiWc5bM7TC0jMFbEeRyyOsFqbDanLx2ggMVYB9vOpwJ/n/IfhIEXQff6TFXgCvcDIVf94Pq5EsRIM8D4DqArOSYL1+whXG2I/6u9lNmwkJDA7v+ocsG9he4ZlUmcJ184wqbHOibP9k2k6oluGerWGeN5pQv69BvztYYWL1i1zWU= root@Aidans-Macbook-Pro";
  wsl-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHh4tIY/al9pyApJa+vH83V0okAvvSTmLuKiljt+v5wP nixos@wsl-machine";
  wsl-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPdfwKxqgxjSNhGBYLuvvoGzBaV5uAFrHqvcLMK+V70A root@nixos";
in
{
  "smb-mount-config.age".publicKeys = [ hyperion wsl-user wsl-system workvm ];
  "rclone-config.age".publicKeys = [ hyperion wsl-user wsl-system workvm ];
  "kubeconfig.age".publicKeys = [ hyperion wsl-user wsl-system workvm ];
}
