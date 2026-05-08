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
make run                # start container 'tracy-eval'
make run NAME=tracy-2   # start container with a custom name
make watch              # follow stdout of 'tracy-eval'
make watch NAME=tracy-2 # follow stdout of a custom-named container
make stop               # stop & remove 'tracy-eval'
make stop NAME=tracy-2  # stop & remove a custom-named container
make help               # list targets
```

The default container name is `tracy-eval`. The default image name is
`local-tracy-evaluation-control` (override with `IMAGE=...`).

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
docker run -d --name tracy-eval \
  --env-file .env \
  -v "$PWD/TASK.md:/home/coder/control/TASK.md:ro" \
  local-tracy-evaluation-control
```

## Watch progress

```sh
docker logs -f tracy-eval
# or, equivalently:
docker exec tracy-eval tail -f /home/coder/control/claude.log
```

Claude's transcript is persisted to `/home/coder/control/claude.log` inside the
container. With the default `CLAUDE_OUTPUT_FORMAT=stream-json`, this is
newline-delimited JSON (one event per line — assistant messages, tool calls,
results). Set `CLAUDE_OUTPUT_FORMAT=text` in `.env` for the old human-readable
format.

## Push commits Claude made

The container stays alive after Claude finishes (the entrypoint ends with
`tail -F` on the log) so you can inspect state and push.

```sh
docker exec -it tracy-eval bash
# inside the container:
cd /home/coder/control/tracy
git log --oneline -20
git remote -v          # add a remote if needed
git push origin <branch>
```

Commits are authored as `Claude Agent <claude-agent@anthropic.local>`.

## Cleanup

```sh
docker rm -f tracy-eval
```

## Layout

```
.
├── Makefile                # bootstrap / build / run / watch / stop targets
├── Dockerfile              # base + toolchain + Claude Code; entrypoint runs Claude
├── entrypoint.sh           # runs `claude -p` on TASK.md, tees to claude.log, then tail -F
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
