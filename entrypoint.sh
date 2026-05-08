#!/usr/bin/env bash
set -u
cd /root/control

echo "[entrypoint] ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL:-<unset>}"
: "${ANTHROPIC_AUTH_TOKEN:?ANTHROPIC_AUTH_TOKEN is required (pass via --env-file .env)}"
echo "[entrypoint] ANTHROPIC_AUTH_TOKEN is set (${#ANTHROPIC_AUTH_TOKEN} chars)"

git config --global --add safe.directory '*'

claude -p "Read /root/control/TASK.md and execute the task defined in it. \
Work in /root/control. Make as much progress as you can." \
  2>&1 | tee /root/control/claude.log
status=${PIPESTATUS[0]}
echo "[entrypoint] Claude finished with exit ${status} - container staying alive for inspection." \
  | tee -a /root/control/claude.log

echo '[entrypoint] Streaming /root/control/claude.log - attach to this container to view it.'

exec tail -n +1 -F /root/control/claude.log
