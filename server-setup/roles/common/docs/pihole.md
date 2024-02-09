# Pihole Setup

[Pihole](https://pi-hole.net/) is a DNS-based, network-wide adblocker. We deploy it using Docker, because containers are easy. However, we want it to be highly-available, which is why we also set up [Gravity Sync](https://github.com/vmstan/gravity-sync) and [keepalived](https://www.keepalived.org/) to create a clustered setup. Gravity Sync is used to sync configuration between all of our Pihole instances. Keepalived is then used to serve all of our instances behind a single IP address. As an architectural note, the reason we run this in regular Docker, rather than in Kubernetes, is because we want to have DNS available for the cluster, in case we need to pull system images. To get it set up, we run the following steps with Ansible:

1. Include the [docker setup](docker-setup.md) and [ssh key exchange](ssh-key-exchange.md) playbooks, as necessary pre-requisites
2. First, we need to free port 53, which is held by [systemd-resolved](https://wiki.archlinux.org/title/systemd-resolved)
3. Set Pihole to run with Docker Compose
4. Install the Gravity Sync config in `/etc/gravity-sync`
5. Why do we have passwordless sudo?
6. Don't we already have passwordless docker?