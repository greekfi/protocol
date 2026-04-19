#!/bin/bash
set -e

# ============================================
# YieldVault Demo Setup
# Deploys to a Base-forked anvil with BebopSettlement
# ============================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RPC=http://localhost:8545

# Your wallet address (LP + operator)
OPERATOR=${1:-0x5b5e727A7a78603ebF4f1652488830FC0843Df45}

echo "=== Step 1: Start forked anvil ==="
echo "Run in another terminal:"
echo "  cd $SCRIPT_DIR && make fork FORK_URL=https://mainnet.base.org"
echo ""
echo "Press Enter when anvil is running..."
read -r

echo "=== Step 2: Deploy contracts ==="
cd "$SCRIPT_DIR"
yarn deploy

echo "=== Step 3: Parse deployed addresses ==="
# Extract addresses from the broadcast file
BROADCAST="$SCRIPT_DIR/broadcast/Deploy.s.sol/31337/run-latest.json"
if [ ! -f "$BROADCAST" ]; then
    echo "Error: broadcast file not found at $BROADCAST"
    exit 1
fi

# Parse contract addresses from broadcast (CREATE transactions)
FACTORY=$(python3 -c "
import json
with open('$BROADCAST') as f:
    data = json.load(f)
for tx in data['transactions']:
    if tx.get('contractName') == 'OptionFactory':
        print(tx['contractAddress'])
        break
")
VAULT=$(python3 -c "
import json
with open('$BROADCAST') as f:
    data = json.load(f)
for tx in data['transactions']:
    if tx.get('contractName') == 'YieldVault':
        print(tx['contractAddress'])
        break
")
SHAKY=$(python3 -c "
import json
with open('$BROADCAST') as f:
    data = json.load(f)
for tx in data['transactions']:
    if tx.get('contractName') == 'ShakyToken':
        print(tx['contractAddress'])
        break
")
STABLE=$(python3 -c "
import json
with open('$BROADCAST') as f:
    data = json.load(f)
for tx in data['transactions']:
    if tx.get('contractName') == 'StableToken':
        print(tx['contractAddress'])
        break
")

echo "  OptionFactory: $FACTORY"
echo "  YieldVault:    $VAULT"
echo "  ShakyToken:    $SHAKY"
echo "  StableToken:   $STABLE"
echo "  Operator:      $OPERATOR"

echo ""
echo "=== Step 4: Run DemoSetup ==="
forge script script/DemoSetup.s.sol \
    --sig "run(address,address,address,address,address)" \
    "$FACTORY" "$VAULT" "$SHAKY" "$STABLE" "$OPERATOR" \
    --broadcast --rpc-url $RPC \
    --account scaffold-eth-default --password localhost --legacy

echo ""
echo "=== Done! ==="
echo "Next:"
echo "  cd .. && yarn start"
echo "  Open http://localhost:3000/vault"
