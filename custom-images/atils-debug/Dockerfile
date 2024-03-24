FROM alpine:latest

# Install necessary packages
RUN apk update && apk add --no-cache \
    zsh \
    git \
    curl \
    wget \
    iputils \
    bind-tools \
    busybox-extras \
    net-tools \
    tcpdump \
    jq \
    yq \
    postgresql-client

# Set Zsh as the default shell, install OhMyZsh, and install addons
RUN sed -i -e "s/bin\/ash/bin\/zsh/" /etc/passwd && \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting && \
    git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

WORKDIR /root

COPY .zshrc /root/.zshrc
COPY .p10k.zsh /root/.p10k.zsh

# Set the entrypoint to keep the container running
CMD ["sleep", "infinity"]