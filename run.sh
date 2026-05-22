#!/usr/bin/env bash
# AutoResearch — Docker launcher.
#
# Usage:
#   ./run.sh run --config config_bt.yaml
#   ./run.sh run --config config_bt.yaml --stop-after scope
#   AUTORESEARCH_VERSION=latest ./run.sh run ...     # force latest tag
#
# Expects this shell repo to contain:
#   prompts/                  ← canonical prompts (this repo's git-tracked copy)
#   config*.yaml              ← run configs
#   knowledge_base/           ← seed KB + index.json
#   research_runs/            ← output (git-tracked or shared)
#   .env                      ← ANTHROPIC_API_KEY=sk-ant-...
set -euo pipefail

# Pinned canonical version. Bumped in lockstep with prompt changes — see
# CHANGELOG.md before overriding to :latest.
PINNED_VERSION="0.6"
VERSION="${AUTORESEARCH_VERSION:-$PINNED_VERSION}"
IMAGE="ghcr.io/REPLACEME/autoresearch:${VERSION}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# .env must exist with ANTHROPIC_API_KEY.
if [[ ! -f "$HERE/.env" ]]; then
  echo "missing .env — copy .env.example and add your ANTHROPIC_API_KEY" >&2
  exit 1
fi

# Ensure mount targets exist on host (docker would create them as root otherwise).
mkdir -p "$HERE/research_runs" "$HERE/knowledge_base" "$HERE/prompts"

docker pull "$IMAGE" >/dev/null

exec docker run --rm -it \
  --env-file "$HERE/.env" \
  -v "$HERE:/work" \
  -v "$HERE/prompts:/app/prompts:ro" \
  "$IMAGE" "$@"
