.DEFAULT_GOAL := help

.PHONY: help build test run debug deploy-local deploy-testnet-dry deploy-mainnet-dry
help:		## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build:	## Build the project (defaults to mainnet)
	pnpm run build
b: build

test:	## Run the tests
	pnpm run test
t: test

deploy-local:	## Deploy to a local Anvil network
	pnpm run deploy:local
dl:	deploy-local

deploy-testnet-dry:	## Preview a testnet deploy without sending transactions
	pnpm run deploy:testnet:dry
dtd: deploy-testnet-dry

deploy-mainnet-test-dry:	## Preview a mainnet-test deploy without sending transactions
	pnpm run deploy:mainnet_test:dry

deploy-mainnet-live-dry:	## Preview a mainnet-live deploy without sending transactions
	pnpm run deploy:mainnet_live:dry

deploy-mainnet-test:	## Deploy mainnet-test smart contract
	pnpm run deploy:mainnet_test

deploy-mainnet-live:	## Deploy mainnet-live smart contract
	pnpm run deploy:mainnet_live

java-local:	## Generate java bindings and publish to local maven repository
	cd bindings/java && ./gradlew publishToMavenLocal
jl: publish-java-locally

fork-mainnet:	## Fork Ethereum Mainnet using Anvil
	anvil --fork-url $ETH_MAINNET_RPC_URL
