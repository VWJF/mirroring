# Build context is this directory (GitHub Docker Action) or `./mirror` in CI.
#   docker build -f mirror/Dockerfile ./mirror
FROM debian:bookworm-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        git-lfs \
        jq \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | tee /usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && git lfs install --system \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/mirror.sh scripts/askpass.sh /opt/mirroring/scripts/
COPY entrypoint.sh /opt/mirroring/entrypoint.sh
RUN chmod +x /opt/mirroring/entrypoint.sh /opt/mirroring/scripts/mirror.sh /opt/mirroring/scripts/askpass.sh

ENV ACTION_PATH=/opt/mirroring

WORKDIR /github/workspace

ENTRYPOINT ["/opt/mirroring/entrypoint.sh"]
