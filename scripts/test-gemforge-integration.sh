#!/usr/bin/env bash
set -euo pipefail
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

cd "$(dirname "$0")/.."

readonly RPC_URL="http://127.0.0.1:18545"
readonly MNEMONIC="test test test test test test test test test test test junk"
readonly DEPLOYER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
readonly UPGRADER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
readonly UPGRADER_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
readonly BOSS="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
readonly ADMIN="0x90F79bf6EB2c4f870365E785982E1f101E93b906"
readonly WORKER="0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"
readonly APPROVER_1="0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc"
readonly APPROVER_2="0x976EA74026E726554dB657fA54763abd0C3a0aa9"
readonly CREATE3_SALT="0x1111111111111111111111111111111111111111111111111111111111111111"
readonly GEMFORGE_CONFIG="test/integration/gemforge.config.cjs"

test_dir="$(mktemp -d)"
deployments="$test_dir/deployments.json"
anvil_pid=""

cleanup() {
  if [[ -n "$anvil_pid" ]]; then
    kill "$anvil_pid" 2>/dev/null || true
    wait "$anvil_pid" 2>/dev/null || true
  fi
  # Leave the checked-in generated ABI in its production shape after fixture builds.
  pnpm build >/dev/null 2>&1 || true
  rm -rf "$test_dir"
}
trap cleanup EXIT

fail() {
  echo "integration test failed: $*" >&2
  exit 1
}

normalize() {
  tr '[:upper:]' '[:lower:]'
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label: expected $expected, got $actual"
}

assert_address_eq() {
  local expected actual
  expected="$(printf '%s' "$1" | normalize)"
  actual="$(printf '%s' "$2" | normalize)"
  assert_eq "$expected" "$actual" "$3"
}

run_fixture() {
  local fixture="$1"
  shift
  env \
    GEMFORGE_INTEGRATION_FIXTURE="$fixture" \
    GEMFORGE_LOCAL_RPC_URL="$RPC_URL" \
    GEMFORGE_DEPLOYMENTS_PATH="$deployments" \
    ONRE_CREATE3_SALT="$CREATE3_SALT" \
    ONRE_BOSS="$BOSS" \
    ONRE_ADMIN="$ADMIN" \
    ONRE_WORKER="$WORKER" \
    ONRE_UPGRADER="$UPGRADER" \
    ONRE_APPROVER_1="$APPROVER_1" \
    ONRE_APPROVER_2="$APPROVER_2" \
    "$@"
}

build_fixture() {
  run_fixture "$1" pnpm exec gemforge build --config "$GEMFORGE_CONFIG" >/dev/null
}

deploy_fixture() {
  run_fixture "$1" pnpm exec gemforge deploy local --config "$GEMFORGE_CONFIG" 2>&1
}

call() {
  cast call --rpc-url "$RPC_URL" "$@"
}

send() {
  cast send --rpc-url "$RPC_URL" --private-key "$UPGRADER_KEY" "$@" >/dev/null
}

manual_cut_data() {
  printf '%s\n' "$1" | sed -n 's/^GEMFORGE: Tx data: //p' | tail -1
}

anvil --silent --port 18545 --mnemonic "$MNEMONIC" >"$test_dir/anvil.log" 2>&1 &
anvil_pid=$!
for _ in $(seq 1 50); do
  if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1 || fail "Anvil did not start"

echo "Deploying fixture v1 through CREATE3..."
build_fixture v1
fresh_output="$(deploy_fixture v1)"
printf '%s\n' "$fresh_output"
printf '%s\n' "$fresh_output" | grep -q 'CREATE3 salt (specified)' || fail "fresh deployment did not use CREATE3"
[[ -s "$deployments" ]] || fail "Gemforge did not create the deployment record"

diamond="$(node -e '
const data = require(process.argv[1]);
const proxy = data.local.contracts.find(({ name }) => name === "DiamondProxy");
if (!proxy) process.exit(1);
process.stdout.write(proxy.onChain.address);
' "$deployments")"
[[ "$(cast code --rpc-url "$RPC_URL" "$diamond")" != "0x" ]] || fail "diamond has no runtime code"

recorded_sender="$(node -e '
const data = require(process.argv[1]);
process.stdout.write(data.local.contracts.find(({ name }) => name === "DiamondProxy").sender);
' "$deployments")"
assert_address_eq "$DEPLOYER" "$recorded_sender" "deployment-record sender"

assert_address_eq "$BOSS" "$(call "$diamond" 'boss()(address)')" "initializer boss"
default_admin_role="$(call "$diamond" 'DEFAULT_ADMIN_ROLE()(bytes32)')"
admin_role="$(call "$diamond" 'ADMIN_ROLE()(bytes32)')"
worker_role="$(call "$diamond" 'WORKER_ROLE()(bytes32)')"
upgrader_role="$(call "$diamond" 'UPGRADER_ROLE()(bytes32)')"
assert_eq "true" "$(call "$diamond" 'hasRole(bytes32,address)(bool)' "$default_admin_role" "$BOSS")" "boss role"
assert_eq "true" "$(call "$diamond" 'hasRole(bytes32,address)(bool)' "$admin_role" "$ADMIN")" "admin role"
assert_eq "true" "$(call "$diamond" 'hasRole(bytes32,address)(bool)' "$worker_role" "$WORKER")" "worker role"
assert_eq "true" "$(call "$diamond" 'hasRole(bytes32,address)(bool)' "$upgrader_role" "$UPGRADER")" "final upgrader role"
assert_eq "false" "$(call "$diamond" 'hasRole(bytes32,address)(bool)' "$upgrader_role" "$DEPLOYER")" "bootstrap upgrader handoff"
app_config="$(call "$diamond" 'appConfig()(bool,address,address)')"
printf '%s\n' "$app_config" | grep -qi "$APPROVER_1" || fail "initializer approver 1 was not stored"
printf '%s\n' "$app_config" | grep -qi "$APPROVER_2" || fail "initializer approver 2 was not stored"

zero_address="0x0000000000000000000000000000000000000000"
protected_signatures=(
  'diamondCut((address,uint8,bytes4[])[],address,bytes)'
  'facets()'
  'facetAddress(bytes4)'
  'facetAddresses()'
  'facetFunctionSelectors(address)'
  'supportsInterface(bytes4)'
  'hasRole(bytes32,address)'
  'getRoleAdmin(bytes32)'
  'grantRole(bytes32,address)'
  'revokeRole(bytes32,address)'
  'renounceRole(bytes32,address)'
)
protected_facets=()
for signature in "${protected_signatures[@]}"; do
  selector="$(cast sig "$signature")"
  facet="$(call "$diamond" 'facetAddress(bytes4)(address)' "$selector")"
  [[ "$(printf '%s' "$facet" | normalize)" != "$(printf '%s' "$zero_address" | normalize)" ]] \
    || fail "protected selector has no facet: $signature"
  protected_facets+=("$facet")
done

send "$diamond" 'setIntegrationValue(uint256)' 42
assert_eq "42" "$(call "$diamond" 'integrationValue()(uint256)')" "initial integration state"
assert_eq "1" "$(call "$diamond" 'integrationVersion()(uint256)')" "v1 selector"

echo "Generating and executing v2 manual-cut calldata..."
build_fixture v2
v2_output="$(deploy_fixture v2)"
printf '%s\n' "$v2_output"
printf '%s\n' "$v2_output" | grep -q 'Add = 1, Replace = 1, Remove = 0' || fail "v2 did not exercise add and replace"
v2_data="$(manual_cut_data "$v2_output")"
[[ "$v2_data" == 0x* ]] || fail "Gemforge did not output v2 manual-cut calldata"
send "$diamond" --data "$v2_data"
assert_eq "2" "$(call "$diamond" 'integrationVersion()(uint256)')" "replaced selector"
assert_eq "22" "$(call "$diamond" 'addedInV2()(uint256)')" "added selector"
assert_eq "42" "$(call "$diamond" 'integrationValue()(uint256)')" "state after v2"

echo "Generating and executing v3 multi-selector removal calldata..."
build_fixture v3
v3_output="$(deploy_fixture v3)"
printf '%s\n' "$v3_output"
printf '%s\n' "$v3_output" | grep -q 'Remove = 1' || fail "v3 did not generate a removal cut"
v3_data="$(manual_cut_data "$v3_output")"
[[ "$v3_data" == 0x* ]] || fail "Gemforge did not output v3 manual-cut calldata"
send "$diamond" --data "$v3_data"
assert_eq "3" "$(call "$diamond" 'integrationVersion()(uint256)')" "v3 selector"
assert_eq "42" "$(call "$diamond" 'integrationValue()(uint256)')" "state after v3"

for signature in 'legacyOne()' 'legacyTwo()'; do
  selector="$(cast sig "$signature")"
  assert_address_eq "$zero_address" "$(call "$diamond" 'facetAddress(bytes4)(address)' "$selector")" "removed $signature"
done

# Successful upgrades plus unchanged initialized roles prove init calldata was not replayed.
assert_eq "true" "$(call "$diamond" 'hasRole(bytes32,address)(bool)' "$upgrader_role" "$UPGRADER")" "upgrader after upgrades"
assert_eq "false" "$(call "$diamond" 'hasRole(bytes32,address)(bool)' "$upgrader_role" "$DEPLOYER")" "bootstrap role after upgrades"
for index in "${!protected_signatures[@]}"; do
  signature="${protected_signatures[$index]}"
  selector="$(cast sig "$signature")"
  facet="$(call "$diamond" 'facetAddress(bytes4)(address)' "$selector")"
  assert_address_eq "${protected_facets[$index]}" "$facet" "protected $signature selector"
done

recorded_diamond="$(node -e '
const data = require(process.argv[1]);
process.stdout.write(data.local.contracts.find(({ name }) => name === "DiamondProxy").onChain.address);
' "$deployments")"
assert_address_eq "$diamond" "$recorded_diamond" "deployment record after upgrades"

echo "Gemforge Anvil integration test passed for $diamond"
