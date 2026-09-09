.DEFAULT_GOAL := help

.PHONY: help build test run debug
help:		## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build:	## Build the project (defaults to mainnet)
	pnpm run build
b: build

test:	## Run the tests
	pnpm run test
t: test

deploy-local:	## Deploy to a local Anvil network
	pnpm run deploy:local
dl:	deploy-local
