
YOUR SETTING:
You are given two repositories:

1. Tracy: AI Tracing Kotlin library.
2. API Coverage Evaluator: Evaluator that calculates how many API routes and attributes were covered by Tracy and builds evaluation reports over this information.

Your main task is to introduce modifications, new functionality, or/and enhancements to the existing Tracy code to maximize the evaluation score.


MODIFICATIONS LOOP:
Publish Tracy into local Maven → Run evaluator over published Tracy sources to compute the coverage with an evaluation report → analyze the report, identify areas for improvement in Tracy → proceed to the modifying Tracy sources → once finished with an incremental change, repeat the loop.


PRELIMINARY STEPS:
1. Set up both repositories and ensure you understand how to run tests (mainly, for Tracy) and run evaluator.
1. Next, you MUST understand how to run the evaluator over Tracy sources to compute the coverage. Steps you need to take:
   1. Publish Tracy as a library locally via Gradle's task Local Publish Maven.
   1. Then, feed the generated library sources into the evaluator.
   1. Once you generated the coverage report, you can analyze it, identify areas for improvement in Tracy, and proceed to the modifying Tracy sources to improve the score for the next generation.

Checkout from the main branch into a new branch in which you will implement all the modifications you plan to apply during the entire generation session. In other words, you commit all your changes in a single branch (splitting changes across different commits is for your choice).

NOTES:
1. You can use git commands to create branches, commit/revert changes and view the history of modifications in the Tracy repository.
1. You CANNOT use git to push the implemented modifications yourself, only creating commits/branches.
1. Install any missing dependencies/components you need to run the evaluator, build Tracy or run Tracy tests, etc (FYI, Python and JDK-21 are already installed).
1. Create `CLAUDE_CHANGELOG.md` at the `control` folder where you will list via brief bullet-points what modifications/changes you introduced within a single generation attempt, between running evaluator before/after the change.

FINISH CONDITIONS:
Finish the execution in one of the following conditions:
1. You realize that either the score reached its max value or the evaluation fit a plato with no significant score improvements between your attempts.
1. When you decide that introduced changes already represent HIGH quality implementation of new functionality and enhancements to the existing ones (usually this will be somewhere near the plato state).


INFORMATION:

═══════════════════════════════════════════════════════════════
WHAT YOU'RE BUILDING
═══════════════════════════════════════════════════════════════

Tracy is an OTLP tracing instrumentation that wraps OpenAI / Anthropic / Gemini SDK clients. Production code, evaluated against an external scenario suite. Quality bar: every change must build green, test green, and ship review-ready (KDoc + CHANGELOG).

LLM Provider API References (look up exact request/response field names here):
- OpenAI:    https://developers.openai.com/api/reference/overview
- Anthropic: https://platform.claude.com/docs/en/api/overview
- Gemini:    https://ai.google.dev/gemini-api/docs

OTel GenAI registry (the source of truth for `gen_ai.*` attribute names):
- https://opentelemetry.io/docs/specs/semconv/registry/attributes/gen-ai
- 


══════════════════════════════════════════════════════════
TWO KINDS OF CHANGES — both contribute to next-gen scoring
══════════════════════════════════════════════════════════

1. AUDIT-FIX — repair an existing defect in the codebase.
2. NEW-COVERAGE — make a failing check pass by extending or adding a handler.

Always emit AUDIT-FIX suggestions BEFORE NEW-COVERAGE in your output to ensure higher quality of the generated code.


═══════════════════════════════════════════════════════════════
REQUIRED OUTPUTS for every change
═══════════════════════════════════════════════════════════════

2. **KDoc** on every new public type / function. If a public type's behavior changed, update its KDoc.
3. **CHANGELOG.md** — append a bullet under `## Unreleased`. One bullet per logical change, user-visible terms ("Added Anthropic batches.create span attributes", not "Modified AnthropicListEndpointHandler.kt"). Create CHANGELOG.md if missing.
4. **Tests** — add to the matching `*Test.kt` file. Use MockWebServer + the existing `Base*TracingTest` pattern. NEVER call real APIs. NEVER `Thread.sleep`. Each test asserts the specific span attribute(s) the change is for.
5. **README updates** if any public API surface changed (new public class, renamed function, breaking signature change).


═══════════════════════════════════════════════════════════════
ATTRIBUTE-NAMING POLICY (per spec audit)
═══════════════════════════════════════════════════════════════

When adding a span attribute, decide its namespace BEFORE writing it:

| Attribute concept                                  | Namespace                  |
  |----------------------------------------------------|----------------------------|
| Listed in OTel GenAI registry (`gen_ai.usage.*`,   | `gen_ai.*` (registry)      |
|   `gen_ai.request.model`, `gen_ai.response.id`,    |                            |
|   `gen_ai.prompt.{i}.*`, etc.)                     |                            |
| OpenAI-specific (api.type, system_fingerprint, …)  | `openai.*`                 |
| Anthropic-specific (api.type, batch.processing_…)  | `anthropic.*`              |
| Gemini-specific (api.type, …)                      | `gemini.*` or `tracy.gemini.*` |
| Library-internal (response.created_at, file.*)     | `tracy.*`                  |



═══════════════════════════════════════════════════════════════
VERIFY before finishing
═══════════════════════════════════════════════════════════════

This container does NOT have API keys (OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY are all unset). Plan the verification accordingly:

- `./gradlew assemble --no-daemon` exits 0 — this is your HARD GATE. (`assemble` runs compileKotlinJvm + compileJava + jar; it does NOT run any test task. The breeder discards branches that don't assemble.)
- **DO NOT use `./gradlew build -x test`** — the project is Kotlin Multiplatform; the JVM test task is named `jvmTest` and the aggregate is `allTests`/`check`, so `-x test` does NOT skip them. `assemble` is the right command.

- For the tests YOU just wrote/modified in this gen — run ONLY them, narrowly, and ONLY if they're MockWebServer-based (no real API calls):
  `./gradlew :tracing:<provider>:jvmTest --tests "*.YourNewTest" --no-daemon`
  (Note: `jvmTest`, NOT `test` — this is Kotlin Multiplatform.) If those exit 0, you're done. If they hit a missing-key error, you wrote a test that calls real APIs — rewrite it with MockWebServer + MOCK_API_KEY.

- DO NOT run `./gradlew test`, `./gradlew check`, `./gradlew allTests`, or `./gradlew build`. All of them trigger the FULL test suite, which contains pre-existing integration tests that need real API keys and WILL fail in this container. Those failures are NOT your problem to fix — your gen will be discarded if you try.

- For every new public type: it has KDoc.

- `CHANGELOG.md` has a new bullet under `## Unreleased` for each logical change in this gen.

- Spot-check: `git diff` includes no dead-code branches you intended to remove and no `gen_ai.*` attribute names that aren't in the OTel GenAI registry (or are not under the indexed sub-namespaces `gen_ai.prompt.{i}.*`, `gen_ai.completion.{i}.*`, `gen_ai.tool.{i}.*`).

If `./gradlew assemble` fails: read the gradle log tail and fix only the COMPILATION error (missing import, wrong type, undefined symbol). Do NOT touch unrelated test code. If the error is in a test file you wrote this gen, fix it; if it's in a pre-existing test, rewrite that test to compile (e.g. add a missing import) but do NOT change its assertions. The breeder discards branches that don't assemble.


═══════════════════════════════════════════════════════════════
AUDIT PASS — scan existing handlers for these recurring defect patterns
═══════════════════════════════════════════════════════════════

Before proposing any NEW-COVERAGE work, walk the cloned repo and look for:

▸ **Op-name collisions.** Two distinct routes producing the same `gen_ai.operation.name`. Examples seen in prior gens: Anthropic `batches.results` colliding with `batches.retrieve`; Anthropic `files.content` colliding with `files.retrieve`. The collision silently drops attributes from the lower-priority route.
Fix: rename one to URL-qualified form (`batches.results.retrieve`, `files.content.retrieve`).

▸ **Conflated dispatchers.** One handler routing 3+ unrelated resource classes via path-matching. Example: `AnthropicListEndpointHandler` dispatches batches/models/files via `if (detectedType == "models")` cascades. Latent bugs cluster here.
Fix: split into per-resource handlers (`AnthropicBatchesHandler`, `AnthropicModelsHandler`, `AnthropicFilesHandler`).

▸ **No-op handlers.** `fun execute(...) { /* Unit */ }` or empty `mapOf()` returns that exist only to win dispatch over a fallback. Example: `GeminiModelsHandler` is `Unit`-only; spans get only cross-cutting attrs.
Fix: parse the documented response fields, OR change the dispatcher so the URL doesn't route here.

▸ **Dead-code branches.** Conditions that can never fire because the upstream code path doesn't produce them. Example: anthropic files handler reading `body.deleted` on an endpoint that never returns that field.
Fix: remove. Don't paper over.

▸ **Wrong attribute keys.** Reading API fields that don't exist in the provider's documented schema. Example: anthropic models handler reads `capabilities.vision` — the documented key is `capabilities.image_input.supported`. Span never gets the attribute.
Fix: cross-check against the API reference URL and correct.

▸ **Non-registry `gen_ai.*` names.** Attributes prefixed `gen_ai.` that are not in the OTel GenAI registry (https://opentelemetry.io/docs/specs/semconv/registry/attributes/gen-ai). Indexed `gen_ai.prompt.{i}.*` / `gen_ai.completion.{i}.*` / `gen_ai.tool.{i}.*` ARE registry — leave them. But e.g. `gen_ai.response.batch.*`, `gen_ai.response.list.*`, `gen_ai.usage.total_tokens` are NOT in the registry.
Fix: either (a) move to registry-compliant name if one exists, or (b) move to `tracy.*` / provider-specific (`openai.*`, `anthropic.*`, `gemini.*`) namespace.
