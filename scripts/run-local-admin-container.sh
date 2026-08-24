#!/usr/bin/env bash
set -Eeuo pipefail

readonly rpc_url="http://127.0.0.1:8545"
readonly ui_port="5173"
readonly anvil_config="/tmp/onre-anvil-config.json"

anvil_pid=""
ui_pid=""

cleanup() {
  rm -f "$anvil_config"
  [[ -n "$ui_pid" ]] && kill "$ui_pid" 2>/dev/null || true
  [[ -n "$anvil_pid" ]] && kill "$anvil_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Starting Anvil on http://127.0.0.1:8545"
anvil \
  --host 0.0.0.0 \
  --port 8545 \
  --chain-id 31337 \
  --allow-origin 'http://localhost:5173' \
  --accounts 6 \
  --mnemonic-random 12 \
  --config-out "$anvil_config" \
  --quiet \
  >/tmp/anvil.log 2>&1 &
anvil_pid=$!

for _ in $(seq 1 60); do
  if cast chain-id --rpc-url "$rpc_url" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$anvil_pid" 2>/dev/null; then
    cat /tmp/anvil.log
    exit 1
  fi
  sleep 1
done
cast chain-id --rpc-url "$rpc_url" >/dev/null

readarray -t local_accounts < <(node -e "const config=require('$anvil_config'); console.log([...config.available_accounts, config.private_keys[0]].join('\n'))")
if [[ "${#local_accounts[@]}" -ne 7 ]]; then
  echo "Anvil did not generate the expected local accounts"
  exit 1
fi

export ONRE_BOSS="${local_accounts[0]}"
export ONRE_ADMIN="${local_accounts[1]}"
export ONRE_WORKER="${local_accounts[2]}"
export ONRE_UPGRADER="${local_accounts[3]}"
export ONRE_APPROVER_1="${local_accounts[4]}"
readonly permissionless_account="${local_accounts[5]}"
export ONRE_LOCAL_PRIVATE_KEY="${local_accounts[6]}"
unset local_accounts
rm -f "$anvil_config"

echo "Generated disposable boss $ONRE_BOSS"
echo "Deploying a fresh local OnRe Diamond"
pnpm exec gemforge deploy local --new
unset ONRE_LOCAL_PRIVATE_KEY

diamond_address="$(node -e "const deployment=require('./gemforge.deployments.json').local; const diamond=deployment?.contracts?.find((entry)=>entry.name==='DiamondProxy')?.onChain?.address; if (!diamond) process.exit(1); process.stdout.write(diamond)")"

echo "Configuring permissionless settlement account $permissionless_account"
cast send --rpc-url "$rpc_url" --unlocked --from "$ONRE_BOSS" \
  "$diamond_address" "setPermissionlessSettlementAccount(address)" "$permissionless_account" >/dev/null

echo "Building the admin UI for Diamond $diamond_address"
forge build admin-ui/contracts/LocalAssetToken.sol lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol
pnpm exec vite build admin-ui

echo "OnRe Admin: http://localhost:5173"
echo "Anvil RPC:   http://localhost:8545"
pnpm exec vite preview admin-ui --host 0.0.0.0 --port "$ui_port" --strictPort &
ui_pid=$!
wait "$ui_pid"
