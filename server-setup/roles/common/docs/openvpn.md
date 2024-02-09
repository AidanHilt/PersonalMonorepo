# OpenVPN Setup

TODO This should actually be its own role, unless we want to build a cluster
While our ideal goal is to be able to access all of our services from anywhere in the world, there are some things that are too risky to be ok with putting out on the public internet, even behind a reverse proxy. For those, we'll create a VPN using [OpenVPN Access Server](https://openvpn.net/access-server/) in [high-availability failover mode](https://openvpn.net/vpn-server-resources/setting-up-high-availability-failover-mode/). To do this, we run the following steps with Ansible:

1. Perform an [SSH key exchange](ssh-key-exchange.md) so both machines can access each other
2. Add the OpenVPN repository to apt
3. Install OpenVPN Access Server using apt
4. Copy over default config, specifying whether node is primary or secondary
5. Configure the primary OpenVPN node with everything it needs. This means, for both nodes, adding its enabled state, the node type, hostname, ssh port, username to use, and the password for the admin user
