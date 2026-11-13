FROM mcr.microsoft.com/devcontainers/rust:1-bookworm

# System deps for CPAL/ALSA (offline rendering does not need these, but the stack will).
RUN apt-get update -qq \
 && apt-get install -y -qq libasound2-dev pkg-config \
 && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/oras-project/oras:v1.2.2 /bin/oras /usr/local/bin/oras

ARG SILENTORB_AGENTS_PUBLISHING_VERSION=0.1.0
ARG SILENTORB_AGENTS_PLANNING_VERSION=0.1.0

RUN mkdir -p /opt/silentorb-agents/silentorb-agents-publishing \
             /opt/silentorb-agents/silentorb-agents-planning \
 && cd /opt/silentorb-agents/silentorb-agents-publishing \
 && oras pull "ghcr.io/silentorb/silentorb-agents-publishing:${SILENTORB_AGENTS_PUBLISHING_VERSION}" \
 && cd /opt/silentorb-agents/silentorb-agents-planning \
 && oras pull "ghcr.io/silentorb/silentorb-agents-planning:${SILENTORB_AGENTS_PLANNING_VERSION}" \
 && chown -R vscode:vscode /opt/silentorb-agents
