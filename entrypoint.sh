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

if [ -n "${REPO_PAT:-}" ]; then
  echo "[entrypoint] REPO_PAT is set (${#REPO_PAT} chars) - tracy branch WILL be auto-pushed to GitHub on exit."
else
  echo "[entrypoint] REPO_PAT is NOT set - auto-push DISABLED; push manually via 'make exec' after Claude exits."
fi

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

push_to_remote() {
  if [ -z "${REPO_PAT:-}" ]; then
    echo "[entrypoint][push] REPO_PAT not set - skipping remote push. Use 'make exec' and push manually."
    return 0
  fi

  cd /home/coder/control/tracy || { echo "[entrypoint][push] tracy/ not found - skipping."; return 1; }

  local claude_branch
  claude_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ -z "${claude_branch}" ] || [ "${claude_branch}" = "HEAD" ]; then
    echo "[entrypoint][push] HEAD is detached - skipping push. Claude must end on its working branch."
    return 0
  fi
  if [ "${claude_branch}" = "main" ] || [ "${claude_branch}" = "master" ]; then
    echo "[entrypoint][push] Current branch is '${claude_branch}' - claude did not create a working branch; skipping push."
    return 0
  fi

  if ! git diff --quiet \
     || ! git diff --cached --quiet \
     || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "[entrypoint][push] Uncommitted changes found on '${claude_branch}' - committing as auto-save."
    git add -A
    git commit -m "auto-save: post-claude container exit" || true
  fi

  local run_uuid
  run_uuid=$(cat /proc/sys/kernel/random/uuid)
  local publish_branch="local-claude-control/${claude_branch}/${run_uuid}"
  echo "[entrypoint][push] Creating publish branch '${publish_branch}' from '${claude_branch}' (uuid: ${run_uuid})"
  git branch -f "${publish_branch}" "${claude_branch}"

  local origin_url owner_repo=""
  origin_url=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "${origin_url}" =~ ^git@github\.com:(.+)$ ]]; then
    owner_repo="${BASH_REMATCH[1]%.git}"
  elif [[ "${origin_url}" =~ ^https://github\.com/(.+)$ ]]; then
    owner_repo="${BASH_REMATCH[1]%.git}"
  fi
  if [ -z "${owner_repo}" ]; then
    echo "[entrypoint][push] Cannot parse owner/repo from origin '${origin_url}' - skipping push."
    return 1
  fi

  echo "[entrypoint][push] Pushing ${publish_branch} -> github.com/${owner_repo}"
  if git push \
       "https://x-access-token:${REPO_PAT}@github.com/${owner_repo}.git" \
       "${publish_branch}:${publish_branch}"; then
    echo "[entrypoint][push] Pushed: https://github.com/${owner_repo}/tree/${publish_branch}"
  else
    echo "[entrypoint][push] Push FAILED. Check that REPO_PAT has Contents:write on ${owner_repo}."
    return 1
  fi
}

push_to_remote 2>&1 | tee -a /home/coder/control/claude.log || true

touch "${DONE_MARKER}"
exit "${status}"
