#!/usr/bin/env bash
set -euo pipefail

readonly target="${GEMFORGE_DEPLOY_TARGET:?GEMFORGE_DEPLOY_TARGET is required}"

if [[ "$target" == "local" ]]; then
  exit 0
fi

pnpm exec gemforge verify "$target"
