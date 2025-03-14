# Bootstrapping a NixOS server

By far, the worst part of setting up a NixOS machine is bootstrapping it. It's not so bad when you have access to a machine and can copy and paste out of it, but it gets trickier when you want to set your stuff up remotely. The best way to handle this is to have a simple procedure that makes you think as little as possible, and is well-rehearsed. Here's my attempt at one.

1. Install basic software and configuration
    * ```curl https://raw.githubusercontent.com/AidanHilt/PersonalMonorepo/refs/heads/feat/staging-cluster-setup/nix/server-setup/bootstrap/configuration.nix > /etc/nixos/configuration.nix```   
    This will add a few tools we'll use later in the process to our `configuration.nix`. This needs to be run with some kind of root access
    * ```nixos-rebuild switch```  
    Actually applies our new configuration.nix. You shouldn't even need to reboot! 
2. sfasdfasdf