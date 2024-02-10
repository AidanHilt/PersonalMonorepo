# Docker Setup
This library task installs Docker on an Ubuntu machine. It performs the following steps:

1. Add Docker repository to apt
2. Install docker, the docker CLI, containerd, and docker-compose.
3. Install pip3
4. Using pip3, install the docker and docker-compose Python libraries. This is so we can use Ansible to manage docker-compose stacks down the line.
5. Add the user "aidan" to the docker group for sudoless `docker`.