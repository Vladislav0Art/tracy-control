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

  # Optional: enables auto-push of Claude's branch on container exit (see "Auto-push to GitHub" below).
  # Needs Contents:write on the tracy repo.
  # REPO_PAT=ghp_...

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
make stop                    # stop & remove 'tracy-eval-1'
make stop NAME=tracy-eval-2  # stop & remove a different container
make help                    # list targets
```

### Container lifecycle

- `make run` — Claude runs against `TASK.md`, then the container **exits**
  (so `docker ps` makes it obvious when the agent has finished). Exit code
  matches Claude's. The container is **not** auto-removed; its filesystem
  stays intact.
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

If `REPO_PAT` is set in `.env`, the entrypoint will, **after Claude exits**:

1. Verify HEAD is on a non-`main` branch in `tracy/`.
2. Safety-net-commit any uncommitted/untracked work as `auto-save: post-claude container exit`.
3. Generate a fresh UUID and create `local-claude-control/<claude-branch>/<uuid>` from Claude's branch (UUID per run, so reruns / parallel containers never collide on the remote).
4. Push that branch to `origin` over HTTPS using the PAT.
5. Print the GitHub URL: `https://github.com/<owner>/<repo>/tree/local-claude-control/<claude-branch>/<uuid>`.

Required PAT scope:

- **Classic PAT** — `repo` (or `public_repo` for a public repo).
- **Fine-grained PAT** — `Contents: Read and write` on the tracy repo.

If `REPO_PAT` is unset, the push step is skipped with a warning, and you can
push manually via `make exec` (see below).

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
├── Makefile                # bootstrap / build / run / watch / stop targets
├── Dockerfile              # base + toolchain + Claude Code; entrypoint runs Claude
├── entrypoint.sh           # runs `claude -p` on TASK.md, tees to claude.log, exits on finish
├── bootstrap.sh            # clones tracy + evaluator into ./artifacts/
├── TASK.md                 # the prompt Claude executes (mounted at runtime)
├── .env                    # secrets + CLAUDE_* overrides, via --env-file (gitignored)
└── artifacts/              # bootstrap output (gitignored)
    ├── tracy/
    └── evaluator/
```

## Notes

- Claude is invoked with `-p ... --model ... --effort ... --max-turns ...
  --max-budget-usd ... --dangerously-skip-permissions --output-format ...
  --verbose`. Defaults live in `entrypoint.sh`; override any of them via the
  `CLAUDE_*` env vars in `.env`.
- The container runs as a non-root `coder` user (required by
  `--dangerously-skip-permissions`); commits are authored as
  `Claude Agent <claude-agent@anthropic.local>` (system git identity).
- The image installs JDK 21, Python 3.12, Node 22, and the Claude Code CLI.
- The image does **not** bake in `.env`; secrets are only present at run time.
