#!/usr/bin/env bash
set -u
cd /home/coder/control

DONE_MARKER=/home/coder/control/.claude_done

# Re-entry mode: container was started again after Claude already finished.
# Skip the run, keep the container alive so `docker exec` works.
if [ -f "${DONE_MARKER}" ]; then
  echo "[entrypoint] ${DONE_MARKER} present - Claude already ran in this container; keeping it alive for inspection."
  echo "[entrypoint] Remove ${DONE_MARKER} and restart the container to re-run Claude."
  exec tail -n +1 -F /home/coder/control/claude.log
fi

echo "[entrypoint] ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL:-<unset>}"
: "${ANTHROPIC_AUTH_TOKEN:?ANTHROPIC_AUTH_TOKEN is required (pass via --env-file .env)}"
echo "[entrypoint] TOKEN_LABEL=${TOKEN_LABEL:-<unset>}"
echo "[entrypoint] ANTHROPIC_AUTH_TOKEN is set (${#ANTHROPIC_AUTH_TOKEN} chars)"

: "${CLAUDE_MODEL:=claude-sonnet-4-6}"
: "${CLAUDE_EFFORT:=xhigh}"
: "${CLAUDE_MAX_TURNS:=500}"
: "${CLAUDE_MAX_BUDGET_USD:=300}"
: "${CLAUDE_OUTPUT_FORMAT:=stream-json}"

echo "[entrypoint] CLAUDE_MODEL=${CLAUDE_MODEL}"
echo "[entrypoint] CLAUDE_EFFORT=${CLAUDE_EFFORT}"
echo "[entrypoint] CLAUDE_MAX_TURNS=${CLAUDE_MAX_TURNS}"
echo "[entrypoint] CLAUDE_MAX_BUDGET_USD=${CLAUDE_MAX_BUDGET_USD}"
echo "[entrypoint] CLAUDE_OUTPUT_FORMAT=${CLAUDE_OUTPUT_FORMAT}"

git config --global --add safe.directory '*'

claude -p "Read /home/coder/control/TASK.md and execute the task defined in it. Work in /home/coder/control. Make as much progress as you can." \
  --model "${CLAUDE_MODEL}" \
  --effort "${CLAUDE_EFFORT}" \
  --max-turns "${CLAUDE_MAX_TURNS}" \
  --max-budget-usd "${CLAUDE_MAX_BUDGET_USD}" \
  --dangerously-skip-permissions \
  --output-format "${CLAUDE_OUTPUT_FORMAT}" \
  --verbose \
  2>&1 | tee /home/coder/control/claude.log
status=${PIPESTATUS[0]}
echo "[entrypoint] Claude finished with exit ${status}." \
  | tee -a /home/coder/control/claude.log

touch "${DONE_MARKER}"
exit "${status}"
