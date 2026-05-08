# TASK

## Setting

You have two repositories in this workspace:

1. **Tracy** (`./tracy/`) — AI-tracing Kotlin library that wraps OpenAI / Anthropic / Gemini SDK clients with OTLP spans.
2. **API Coverage Evaluator** (`./evaluator/`) — runs scenarios against a published Tracy build and reports how much of each SDK's API surface and span attributes Tracy covered.

Your goal: **modify Tracy so the evaluator's coverage score goes up as much as possible.**

## The loop

Repeat until the score plateaus or the changes already represent a HIGH-quality enhancement:

1. Publish Tracy to local Maven (see "Publish Tracy locally" below).
2. Run the evaluator against the local build; get the coverage report.
3. Analyze the report — find missing coverage, broken handlers, wrong attribute names.
4. Make ONE focused change in Tracy (AUDIT-FIX or NEW-COVERAGE — see below).
5. Verify (see "Verify before each commit").
6. Commit on the working branch with a short message.
7. Repeat.

### Publish Tracy locally

From `tracy/`, run:

```sh
GRADLE_OPTS="-Xmx1g -Dorg.gradle.jvmargs=-Xmx1g -Dkotlin.daemon.jvm.options=-Xmx1g" \
  ./gradlew publishAllToMavenLocal -x test
```

Notes:
- `-x test` skips the test task — publishing should not run tests.
- `GRADLE_OPTS` caps heap so the daemon doesn't blow out container memory.

Artifacts land in `~/.m2/repository/org/jetbrains/ai/tracy/`. If that directory doesn't appear after a successful publish, list `~/.m2/repository` to confirm where they went and point the evaluator at that path.

Stop when any of the following holds:
- The score has reached its ceiling.
- Several iterations in a row produce no significant change in score.
- The accumulated diff is a clearly high-quality enhancement.

## Setup steps

1. Read both repos enough to know: how Tracy publishes locally, how the evaluator consumes a Maven repo, where Tracy handlers and tests live.
2. In `tracy/`, check out a new branch off `main`. **All work goes on this single branch.** Split into commits as you like. Do NOT push — pushing is done out-of-band after you finish.
3. Install any extra deps you need. Python 3.12 and JDK 21 are already present.
4. Maintain `/home/coder/control/CLAUDE_CHANGELOG.md` — one terse bullet per iteration with **score before / score after** + what you changed. This is a meta-log of the run, separate from Tracy's own `CHANGELOG.md`.

## Two kinds of changes

Apply in this priority order — finish AUDIT-FIX work before starting NEW-COVERAGE so higher-priority repairs land first:

1. **AUDIT-FIX** — repair an existing defect (bad attribute name, dead branch, op-name collision, conflated dispatcher, no-op handler).
2. **NEW-COVERAGE** — extend or add a handler to cover an API route the evaluator currently fails on.

## Required outputs for every Tracy change

- **KDoc** on every new public type / function. Update KDoc when public behavior changes.
- **Tests** — add to the matching `*Test.kt`. Use the existing `Base*TracingTest` + MockWebServer pattern. **Never** call real APIs. **Never** `Thread.sleep`. Each test asserts the specific span attribute(s) the change is for.
- **`tracy/CHANGELOG.md`** — one bullet under `## Unreleased`, in user-visible terms ("Added Anthropic `batches.create` span attributes", not "Modified `AnthropicListEndpointHandler.kt`"). Create the file if missing.
- **README** updates if any public API surface changed (new public class, renamed function, breaking signature change).

## Attribute-naming policy

Decide an attribute's namespace BEFORE writing it:

| Attribute concept | Namespace |
|---|---|
| Listed in OTel GenAI registry (`gen_ai.usage.*`, `gen_ai.request.model`, `gen_ai.response.id`, indexed `gen_ai.prompt.{i}.*` / `gen_ai.completion.{i}.*` / `gen_ai.tool.{i}.*`, …) | `gen_ai.*` |
| OpenAI-specific (`api.type`, `system_fingerprint`, …) | `openai.*` |
| Anthropic-specific (`api.type`, `batch.processing_*`, …) | `anthropic.*` |
| Gemini-specific | `gemini.*` or `tracy.gemini.*` |
| Library-internal (`response.created_at`, `file.*`) | `tracy.*` |

References:

- OTel GenAI registry: https://opentelemetry.io/docs/specs/semconv/registry/attributes/gen-ai
- OpenAI:    https://developers.openai.com/api/reference/overview
- Anthropic: https://platform.claude.com/docs/en/api/overview
- Gemini:    https://ai.google.dev/gemini-api/docs

## Audit pass — recurring defects to scan for

Before NEW-COVERAGE, walk Tracy looking for these patterns:

- **Op-name collisions.** Two routes producing the same `gen_ai.operation.name` — the lower-priority route silently loses its attributes. (Examples: Anthropic `batches.results` colliding with `batches.retrieve`; `files.content` with `files.retrieve`.) **Fix:** rename one to URL-qualified form (e.g. `batches.results.retrieve`).
- **Conflated dispatchers.** One handler routing 3+ unrelated resource classes via path-matching (e.g. `AnthropicListEndpointHandler` dispatching batches/models/files via `if (detectedType == "models")` cascades). Latent bugs cluster here. **Fix:** split into per-resource handlers.
- **No-op handlers.** `execute(...) { /* Unit */ }` or empty `mapOf()` that exists only to win dispatch over a fallback (e.g. `GeminiModelsHandler` is `Unit`-only; spans get only cross-cutting attrs). **Fix:** parse the documented response fields, or change the dispatcher so the URL doesn't route here.
- **Dead-code branches.** Conditions that can never fire because the upstream code path doesn't produce them (e.g. an anthropic files handler reading `body.deleted` on an endpoint that never returns that field). **Fix:** remove. Don't paper over.
- **Wrong attribute keys.** Reading API fields that don't exist in the provider's documented schema (e.g. anthropic models handler reads `capabilities.vision`; the documented key is `capabilities.image_input.supported` — span never gets the attribute). **Fix:** cross-check against the API reference and correct.
- **Non-registry `gen_ai.*` names.** Attributes prefixed `gen_ai.` that are not in the OTel GenAI registry. Indexed `gen_ai.prompt.{i}.*` / `gen_ai.completion.{i}.*` / `gen_ai.tool.{i}.*` ARE in the registry — leave them. Examples that are NOT: `gen_ai.response.batch.*`, `gen_ai.response.list.*`, `gen_ai.usage.total_tokens`. **Fix:** move to a registry-compliant name if one exists, otherwise to `tracy.*` or the provider namespace.

## Verify before each commit

This container has **no provider API keys** (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` are unset). Plan verification accordingly.

**HARD GATE — `./gradlew assemble --no-daemon` must exit 0.** `assemble` runs `compileKotlinJvm` + `compileJava` + `jar` and runs no test task. If assemble fails, the iteration cannot improve the score — read the gradle log tail and fix only the compilation error (missing import, wrong type, undefined symbol). Don't touch unrelated test code.

- **Do NOT use `./gradlew build -x test`.** Tracy is Kotlin Multiplatform; the JVM test task is `jvmTest` and the aggregate is `allTests` / `check`, so `-x test` does not skip them. Use `assemble`.
- **For tests you just wrote / modified** in this iteration — run them narrowly, and only if they're MockWebServer-based:

  ```
  ./gradlew :tracing:<provider>:jvmTest --tests "*.YourNewTest" --no-daemon
  ```

  Note `jvmTest`, not `test`. If a test hits a missing-key error, you wrote one that calls real APIs — rewrite it with MockWebServer + a mock API key.
- **Do NOT run `./gradlew test`, `./gradlew check`, `./gradlew allTests`, or `./gradlew build`.** They trigger the full suite, which contains pre-existing integration tests that need real API keys and will fail here. Those failures are not yours to fix.

Spot-checks before committing:

- Every new public type has KDoc.
- `tracy/CHANGELOG.md` has a new bullet under `## Unreleased` for each logical change.
- `git diff` shows no dead branches you intended to remove, and no `gen_ai.*` names that aren't in the registry (outside the indexed sub-namespaces).

## Constraints

- Use `git` to branch, commit, and view history. Do **not** push.
- One working branch off `main`; commit granularity is your call.
- Quality bar: every change builds green (`assemble`), tests green (the ones you wrote), and ships with KDoc + a `CHANGELOG.md` bullet.
