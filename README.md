<p align="center">
  <img src="banner.png" alt="AutoResearch" width="500">
</p>

# AutoResearch

Autonomous research assistant. Given a topic and a small set of reference papers, AutoResearch scopes the problem (with a critic-evolve loop), runs a literature search, designs and executes experiments, and writes a 2-page mini-paper plus a one-page executive summary end-to-end.

***Note***: this repo is the shell testing version for the labs (design partners) we're collaborating with. It doesn't contain the full code. Licensed research groups have access to the docker image of this product. 

<p align="left">
  <img src="image.png" alt="AutoResearch" width="650">
</p>


## Setup

```bash
# 1. Install (uses uv)
uv sync

# 2. API key
echo 'ANTHROPIC_API_KEY=sk-ant-...' > .env
```

## Quick start

### Step 1. List the reference papers in `knowledge_base/references.json`

Create the file at the repo root (or wherever your config lives — see "References file location" below) with a flat JSON list of URLs:

```json
[
  "https://bitvm.org/bitvm.pdf",
  "https://eprint.iacr.org/2025/1485.pdf"
]
```

Max 10 URLs per run (hard cap — raise with `scope_kb_max_papers` if you need more).

### Step 2. Build the knowledge base

```bash
uv run python build_knowledgedb.py
```

This fetches every URL, extracts metadata (title, authors, abstract, keywords) via the LLM, and markdownifies the paper body. Output lands in `knowledge_base/index.json` + `knowledge_base/raw/<slug>.{pdf,html,md}`. Idempotent — URLs already in `index.json` are skipped on subsequent runs.

You can technically skip this step — stage_scope will auto-build any missing entries on its first run — but pre-warming the cache makes the actual research run much faster.

### Step 3. Write `config.yaml`

See "Configuration" below for the full schema. The minimum required fields are: `topic`, `project_id`, `user_id`, `is_base_run`, `note`.

### Step 4. Run the pipeline

```bash
# First, just run the scoping stage
uv run python cli.py run --config config.yaml --stop-after scope

# If the scoping looks good, resume the run, picking up from the stage
uv run python cli.py run --config config.yaml \
  --resume <user_name>_20260521T143000 \
  --start-from literature

# Verbose (prints every system+user prompt to stderr)
uv run python cli.py run --config config.yaml --debug
```

Outputs land in `research_runs/<project_id>/<user_id>_<timestamp>/`. The `00_summary.md` at the top is the executive briefing — start there.

### References file location

By convention the system auto-discovers `<config_dir>/knowledge_base/references.json`. Override with the `references:` field in your config if you keep your KB elsewhere (e.g. shared across projects).

## Knowledge base

The knowledge base is the set of reference papers the scope stage feeds into every sub-agent (analysis, eval_design, scope orchestrator, critic, evolve). All you maintain is `references.json` — a flat list of URLs.

### Folder layout

```
knowledge_base/
├── references.json    ← you edit this
├── index.json         ← auto-generated metadata (title, authors, abstract, keywords)
└── raw/               ← auto-fetched paper bodies
    ├── bitvm-compute-anything.md         ← markdown extracted from PDF/HTML
    ├── bitvm-compute-anything.pdf        ← original (heavy; gitignored by default)
    └── ...
```

### Auto-build on scope-stage run

When stage_scope runs, it reads `references.json` and for each URL not yet in `index.json`:

1. Fetches the URL (PDF or HTML)
2. Markdownifies the body to `raw/<slug>.md`
3. Calls the LLM with `prompts/kb_extract.md` to extract metadata
4. Appends an entry to `index.json`

Already-indexed URLs are skipped. So `references.json` is the only file you edit; the system handles the rest.

### Manual build (optional)

You can also pre-warm the cache before running the pipeline:

```bash
# Default knowledge_base/ next to the repo root
uv run python build_knowledgedb.py

# A different directory (e.g. per-project KB)
uv run python build_knowledgedb.py --kb-dir bitcoin_kb

# Re-extract everything
uv run python build_knowledgedb.py --force
```

### Constraints

- **Max 10 papers** per `references.json` by default — the scope stage hard-fails if more. Raise with `scope_kb_max_papers` (see below). The cap exists because every sub-agent sees the full markdown of every paper.
- **40k chars per paper** — papers longer than this get truncated with a `[...TRUNCATED]` marker (and an alert in the log). Raise with `scope_kb_max_chars_per_paper` if your papers are dense.
- **Caching**: the KB is injected as a `cache_control: ephemeral` system block in every sub-agent call. First call writes the cache (~~125% input price for that block); subsequent calls within 5 minutes read it (~~10% price). Roughly 3× cheaper than passing it uncached.

## Configuration

All paths in the YAML resolve relative to the config file's directory, not the shell's working directory.

### Full config example

This shows every field. Required fields are uncommented; optional fields show their default value.

```yaml
# ── Required ──────────────────────────────────────────────────────────

# The research problem in one sentence. Drives every downstream stage.
topic: "Optimize Bitcoin on-chain cost for bridge publication."

# Project slug — groups runs of the same research area together.
# Allowed chars: lowercase letters, digits, underscore, hyphen.
# Must start and end alphanumerically.
project_id: "bitcoin-cost-optimization"

# User slug — identifies who launched the run. Same rules as project_id.
# Folder names embed this: research_runs/<project_id>/<user_id>_<timestamp>/
user_id: "xxx"

# true  = fresh run; later fields starting with `base_run_id` / `feedbacks_file`
#         MUST be omitted.
# false = iterative run; `base_run_id` + `feedbacks_file` REQUIRED below.
is_base_run: true

# Free-text note shown in the scope artifact's header. Use "" if none.
# Good for tagging a run with a short reminder (e.g. "trying smaller KB").
note: ""


# ── Iterative run only — omit when is_base_run: true ─────────────────

# Run folder name to refine. Three accepted shapes:
#   leaf:                 <user_name>_20260508T132542
#   project-qualified:    bitcoin-cost-optimization/<user_name>_20260508T132542
#   full path:            research_runs/bitcoin-cost-optimization/<user_name>_...
# base_run_id: "<user_name>_20260508T132542"

# Path to a markdown file containing reviewer feedback for this iteration.
# Resolved relative to the config file. Each stage reads its prior artifact
# and this file to produce a refined version.
# feedbacks_file: "./feedbacks.md"


# ── Knowledge base ────────────────────────────────────────────────────

# Path to references.json (a flat JSON list of paper URLs). If omitted,
# auto-discovers <config_dir>/knowledge_base/references.json. Set explicitly
# only when your KB lives elsewhere (e.g. shared across projects).
# references: "./knowledge_base/references.json"

# Hard ceiling on the number of URLs in references.json. Scope stage fails
# BEFORE doing any fetching when this is exceeded. Default is the safe
# context-budget assumption: 10 papers × 40k chars ≈ 100k tokens injected
# into every sub-agent call. Raise only if you've measured the token math.
scope_kb_max_papers: 10

# Per-paper char cap when injecting markdown into sub-agent prompts.
# Papers longer than this are head-truncated with a "[...TRUNCATED]" marker
# and an alert in the log. Raise for dense papers; lower to save tokens.
scope_kb_max_chars_per_paper: 40000


# ── Model ─────────────────────────────────────────────────────────────

# Anthropic model used for the main pipeline (scope, rank, synth, experiment).
# Stage 2 also spins up a haiku for cheap query-gen + web search regardless.
# Examples: claude-opus-4-7, claude-sonnet-4-6
model: "claude-opus-4-7"

# Default per-call output cap. Each LLM.complete() defaults to this unless
# overridden (codegen uses exp_codegen_max_tokens below). Raise for stages
# that emit long markdown (memo, summary); lower to enforce conciseness.
max_tokens: 16384


# ── Output ────────────────────────────────────────────────────────────

# Where run folders are written. Each run lands at
# <output_dir>/<project_id>/<user_id>_<timestamp>/. Default: ./research_runs
output_dir: "./research_runs"


# ── Stage 2: literature search ───────────────────────────────────────

# Raw hits pulled per web_search query before dedupe. Lower to save haiku
# tokens / wall-clock; raise for broader coverage of niche topics.
lit_results_per_query: 5

# Number of ranked survivors that enter the synthesis call. The synthesis
# LLM sees one paper-row per item, so this drives the size of the final
# literature.md. Default: 12.
lit_top_n: 20


# ── Stage 3: experiment ──────────────────────────────────────────────

# Wall-clock budget (seconds) for ONE attempt of the generated experiment
# subprocess. If it times out, the self-heal loop feeds the traceback back
# to the LLM for a patch. Raise for simulations with high trial counts.
exp_timeout_sec: 500

# Self-heal attempts before giving up. Each retry costs one LLM patch call
# plus one subprocess run. Default: 3.
exp_max_retries: 3

# Per-call output cap for codegen + patch (separate from max_tokens because
# experiment code is long — easy to truncate mid-file otherwise).
# Default: 32768. Sonnet supports up to 64000.
exp_codegen_max_tokens: 16384
```

## CLI

```bash
# First, just run the scoping stage
uv run python cli.py run --config config_bt.yaml --stop-after scope

# If the scoping looks good, resume the run, picking up from the stage
uv run python cli.py run --config config_bt.yaml \
  --resume <user_name>_20260521T143000 \
  --start-from literature

# Verbose (prints every system+user prompt to stderr)
uv run python cli.py run --config config_bt.yaml --debug
```

Stage names: `scope`, `literature`, `experiment`, `summary`.

### Iterative runs

Edit your config:

```yaml
is_base_run: false
base_run_id: "<user_name>_20260521T143000"   # the prior run to refine
feedbacks_file: "./feedbacks.md"         # your free-text feedback
```

Then run normally — each stage adapts its prior artifact against the feedback. The summary stage adds a `### Changes from base run` section.

## Web UI

```bash
uv run python -m app
# → http://127.0.0.1:8000
```

Dashboard lists every project's runs (newest first) and shows a YAML preview of the selected config. Click any run for the live log + rendered markdown artifacts + an **Iterate this run** button that spawns a refinement from a feedback textarea.

Port via `AUTORESEARCH_PORT` (default 8000). One run at a time.

## Pipeline stages


| #   | File                               | Output                                                                   |
| --- | ---------------------------------- | ------------------------------------------------------------------------ |
| 1   | `src/pipeline/stage_scope.py`      | `01_*.md` — analysis, eval_design, scope (with critic/evolve iterations) |
| 2   | `src/pipeline/stage_literature.py` | `02_literature.md` — annotated bibliography + gap analysis               |
| 3   | `src/pipeline/stage_experiment.py` | `03_experiment/{run.py, analysis.md, ...}` + `04_memo.md` (mini paper)   |
| 4   | `src/pipeline/stage_summary.py`    | `00_summary.md` — executive briefing at the top of the run folder        |


## Output artifacts — what's in a run folder

After a run completes, `research_runs/<project>/<user_name>_<timestamp>/` contains the files below. Start with `00_summary.md`.


| Stage         | File                               | Description                                                                                                                      |
| ------------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| 1. Scope      | `01_1_analysis.md`                 | Frames the problem before picking solutions — context, constraints, and candidate-archetype space.                               |
| 1. Scope      | `01_2_eval_design.md`              | Evaluation metrics the scope orchestrator will use to compare candidate directions.                                              |
| 1. Scope      | `01_3_scope.md`                    | Orchestrator's proposal: candidate solution directions scored against the metrics, plus the chosen direction with justification. |
| 1. Scope      | `01_4_critic_N.md`                 | Independent 0-10 score of the current scope proposal with structured feedback. One file per critic invocation.                   |
| 1. Scope      | `01_5_evolve_N.md`                 | Refined scope produced in response to the critic's feedback. One file per evolve iteration.                                      |
| 2. Literature | `02_literature.md`                 | Annotated bibliography (10-15 papers) + gap analysis tied to the scope's Key Questions.                                          |
| 2. Literature | `02_suggested_references.json`     | URLs of papers found during search that aren't yet in `knowledge_base/index.json`.                                               |
| 3. Experiment | `03_experiment/exp_plan.md`        | Experiment design: hypothesis, approach, baseline, inputs, metrics, procedure, JSON output schema.                               |
| 3. Experiment | `03_experiment/run.py` (+ helpers) | Generated Python program the code generator emitted. Prints a JSON metrics object to stdout as its last line.                    |
| 3. Experiment | `03_experiment/metrics.json`       | Raw JSON metrics from the final successful run. Absent if all attempts failed.                                                   |
| 3. Experiment | `03_experiment/results.csv`        | 2-column `name,value` flattening of `metrics.json` for spreadsheet inspection.                                                   |
| 3. Experiment | `03_experiment/fig_*.png`          | Charts the generated code emitted. At least one per experiment (codegen-mandated).                                               |
| 3. Experiment | `03_experiment/analysis.md`        | Results-focused write-up reading the metrics + charts and interpreting them against the hypothesis.                              |
| 3. Experiment | `03_experiment/run_log.json`       | Per-attempt history: exit code, duration, timed-out flag. Useful when an experiment failed.                                      |
| 3. Experiment | `04_memo.md`                       | 2-page mini-paper at the run-dir top level. Frames the result in context of the original scope.                                  |
| 4. Summary    | `00_summary.md`                    | One-page executive briefing aggregating scope, literature, analysis, memo + cost. Written last, read first.                      |
| (always)      | `log.md`                           | Timestamped event log of every stage transition, LLM call (with token + cost), artifact write, and error.                        |
| (always)      | `run_config.yaml`                  | Snapshot of the YAML config this run was launched with. Makes the run self-describing.                                           |


