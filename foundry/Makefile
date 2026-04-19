.PHONY: build deploy deploy-and-generate-abis deploy-abis deploy-full generate-abis get-address account chain compile flatten fork format lint test verify

DEPLOY_SCRIPT ?= script/Deploy.s.sol

# setup wallet for anvil
setup-anvil-wallet:
	@rm -f ~/.foundry/keystores/scaffold-eth-default 2>/dev/null || true
	@rm -rf broadcast/Deploy.s.sol/31337 2>/dev/null || true
	cast wallet import --private-key 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6 --unsafe-password 'localhost' scaffold-eth-default

# Start local chain
chain: setup-anvil-wallet
	anvil

# Start a fork
fork: setup-anvil-wallet
	anvil --fork-url ${FORK_URL} --chain-id 31337

# Deploy the contracts
deploy:
	@if [ ! -f "$(DEPLOY_SCRIPT)" ]; then echo "Error: Deploy script '$(DEPLOY_SCRIPT)' not found"; exit 1; fi
	@if [ "$(RPC_URL)" = "localhost" ]; then \
		if [ "$(ETH_KEYSTORE_ACCOUNT)" = "scaffold-eth-default" ]; then \
			forge script $(DEPLOY_SCRIPT) --rpc-url localhost --account $(ETH_KEYSTORE_ACCOUNT) --password localhost --broadcast --legacy --ffi $(DEPLOY_EXTRA_ARGS); \
		else \
			forge script $(DEPLOY_SCRIPT) --rpc-url localhost --account $(ETH_KEYSTORE_ACCOUNT) --broadcast --legacy --ffi $(DEPLOY_EXTRA_ARGS); \
		fi; \
	else \
		forge script $(DEPLOY_SCRIPT) --rpc-url $(RPC_URL) --account $(ETH_KEYSTORE_ACCOUNT) --broadcast --legacy --ffi $(DEPLOY_EXTRA_ARGS); \
	fi

# Deploy and generate ABIs
deploy-and-generate-abis: deploy generate-abis

# Deploy, generate ABIs, and commit to abi repo
deploy-abis: 
	@echo ""
	@echo "📝 Checking for ABI changes in submodule..."
	@if [ -d "abi/.git" ] && [ -n "$$(cd abi && git status --porcelain)" ]; then \
		echo "✅ Committing ABI changes to submodule..."; \
		cd abi && \
		git add -A && \
		git commit -m "Update ABIs from deployment" && \
		git push && \
		cd .. && \
		git add abi && \
		echo "✅ ABI submodule committed and pushed"; \
		echo "⚠️  Parent repo submodule reference staged. Run 'git commit' to finalize."; \
	else \
		echo "ℹ️  No ABI changes detected"; \
	fi

# Full deployment (used by yarn deploy)
deploy-full: deploy generate-abis deploy-abis

# Generate TypeScript ABIs
generate-abis:
	node scripts-js/generateTsAbis.js

# List account
account:
	@node scripts-js/checkAccountBalance.js

# Get address of a keystore
get-address:
	@cast wallet address --account $(ACCOUNT_NAME)

# Compile contracts
compile:
	forge compile

# Flatten contracts
flatten:
	forge flatten

# Format code
format:
	forge fmt && prettier --write ./scripts-js/**/*.js

# Lint code
lint:
	forge fmt --check && yarn exec prettier --check ./scripts-js/**/*.js

# Run tests
test:
	forge test

# Verify contracts
verify:
	forge script script/VerifyAll.s.sol --ffi --rpc-url $(RPC_URL)

