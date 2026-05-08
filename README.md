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
  ```

## Quick start (Makefile)

```sh
make bootstrap          # clone tracy + evaluator into ./artifacts/
make build              # docker build -t local-tracy-evaluation-control .
make run                # start container 'tracy-eval'
make run NAME=tracy-2   # start container with a custom name
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

`TASK.md` and `claude_settings.json` are bind-mounted (not baked in), so you can
edit them between runs without rebuilding. Secrets come from `.env` via `--env-file`.

```sh
docker run -d --name tracy-eval \
  --env-file .env \
  -v "$PWD/TASK.md:/root/control/TASK.md:ro" \
  -v "$PWD/claude_settings.json:/root/.claude/settings.json:ro" \
  local-tracy-evaluation-control
```

## Watch progress

```sh
docker logs -f tracy-eval
# or, equivalently:
docker exec tracy-eval tail -f /root/control/claude.log
```

Claude's full transcript is also persisted to `/root/control/claude.log` inside
the container.

## Push commits Claude made

The container stays alive (`sleep infinity`) after Claude finishes so you can
inspect state and push.

```sh
docker exec -it tracy-eval bash
# inside the container:
cd /root/control/tracy
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
├── Makefile                # bootstrap / build / run targets
├── Dockerfile              # base + toolchain + Claude Code; entrypoint runs Claude
├── entrypoint.sh           # runs `claude -p` on TASK.md, tees to claude.log, then sleeps
├── bootstrap.sh            # clones tracy + evaluator into ./artifacts/
├── TASK.md                 # the prompt Claude executes (mounted at runtime)
├── claude_settings.json    # mounted as ~/.claude/settings.json (mounted at runtime)
├── .env                    # secrets, passed via --env-file (gitignored)
└── artifacts/              # bootstrap output (gitignored)
    ├── tracy/
    └── evaluator/
```

## Notes

- `claude_settings.json` keys `maxTurns` and `max_budget_usd` are **not** standard
  Claude Code settings keys and will be ignored. To cap turns, pass `--max-turns N`
  to the `claude` invocation in `entrypoint.sh`.
- The image installs JDK 21, Python 3.12, Node 22, and the Claude Code CLI.
- The image does **not** bake in `.env`; secrets are only present at run time.
