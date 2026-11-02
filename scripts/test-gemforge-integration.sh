#!/usr/bin/env bash
set -euo pipefail
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

cd "$(dirname "$0")/.."

pnpm build
pnpm exec gemforge deploy mainnet_live --dry
