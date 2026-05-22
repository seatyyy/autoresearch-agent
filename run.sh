#!/usr/bin/env bash
# AutoResearch — Docker launcher.
#
# Usage:
#   ./run.sh run --config config_bt.yaml                 # one-shot pipeline run
#   ./run.sh run --config config_bt.yaml --stop-after scope
#   ./run.sh serve                                       # boot the web UI on :8000
#   AUTORESEARCH_VERSION=latest ./run.sh run ...         # force latest tag
#   AUTORESEARCH_PORT=8080 ./run.sh serve                # bind UI on a different port
#
# Expects this shell repo to contain:
#   prompts/                  ← canonical prompts (this repo's git-tracked copy)
#   config*.yaml              ← run configs (editable from the web UI too)
#   knowledge_base/           ← seed KB + index.json
#   research_runs/            ← output (git-tracked or shared)
#   .env                      ← ANTHROPIC_API_KEY=sk-ant-...
set -euo pipefail

# Pinned canonical version. Bumped in lockstep with prompt changes — see
# CHANGELOG.md before overriding to :latest.
PINNED_VERSION="1.0"
VERSION="${AUTORESEARCH_VERSION:-$PINNED_VERSION}"
IMAGE="ghcr.io/REPLACEME/autoresearch:${VERSION}"
PORT="${AUTORESEARCH_PORT:-8000}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# .env must exist with ANTHROPIC_API_KEY.
if [[ ! -f "$HERE/.env" ]]; then
  echo "missing .env — copy .env.example and add your ANTHROPIC_API_KEY" >&2
  exit 1
fi

# Ensure mount targets exist on host (docker would create them as root otherwise).
mkdir -p "$HERE/research_runs" "$HERE/knowledge_base" "$HERE/prompts"

docker pull "$IMAGE" >/dev/null

# Port-publish 8000 always — harmless for `run`, required for `serve`.
# /app/prompts is mounted read-write so the UI's prompt editor (when used)
# can save edits back; flip to :ro if you want prompts immutable from the UI.
exec docker run --rm -it \
  -p "${PORT}:8000" \
  --env-file "$HERE/.env" \
  -v "$HERE:/work" \
  -v "$HERE/prompts:/app/prompts" \
  "$IMAGE" "$@"
