FROM alpine:3.16

RUN apk add --update-cache \
    bash \
    zsh \
    build-base \
    ca-certificates \
    curl \
    htop \
    musl-locales \
    mandoc \
    man-pages \
    python3 \
    sudo \
    tar \
    unzip \
    vim \
    ranger \
    wget \
    nano \
    git \
    openssh \
    nodejs \
    figlet \
    # For VS Code Remote SSH
    gcompat \
    libstdc++ 

# Add a user so that you're not developing as the `root` user
RUN adduser ${USER:-coder} -D -s /bin/zsh && mkdir -p /etc/sudoers.d \
    && echo "${USER:-coder} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USER:-coder} \
    && chmod 0440 /etc/sudoers.d/${USER:-coder}

ENV VERSION=4.7.0

# Install code-server inside the container
RUN \
   wget https://github.com/cdr/code-server/releases/download/v4.7.0/code-server-4.7.0-linux-amd64.tar.gz  && \
   tar x -zf code-server-4.7.0-linux-amd64.tar.gz && \
   rm code-server-4.7.0-linux-amd64.tar.gz && \
   rm code-server-4.7.0-linux-amd64/node && \
   rm code-server-4.7.0-linux-amd64/code-server && \
   rm code-server-4.7.0-linux-amd64/lib/node && \
   mv code-server-4.7.0-linux-amd64 /usr/lib/code-server && \
   sed -i 's/"$ROOT\/lib\/node"/node/g'  /usr/lib/code-server/bin/code-server

USER ${USER:-coder}