# From the base image (built on Docker host)
FROM coder-base:v0.1.20

# Install everything as root
USER root

RUN \
    apk add \
    go

RUN \
    go install -v golang.org/x/tools/gopls@latest

# Set back to coder user
USER coder
