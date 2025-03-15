# Bootstrapping a NixOS server

By far, the worst part of setting up a NixOS machine is bootstrapping it. It's not so bad when you have access to a machine and can copy and paste out of it, but it gets trickier when you want to set your stuff up remotely. The best way to handle this is to have a simple procedure that makes you think as little as possible, and is well-rehearsed. Here's my attempt at one.

1. **Install basic software and configuration**
    * ```curl https://raw.githubusercontent.com/AidanHilt/PersonalMonorepo/refs/heads/feat/staging-cluster-setup/nix/server-setup/bootstrap/configuration-${platform}.nix > /etc/nixos/configuration.nix```   
    This will add a few tools we'll use later in the process to our `configuration.nix`. This needs to be run with some kind of root access. In this case, `${platform}` is a choice between `vbox` (meaning an x86 virtual machine running on local hardware), or nothing else right now.
    * ```nixos-rebuild switch```  
    Actually applies our new configuration.nix. You shouldn't even need to reboot! Make sure to add a `sudo` if you're not running as root 
2. **Grab config information**
    * We'll very least need the filesystem mounts. Everything under `fileSystems` in `/etc/nixos/hardware-configuration.nix` will need to be grabbed and added to the `server-setup` flake.
    * If you run into issues getting the next step to work, check `/etc/nixos/configuration.nix` for any sneaky platform-specific parts that may have been missed. Hopefully, we've seen a platform before, so double check step 1 to make sure you grabbed the right platform.
3. **Set up the host keys**