FROM eclipse-temurin:21-jdk-noble

# Image: local-tracy-evaluation-control
# Bakes in tracy/ and evaluator/; expects TASK.md and claude_settings.json
# to be bind-mounted at run time, and secrets supplied via --env-file.

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git curl ca-certificates unzip zip \
        python3.12 python3.12-venv python3-pip && \
    rm -rf /var/lib/apt/lists/*

# Node.js (required for the Claude Code CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# Git identity so any commits Claude makes inside the container are attributable.
RUN git config --global user.email "claude-agent@anthropic.local" && \
    git config --global user.name "Claude Agent" && \
    git config --global init.defaultBranch main && \
    git config --global --add safe.directory '*'

WORKDIR /root/control

COPY artifacts/tracy/ /root/control/tracy/
COPY artifacts/evaluator/ /root/control/evaluator/

# Mount target for claude_settings.json (bind-mounted at run time).
RUN mkdir -p /root/.claude
ENV CLAUDE_CONFIG_DIR=/root/.claude

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
