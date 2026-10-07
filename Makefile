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

deploy-mainnet-dry:	## Preview a mainnet deploy without sending transactions
	pnpm run deploy:mainnet:dry
dmd: deploy-mainnet-dry

java-local:	## Generate java bindings and publish to local maven repository
	cd bindings/java && ./gradlew publishToMavenLocal
jl: publish-java-locally
