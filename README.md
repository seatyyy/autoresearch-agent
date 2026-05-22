# AutoResearch — Lab Shell

This repo is the user-facing surface for the AutoResearch pipeline. Edit prompts, configs, and your knowledge base here; the orchestration runs inside a Docker image that's auto-pulled by `run.sh`.

## Setup

```bash
# 1. Install Docker + GitHub Container Registry access
docker login ghcr.io       # use a GitHub PAT with read:packages

# 2. Copy your API key
cp .env.example .env
$EDITOR .env               # add ANTHROPIC_API_KEY=sk-ant-...

# 3. Smoke test
./run.sh run --help
```

## Usage

```bash
# Full pipeline run on the bitcoin config
./run.sh run --config config_bt.yaml

# Scope only (fast feedback loop while editing prompts)
./run.sh run --config config_bt.yaml --stop-after scope

# Resume an existing run after editing a downstream prompt
./run.sh run --config config_bt.yaml --resume <user_name>_20260521T143000 --start-from literature
```

Outputs land in `research_runs/<project_id>/<user_id>_<timestamp>/`. Commit them to share with the group.

## What you edit here

- **`prompts/*.md`** — the methodology. This is the main reason you have this repo. Edit a prompt, re-run, iterate.
- **`config*.yaml`** — topic, model, tunables.
- **`knowledge_base/`** — seed papers + extracted metadata. Run `./run.sh build-kb` to refresh.

When you change a prompt, save and re-run — there's no rebuild step.

## Updating the orchestration

When the contractor pushes a new image version:

1. `git pull` this repo — picks up the new `run.sh` PINNED_VERSION, updated canonical prompts, and a `CHANGELOG.md` entry.
2. If you've locally modified a prompt that also changed upstream, git will surface a merge conflict. Resolve it the usual way.
3. Run as normal — `run.sh` will pull the new image on first invocation.

To peek at a version not yet pinned:
```bash
AUTORESEARCH_VERSION=latest ./run.sh run --config config_bt.yaml
```

## Layout

```
.
├── run.sh                   # wraps docker run
├── prompts/                 # canonical methodology — edit freely
│   ├── scope.md
│   ├── analysis.md
│   ├── eval_design.md
│   ├── critic.md
│   ├── evolve.md
│   ├── search_queries.md
│   ├── literature_rank.md
│   ├── literature_synthesis.md
│   ├── experiment_*.md
│   ├── summary.md
│   ├── kb_extract.md
│   └── graph_extract.md
├── config_bt.yaml           # bitcoin / cryptography topic
├── config_ml.yaml           # alt topic
├── knowledge_base/
│   ├── index.json
│   ├── references.json
│   └── raw/                 # gitignored — re-fetchable from references.json
├── research_runs/           # outputs — commit selectively
├── CHANGELOG.md
├── .env.example
└── .gitignore
```
