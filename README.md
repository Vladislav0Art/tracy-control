# local-tracy-evaluation-control

Self-contained Docker image that runs Claude Code against `TASK.md` to iteratively
build/publish [tracy](https://github.com/slawa4s/codespheres-tracy), run the
[evaluator](https://github.com/JetBrains/codespheres-evaluator-api-coverage) against the
local build, and improve tracy's score. After Claude finishes the container stays
alive so you can `docker exec` in and push the resulting commits.

## Prerequisites

- Docker
- A `.env` file in the repo root with at least:
  ```
  ANTHROPIC_BASE_URL=...
  ANTHROPIC_AUTH_TOKEN=...
  TOKEN_LABEL=...           # optional: short label of which key this is (printed at startup so you can tell which run uses which credential)

  # Optional: enables auto-push of each session's branch on session exit (see "Auto-push to GitHub" below).
  # Needs Contents:write on the tracy repo.
  # REPO_PAT=ghp_...

  # Optional session-loop knobs (defaults shown):
  # SESSIONS=1                          # number of sequential Claude sessions in this container
  # REPO_BRANCH=main                    # starting branch for session 0
  # RUN_ID=run_0                        # identifier embedded in published branch names

  # Optional Claude CLI overrides (defaults shown):
  # CLAUDE_MODEL=claude-sonnet-4-6
  # CLAUDE_EFFORT=xhigh
  # CLAUDE_MAX_TURNS=500
  # CLAUDE_MAX_BUDGET_USD=300
  # CLAUDE_OUTPUT_FORMAT=stream-json
  ```

## Quick start (Makefile)

```sh
make bootstrap          # clone tracy + evaluator into ./artifacts/
make build              # docker build -t local-tracy-evaluation-control .
make run                     # start container 'tracy-eval-1'
make run NAME=tracy-eval-2   # run a second container in parallel
make watch                   # follow stdout of 'tracy-eval-1'
make watch NAME=tracy-eval-2 # follow stdout of a different container
make exec                    # start (if exited) and bash into 'tracy-eval-1'
make exec NAME=tracy-eval-2  # bash into a different container
make resume                  # re-invoke entrypoint with current .env (e.g. bumped SESSIONS)
make stop                    # stop & remove 'tracy-eval-1'
make stop NAME=tracy-eval-2  # stop & remove a different container
make help                    # list targets
```

### Container lifecycle

- `make run` — the entrypoint runs `SESSIONS` (default 1) sequential
  **sessions**. Each session gets its own git branch (`claude-session-<N>`)
  off the previous session's tip — session 0 branches off `REPO_BRANCH`
  (default `main`), session 1 off session 0's tip, and so on. Inside each
  session, Claude reads `tracy/CHANGELOG.md` for prior-session notes,
  iterates publish→evaluate→fix→commit until it decides it's done, appends
  a CHANGELOG entry, and exits. Then the entrypoint commits any leftovers,
  writes `artifacts/<session_idx>/branch.txt` (the completion marker),
  optionally pushes to GitHub, and starts the next session. After all
  sessions, the container **exits with 0**.
- `make watch` — works on both running and exited containers (`docker logs`
  is persisted by the daemon until removal).
- `make exec` — starts the container (if exited) and gives you a `bash`. The
  entrypoint detects all sessions are already complete and goes into
  `tail -F` keep-alive, so `docker exec` lands cleanly.
- `make resume` — bumped `SESSIONS` in `.env` and want to do more rounds in
  the same container? `make resume` re-invokes `entrypoint.py` inside the
  existing container with the current `.env`. The entrypoint scans
  `artifacts/<N>/branch.txt`, skips already-complete sessions, and runs the
  rest. Resume picks up the prior session's branch from disk, so changes
  remain incremental. (Why a separate target: `docker start` re-runs the
  entrypoint with the env vars captured at `docker run` time, which won't
  reflect a bumped `SESSIONS`. `docker exec --env-file .env` reads `.env`
  fresh.)
- `make stop` — `docker rm -f` to tear down for good. **Removes the
  writable layer**, so all `artifacts/` and committed branches are lost.
  Don't run this if you want to resume later.
- `make watch` — works on both running and exited containers (`docker logs`
  is persisted by the daemon until removal).
- `make exec` — `docker start` + `docker exec bash`. Starting an exited
  container normally re-runs the entrypoint, but a `.claude_done` marker is
  written when Claude finishes; the entrypoint sees it and skips the rerun,
  going straight to keep-alive. Use this to inspect the diff and push commits.
- `make stop` — `docker rm -f` to tear down for good.
- To force a re-run in the same container (rare): `docker exec <name> rm
  /home/coder/control/.claude_done && docker restart <name>`.

The default container name is `tracy-eval-1`. Override with `NAME=...` to run
multiple containers in parallel (`tracy-eval-2`, `tracy-eval-3`, …). The
default image name is `local-tracy-evaluation-control` (override with
`IMAGE=...`).

---

## Manual usage

### 1. Bootstrap source projects

`bootstrap.sh` clones `tracy` and `evaluator` into `./artifacts/` via SSH. It is
idempotent — already-cloned projects are skipped. Make sure your SSH key has
access to the repos.

```sh
./bootstrap.sh
```

After this you should have:
```
artifacts/
  tracy/
  evaluator/
```

The Dockerfile `COPY`s from `artifacts/`, so the build context picks them up.

### 2. Build the image

```sh
docker build -t local-tracy-evaluation-control .
```

### 3. Run

`TASK.md` is bind-mounted (not baked in), so you can edit it between runs
without rebuilding. Secrets and `CLAUDE_*` overrides come from `.env` via
`--env-file`.

```sh
docker run -d --name tracy-eval-1 \
  --env-file .env \
  -v "$PWD/TASK.md:/home/coder/control/TASK.md:ro" \
  local-tracy-evaluation-control
```

## Watch progress

```sh
docker logs -f tracy-eval-1
# or, equivalently:
docker exec tracy-eval-1 tail -f /home/coder/control/claude.log
```

Claude's transcript is persisted to `/home/coder/control/claude.log` inside the
container. With the default `CLAUDE_OUTPUT_FORMAT=stream-json`, this is
newline-delimited JSON (one event per line — assistant messages, tool calls,
results). Set `CLAUDE_OUTPUT_FORMAT=text` in `.env` for the old human-readable
format.

## Auto-push to GitHub

If `REPO_PAT` is set in `.env`, the entrypoint pushes **each session's**
branch to GitHub right after that session ends (i.e. once per `ATTEMPTS`).
For each session it:

1. Verifies HEAD is on a non-`main` branch in `tracy/`.
2. Safety-net-commits any uncommitted/untracked work as `auto-save: post-claude session <N>`.
3. Generates a fresh UUID and creates a publish branch from Claude's branch.
4. Pushes that publish branch to `origin` over HTTPS using the PAT.
5. Prints the GitHub URL.

Published branch pattern:

```
local-claude-control/<RUN_ID>/session_<session_idx>/<claude-branch>/<uuid>
```

- `<RUN_ID>` defaults to `run_0`; override per run.
- `<session_idx>` is the zero-indexed session number.
- `<claude-branch>` is the working branch name (`claude-session-<N>` unless
  Claude renamed HEAD).
- `<uuid>` is per-session, so re-runs and parallel containers never collide.

Required PAT scope:

- **Classic PAT** — `repo` (or `public_repo` for a public repo).
- **Fine-grained PAT** — `Contents: Read and write` on the tracy repo.

If `REPO_PAT` is unset, push is skipped with a warning and you can push
manually via `make exec` (see below).

## Push commits Claude made manually

If you'd rather push by hand (or `REPO_PAT` was unset / push failed), get a
shell into the container's FS state with `make exec`. The entrypoint detects
the `.claude_done` marker on `docker start` and skips the rerun, going into
keep-alive mode so `docker exec` works:

```sh
make exec
# inside the container:
cd /home/coder/control/tracy
git log --oneline -20
git remote -v          # the remote was set by bootstrap.sh's clone
git push origin <branch>
```

Commits are authored as `Claude Agent <claude-agent@anthropic.local>`.

## Cleanup

```sh
docker rm -f tracy-eval-1
```

## Layout

```
.
├── Makefile                # bootstrap / build / run / watch / exec / stop targets
├── Dockerfile              # base + toolchain + Claude Code; entrypoint runs Claude
├── entrypoint.py           # session loop, claude invocation, auto-commit, auto-push
├── bootstrap.sh            # clones tracy + evaluator into ./artifacts/
├── TASK.md                 # the prompt Claude executes (mounted at runtime)
├── .env                    # secrets + CLAUDE_* / session knobs, via --env-file (gitignored)
└── artifacts/              # bootstrap output (gitignored)
    ├── tracy/
    └── evaluator/
```

Inside the container, the entrypoint produces a sibling `artifacts/` tree
(distinct from the host's bootstrap one) at `/home/coder/control/artifacts/`:

```
artifacts/
├── 0/
│   ├── branch.txt              # name of the branch session 0 ended on
│   ├── evaluation_0.json       # raw evaluator output, baseline run
│   ├── evaluation_1.json
│   └── …
├── 1/
│   ├── branch.txt
│   └── evaluation_*.json
└── …
```

Plus `tracy/CHANGELOG.md` gains a fresh section per session (committed to
the session's branch and pushed with it).

## Notes

- Claude is invoked with `-p ... --model ... --effort ... --max-turns ...
  --max-budget-usd ... --dangerously-skip-permissions --output-format ...
  --verbose`. Defaults live in `entrypoint.py`; override any of them via the
  `CLAUDE_*` env vars in `.env`.
- Sessions: see `ATTEMPTS`, `REPO_BRANCH`, `RUN_ID` env vars under
  Prerequisites. Default is one session off `main`.
- The container runs as a non-root `coder` user (required by
  `--dangerously-skip-permissions`); commits are authored as
  `Claude Agent <claude-agent@anthropic.local>` (system git identity).
- The image installs JDK 21, Python 3.12, Node 22, and the Claude Code CLI.
- The image does **not** bake in `.env`; secrets are only present at run time.
