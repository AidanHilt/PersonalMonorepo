{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

system-tasks-darwin-docker-networking = pkgs.writeShellScriptBin "system-tasks-darwin-docker-networking" ''
#!/bin/bash

set -euo pipefail

export colima_host_ip=$(ifconfig -i bridge100 | grep "inet " | cut -d' ' -f6)
export colima_host_ip="192.168.64.1"
echo $colima_host_ip
export colima_vm_ip=$(colima list | grep docker | awk '{print $8}')
echo $colima_vm_ip
export colima_kind_cidr=$(docker network inspect -f '{{.IPAM.Config}}' kind | cut -d'{' -f2 | cut -d' ' -f1)
echo $colima_kind_cidr
export colima_kind_cidr_short=$(docker network inspect -f '{{.IPAM.Config}}' kind | cut -d'{' -f2 | cut -d' ' -f1| cut -d '.' -f1-2)
echo $colima_kind_cidr_short
export colima_vm_iface=$(colima ssh -- ip -br address show to $colima_vm_ip | cut -d' ' -f1)
echo $colima_vm_iface
export colima_kind_iface=$(colima ssh -- ip -br address show to $colima_kind_cidr | cut -d' ' -f1)
echo $colima_kind_iface
sudo route -nv add -net $colima_kind_cidr_short $colima_vm_ip
ssh_cmd="sudo iptables -A FORWARD -s $colima_host_ip -d $colima_kind_cidr -i $colima_vm_iface -o $colima_kind_iface -p tcp -j ACCEPT"
echo $ssh_cmd
colima ssh -- $ssh_cmd
'';
in

{
  environment.systemPackages = [
    system-tasks-darwin-docker-networking
  ];
}