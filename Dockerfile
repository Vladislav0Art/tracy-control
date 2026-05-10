FROM eclipse-temurin:21-jdk-noble

# Image: local-tracy-evaluation-control
# Bakes in tracy/ and evaluator/; expects TASK.md to be bind-mounted at run
# time, and secrets + claude CLI overrides supplied via --env-file.

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

# System-wide git identity so any commits Claude makes are attributable, and
# coder inherits it without per-user setup.
RUN git config --system user.email "claude-agent@anthropic.local" && \
    git config --system user.name "Claude Agent" && \
    git config --system init.defaultBranch main && \
    git config --system --add safe.directory '*'

# Non-root user (required by --dangerously-skip-permissions).
RUN useradd -m -s /bin/bash coder && \
    mkdir -p /home/coder/control && \
    chown -R coder:coder /home/coder

WORKDIR /home/coder/control

COPY --chown=coder:coder artifacts/tracy/ /home/coder/control/tracy/
COPY --chown=coder:coder artifacts/evaluator/ /home/coder/control/evaluator/

COPY entrypoint.py /usr/local/bin/entrypoint.py
RUN chmod +x /usr/local/bin/entrypoint.py

USER coder

ENTRYPOINT ["/usr/local/bin/entrypoint.py"]
