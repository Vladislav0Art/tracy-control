#!/usr/bin/env python3
"""Entrypoint for the local-tracy-evaluation-control container.

Runs Claude Code in N sequential "sessions" against TASK.md, resumably.

For each session:
  1. Skip if artifacts/<N>/branch.txt already exists (resume marker).
  2. Check out a fresh branch (claude-session-<N>) from the prior session's
     tip (or REPO_BRANCH for session 0).
  3. Invoke `claude -p ...` with a session-aware prompt that tells Claude
     its session index, its branch, and where to put evaluator artifacts.
  4. Auto-commit any uncommitted work the agent left behind.
  5. Save artifacts/<session_idx>/branch.txt with the final branch name.
  6. If REPO_PAT is set, push the branch under
     local-claude-control/<RUN_ID>/session_<session_idx>/<claude_branch>/<uuid>.

After all sessions complete, the entrypoint returns 0 and the container
exits. On a subsequent invocation (docker start, or `docker exec ...
entrypoint.py` with bumped SESSIONS), the entrypoint resumes from the first
missing branch.txt; if everything is done it goes into `tail -F` keep-alive
so `make exec` can drop you in a shell.

Environment variables:
  Required:
    ANTHROPIC_AUTH_TOKEN        Claude API auth token.
  Optional:
    ANTHROPIC_BASE_URL          Claude API base URL.
    TOKEN_LABEL                 Friendly name for the token (printed at startup).
    SESSIONS                    Number of sessions (default 1).
    REPO_BRANCH                 Starting branch for session 0 (default main).
    RUN_ID                      Identifier embedded in publish branch (default run_0).
    REPO_PAT                    GitHub PAT with Contents:write on tracy.
    CLAUDE_MODEL                claude-sonnet-4-6
    CLAUDE_EFFORT               xhigh
    CLAUDE_MAX_TURNS            500
    CLAUDE_MAX_BUDGET_USD       300
    CLAUDE_OUTPUT_FORMAT        stream-json
"""

import os
import re
import shlex
import subprocess
import sys
import textwrap
import uuid
from pathlib import Path
from typing import Optional, Sequence


CONTROL_DIR = Path("/home/coder/control")
TRACY_DIR = CONTROL_DIR / "tracy"
ARTIFACTS_DIR = CONTROL_DIR / "artifacts"
CLAUDE_LOG = CONTROL_DIR / "claude.log"

DEFAULTS = {
    "CLAUDE_MODEL": "claude-sonnet-4-6",
    "CLAUDE_EFFORT": "xhigh",
    "CLAUDE_MAX_TURNS": "500",
    "CLAUDE_MAX_BUDGET_USD": "300",
    "CLAUDE_OUTPUT_FORMAT": "stream-json",
    "SESSIONS": "1",
    "REPO_BRANCH": "main",
    "RUN_ID": "run_0",
}


def log(msg: str) -> None:
    line = f"[entrypoint] {msg}"
    print(line, flush=True)
    with open(CLAUDE_LOG, "a") as f:
        f.write(line + "\n")


def env_or_default(name: str) -> str:
    val = os.environ.get(name, "").strip()
    return val if val else DEFAULTS.get(name, "")


def require_env(name: str) -> str:
    val = os.environ.get(name, "").strip()
    if not val:
        log(f"FATAL: {name} is required (pass via --env-file .env)")
        sys.exit(2)
    return val


def run_streaming(cmd: Sequence[str], *, cwd: Optional[Path] = None) -> int:
    """Run cmd, stream its output to our stdout AND tee into claude.log.
    Returns the exit code."""
    cmd_str = " ".join(shlex.quote(c) for c in cmd)
    log(f"$ {cmd_str}" + (f"  (cwd={cwd})" if cwd else ""))

    with open(CLAUDE_LOG, "a") as logfile:
        proc = subprocess.Popen(
            cmd, cwd=cwd,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        assert proc.stdout is not None
        for line in proc.stdout:
            print(line, end="", flush=True)
            logfile.write(line)
        return proc.wait()


def run_capture(cmd: Sequence[str], *, cwd: Optional[Path] = None) -> str:
    """Run cmd and return stdout (stripped). For short queries; not tee'd."""
    res = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return res.stdout.strip()


def preflight() -> dict:
    log(f"ANTHROPIC_BASE_URL={os.environ.get('ANTHROPIC_BASE_URL') or '<unset>'}")
    auth = require_env("ANTHROPIC_AUTH_TOKEN")
    log(f"TOKEN_LABEL={os.environ.get('TOKEN_LABEL') or '<unset>'}")
    log(f"ANTHROPIC_AUTH_TOKEN is set ({len(auth)} chars)")

    cfg = {k.lower(): env_or_default(k) for k in DEFAULTS}
    cfg["repo_pat"] = os.environ.get("REPO_PAT", "").strip()

    try:
        cfg["sessions"] = int(cfg["sessions"])
    except ValueError:
        log(f"FATAL: SESSIONS must be an integer; got {cfg['sessions']!r}")
        sys.exit(2)
    if cfg["sessions"] < 1:
        log(f"FATAL: SESSIONS must be >= 1; got {cfg['sessions']}")
        sys.exit(2)

    log(f"CLAUDE_MODEL={cfg['claude_model']}")
    log(f"CLAUDE_EFFORT={cfg['claude_effort']}")
    log(f"CLAUDE_MAX_TURNS={cfg['claude_max_turns']}")
    log(f"CLAUDE_MAX_BUDGET_USD={cfg['claude_max_budget_usd']}")
    log(f"CLAUDE_OUTPUT_FORMAT={cfg['claude_output_format']}")
    log(f"SESSIONS={cfg['sessions']}  REPO_BRANCH={cfg['repo_branch']}  RUN_ID={cfg['run_id']}")
    if cfg["repo_pat"]:
        log(f"REPO_PAT is set ({len(cfg['repo_pat'])} chars) - branches WILL auto-push to GitHub at end of each session.")
    else:
        log("REPO_PAT is NOT set - auto-push DISABLED; push manually via 'make exec'.")

    return cfg


def session_branch_name(session_idx: int) -> str:
    return f"claude-session-{session_idx}"


def session_dir(session_idx: int) -> Path:
    return ARTIFACTS_DIR / str(session_idx)


def session_done(session_idx: int) -> bool:
    return (session_dir(session_idx) / "branch.txt").exists()


def find_resume_point(sessions: int) -> int:
    """Return the index of the first session that has not completed yet, or
    `sessions` (one past the end) if all are complete."""
    for idx in range(sessions):
        if not session_done(idx):
            return idx
    return sessions


def get_base_for_session(session_idx: int, repo_branch: str) -> str:
    """Session 0 → REPO_BRANCH. Session N>0 → branch recorded in
    artifacts/<N-1>/branch.txt. Caller must ensure the prior session is
    complete (find_resume_point guarantees this)."""
    if session_idx == 0:
        return repo_branch
    prev_branch_file = session_dir(session_idx - 1) / "branch.txt"
    return prev_branch_file.read_text().strip()


def build_prompt(session_idx: int, branch: str, base_branch: str) -> str:
    artifacts_subdir = f"/home/coder/control/artifacts/{session_idx}"
    changelog = "/home/coder/control/tracy/CHANGELOG.md"
    return textwrap.dedent(f"""\
        Read /home/coder/control/TASK.md and execute the task defined in it.

        Session context (set by the entrypoint, not negotiable):
          - This is session {session_idx} (zero-indexed).
          - Working git branch in /home/coder/control/tracy: '{branch}'.
            It was branched off '{base_branch}'. Stay on this branch - do NOT
            check out a different branch and do NOT create new branches.
          - Save evaluator JSON outputs under
              {artifacts_subdir}/evaluation_<attempt_idx>.json
            where <attempt_idx> is zero-indexed (one file per evaluator run
            within this session). Create the directory if missing.
          - Maintain the project changelog at {changelog}. First, READ the
            file (if present) so you know what previous sessions did and can
            continue incrementally without redoing their work. Then APPEND a
            new section for session {session_idx} containing:
              * session id ({session_idx})
              * branch '{branch}' (this is what gets pushed)
              * base branch '{base_branch}'
              * number of evaluator attempts you ran
              * pointer to artifacts/{session_idx}/evaluation_<i>.json
              * brief summary of changes you made
            Commit this changelog as part of your work so it ends up in the
            branch's git history.

        Make as much progress as you can. Work in /home/coder/control.
        """)


def invoke_claude(session_idx: int, branch: str, base_branch: str, cfg: dict) -> int:
    cmd = [
        "claude", "-p", build_prompt(session_idx, branch, base_branch),
        "--model", cfg["claude_model"],
        "--effort", cfg["claude_effort"],
        "--max-turns", cfg["claude_max_turns"],
        "--max-budget-usd", cfg["claude_max_budget_usd"],
        "--dangerously-skip-permissions",
        "--output-format", cfg["claude_output_format"],
        "--verbose",
    ]
    return run_streaming(cmd, cwd=CONTROL_DIR)


def commit_leftovers(session_idx: int) -> None:
    status = run_capture(["git", "status", "--porcelain"], cwd=TRACY_DIR)
    if not status:
        return
    log(f"Session {session_idx}: uncommitted changes found - auto-committing.")
    run_streaming(["git", "add", "-A"], cwd=TRACY_DIR)
    run_streaming(
        ["git", "commit", "-m", f"auto-save: post-claude session {session_idx}"],
        cwd=TRACY_DIR,
    )


def parse_owner_repo(origin_url: str) -> Optional[str]:
    m = re.match(r"^git@github\.com:(.+?)(?:\.git)?$", origin_url)
    if m:
        return m.group(1)
    m = re.match(r"^https://github\.com/(.+?)(?:\.git)?$", origin_url)
    if m:
        return m.group(1)
    return None


def push_session(session_idx: int, claude_branch: str, cfg: dict) -> None:
    if claude_branch in ("HEAD", "main", "master", ""):
        log(f"Session {session_idx} push: branch '{claude_branch}' is unsafe to push; skipping.")
        return
    origin = run_capture(["git", "remote", "get-url", "origin"], cwd=TRACY_DIR)
    owner_repo = parse_owner_repo(origin)
    if not owner_repo:
        log(f"Session {session_idx} push: could not parse owner/repo from '{origin}'; skipping.")
        return

    run_uuid = str(uuid.uuid4())
    publish = (
        f"local-claude-control/{cfg['run_id']}"
        f"/session_{session_idx}/{claude_branch}/{run_uuid}"
    )
    log(f"Session {session_idx} push: creating publish branch '{publish}' (uuid: {run_uuid})")
    run_streaming(["git", "branch", "-f", publish, claude_branch], cwd=TRACY_DIR)
    push_url = f"https://x-access-token:{cfg['repo_pat']}@github.com/{owner_repo}.git"
    rc = run_streaming(
        ["git", "push", push_url, f"{publish}:{publish}"],
        cwd=TRACY_DIR,
    )
    if rc == 0:
        log(f"Session {session_idx} push: SUCCESS - https://github.com/{owner_repo}/tree/{publish}")
    else:
        log(f"Session {session_idx} push: FAILED. Check that REPO_PAT has Contents:write on {owner_repo}.")


def run_session(session_idx: int, base_branch: str, cfg: dict) -> None:
    log(f"=== Session {session_idx} starting (base branch: {base_branch}) ===")
    branch = session_branch_name(session_idx)
    sd = session_dir(session_idx)
    sd.mkdir(parents=True, exist_ok=True)

    rc = run_streaming(["git", "checkout", "-B", branch, base_branch], cwd=TRACY_DIR)
    if rc != 0:
        log(f"Session {session_idx}: checkout failed; skipping this session.")
        return

    rc = invoke_claude(session_idx, branch, base_branch, cfg)
    log(f"Session {session_idx}: claude exited with {rc}.")

    commit_leftovers(session_idx)

    final_branch = run_capture(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=TRACY_DIR) or branch
    log(f"Session {session_idx}: final HEAD branch is '{final_branch}'.")
    (sd / "branch.txt").write_text(final_branch + "\n")

    if cfg["repo_pat"]:
        push_session(session_idx, final_branch, cfg)
    else:
        log(f"Session {session_idx}: skipping push (REPO_PAT unset).")


def keepalive_tail() -> None:
    """Replace this process with `tail -F` on claude.log so the container
    stays alive for inspection. Used when there is no work to do."""
    log("Going to tail -F /home/coder/control/claude.log (keep-alive). Ctrl-C to detach `make watch`; the container stays running.")
    os.execvp("tail", ["tail", "-n", "+1", "-F", str(CLAUDE_LOG)])


def main() -> int:
    CONTROL_DIR.mkdir(parents=True, exist_ok=True)
    CLAUDE_LOG.touch(exist_ok=True)  # don't truncate; preserve prior runs
    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)

    cfg = preflight()

    # Trust git repos (avoids 'dubious ownership' under the coder user).
    run_streaming(["git", "config", "--global", "--add", "safe.directory", "*"])

    sessions = cfg["sessions"]
    resume_from = find_resume_point(sessions)

    if resume_from >= sessions:
        log(f"All {sessions} session(s) already complete (artifacts/<i>/branch.txt present for i in 0..{sessions - 1}).")
        keepalive_tail()
        return 0  # not reached

    if resume_from > 0:
        log(f"Resuming: sessions 0..{resume_from - 1} already done; starting at session {resume_from}.")
        if cfg["repo_branch"] != DEFAULTS["REPO_BRANCH"]:
            log(f"Note: REPO_BRANCH={cfg['repo_branch']} only matters for session 0, which is already done; ignored on resume.")

    for session_idx in range(resume_from, sessions):
        base_branch = get_base_for_session(session_idx, cfg["repo_branch"])
        run_session(session_idx, base_branch, cfg)

    log(f"All {sessions} session(s) finished. Container will exit; use 'make exec' to inspect or 'make resume' to add more sessions.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
