require('dotenv').config()

const { execFileSync } = require('child_process')
const { randomBytes } = require('crypto')

/**
 * Gemforge configuration for the OnRe Diamond.
 *
 * Docs: https://gemforge.xyz/configuration/
 *
 * Notes specific to this project:
 *
 * - `paths.lib.diamond` points at our own `src/diamond`, not at
 *   `lib/diamond-2-hardhat`. The OnRe diamond core is a hardened descendant of
 *   mudgen/diamond-3-hardhat (ERC-7201 storage namespace, UPGRADER_ROLE-gated
 *   cuts, custom errors, immutable `diamondCut` selector). It is laid out in the
 *   `contracts/{libraries,facets,interfaces}` shape Gemforge's templates import.
 *   It stays under `src/` so `forge build --sizes`, `forge coverage` and Slither
 *   keep treating it as first-party source.
 *
 * - `generator.proxy.template` overrides the stock DiamondProxy, which assumes
 *   an ERC-173 `OwnershipFacet`. See `templates/DiamondProxy.sol`.
 *
 * - `coreFacets` omits `OwnershipFacet` for the same reason.
 */
module.exports = {
  version: 2,
  solc: {
    license: 'MIT',
    version: '0.8.35',
  },
  commands: {
    build: 'forge build --sizes src',
  },
  paths: {
    artifacts: 'out',
    src: {
      // Application facets only. The core diamond facets live under
      // `paths.lib.diamond` and are declared in `diamond.coreFacets` below.
      facets: ['src/facets/*Facet.sol'],
    },
    generated: {
      solidity: 'src/generated',
      support: '.gemforge',
      deployments: 'gemforge.deployments.json',
    },
    lib: {
      diamond: 'src/diamond',
    },
  },
  artifacts: {
    format: 'foundry',
  },
  generator: {
    proxy: {
      template: 'templates/DiamondProxy.sol',
    },
    proxyInterface: {
      // Facet methods take/return these structs, so IDiamondProxy needs them in scope.
      imports: ['src/types/OnReTypes.sol'],
    },
  },
  diamond: {
    publicMethods: false,
    // Runs once, inside the first diamondCut of a new deployment.
    init: {
      contract: 'OnReDiamondInit',
      function: 'init',
    },
    // Installed by DiamondProxy's constructor; never replaced or removed by an upgrade.
    coreFacets: ['DiamondCutFacet', 'DiamondLoupeFacet'],
    protectedMethods: [
      '0x1f931c1c', // DiamondCutFacet.diamondCut()
      '0x7a0ed627', // DiamondLoupeFacet.facets()
      '0xcdffacc6', // DiamondLoupeFacet.facetAddress()
      '0x52ef6b2c', // DiamondLoupeFacet.facetAddresses()
      '0xadfca15e', // DiamondLoupeFacet.facetFunctionSelectors()
      '0x01ffc9a7', // DiamondLoupeFacet.supportsInterface()
      // OnReDiamondInit permanently advertises IAccessControl through ERC-165.
      // Prevent an omitted facet from making Gemforge remove that interface.
      '0x91d14854', // OnReAccessControlFacet.hasRole(bytes32,address)
      '0x248a9ca3', // OnReAccessControlFacet.getRoleAdmin(bytes32)
      '0x2f2ff15d', // OnReAccessControlFacet.grantRole(bytes32,address)
      '0xd547741f', // OnReAccessControlFacet.revokeRole(bytes32,address)
      '0x36568abe', // OnReAccessControlFacet.renounceRole(bytes32,address)
    ],
  },
  hooks: {
    preBuild: '',
    postBuild: '',
    preDeploy: '',
    // Deployment records are saved before this hook runs, so verification
    // includes the proxy, core facets, application facets, and initializer.
    postDeploy: 'bash hooks/verify-gemforge-deployment.sh',
  },
  wallets: {
    // Anvil's first default account.
    local: {
      type: 'mnemonic',
      config: {
        words: 'test test test test test test test test test test test junk',
        index: 0,
      },
    },
    // Signs with a Foundry keystore (`cast wallet import <name> --interactive`).
    // Gemforge only accepts raw keys, so the keystore is decrypted on demand.
    deployer: {
      type: 'private-key',
      config: { key: () => deployerKey() },
    },
  },
  networks: {
    local: { rpcUrl: 'http://localhost:8545', },
    baseSepolia: {
      rpcUrl: () => process.env.BASE_SEPOLIA_RPC_URL,
      contractVerification: {
        foundry: {
          // Gemforge passes this to `forge verify-contract --verifier-api-key`.
          apiKey: () => process.env.ETHERSCAN_API_KEY,
          apiUrl: 'https://api.etherscan.io/v2/api?chainid=84532',
          verifier: 'etherscan',
          chainId: 84532,
        },
      },
    },
    mainnet: {
      rpcUrl: () => process.env.ETH_MAINNET_RPC_URL,
      contractVerification: {
        foundry: {
          // Gemforge passes this to `forge verify-contract --verifier-api-key`.
          apiKey: () => process.env.ETHERSCAN_API_KEY,
          apiUrl: 'https://api.etherscan.io/v2/api?chainid=1',
          verifier: 'etherscan',
          chainId: 1,
        },
      },
    },
  },
  targets: {
    local: {
      network: 'local',
      wallet: 'local',
      initArgs: [initArgs()],
    },
    testnet: {
      network: 'baseSepolia',
      wallet: 'deployer',
      initArgs: [initArgs()],
      // CREATE3 keeps the diamond at the same address on every chain. Set
      // ONRE_CREATE3_SALT to reuse a known address; omit it and Gemforge
      // randomises the salt on a fresh deployment.
      ...(process.env.ONRE_CREATE3_SALT ? { create3Salt: process.env.ONRE_CREATE3_SALT } : {}),
      upgrades: {
        // Upgrade authority is held by a multisig, not by a hot deployer key.
        // Gemforge prints the diamondCut() calldata instead of sending it.
        manualCut: true,
      },
    },
    mainnet: {
      network: 'mainnet',
      wallet: 'deployer',
      initArgs: [initArgs()],
      ...(process.env.ONRE_CREATE3_SALT ? { create3Salt: process.env.ONRE_CREATE3_SALT } : {}),
      upgrades: {
        // Upgrade authority is held by a multisig, not by a hot deployer key.
        // Gemforge prints the diamondCut() calldata instead of sending it.
        manualCut: true,
      },
    },
  },
}

/**
 * Builds the `OnReTypes.InitializeParams` tuple passed to `OnReDiamondInit.init`.
 *
 * Only read on a brand-new deployment; upgrades never re-run the initializer.
 * ONRE_APPROVER_1 / ONRE_APPROVER_2 are optional (at most two are accepted).
 */
function initArgs() {
  const approvers = [process.env.ONRE_APPROVER_1, process.env.ONRE_APPROVER_2].filter(Boolean)

  return [
    process.env.ONRE_BOSS,
    process.env.ONRE_ADMIN,
    process.env.ONRE_WORKER,
    process.env.ONRE_UPGRADER,
    approvers,
  ]
}

let cachedDeployerKey

/**
 * Returns the deployment wallet's private key, decrypted from the Foundry
 * keystore named by ONRE_DEPLOYER_ACCOUNT (default `deployer`).
 *
 * Only called by commands that need a signer (deploy, query, verify), so
 * `gemforge build` never prompts. cast asks for the keystore password on the
 * terminal, or reads it from CAST_UNSAFE_PASSWORD for non-interactive runs.
 * PRIVATE_KEY, if set, bypasses the keystore.
 *
 * Never run a real deploy with `-v`: gemforge's trace output logs the key in
 * plaintext. Dry runs are safe, since they use a throwaway key.
 */
function deployerKey() {
  // `gemforge deploy --dry` sends nothing, so it only needs some signer to read
  // the live diamond. A throwaway key skips the password prompt and keeps the
  // real key out of `-v` trace output.
  if (isDryRun()) {
    if (!cachedDeployerKey) {
      console.warn('Dry run: signing with a throwaway key, not the deployment keystore.')
      cachedDeployerKey = `0x${randomBytes(32).toString('hex')}`
    }
    return cachedDeployerKey
  }

  if (process.env.PRIVATE_KEY) return process.env.PRIVATE_KEY

  if (!cachedDeployerKey) {
    const account = process.env.ONRE_DEPLOYER_ACCOUNT || 'deployer'
    const out = execFileSync('cast', ['wallet', 'decrypt-keystore', account], {
      stdio: ['inherit', 'pipe', 'inherit'],
    }).toString()
    const match = out.match(/0x[0-9a-fA-F]{64}/)
    if (!match) throw new Error(`Could not read a private key from Foundry keystore "${account}"`)
    cachedDeployerKey = match[0]
  }
  return cachedDeployerKey
}

function isDryRun() {
  return process.argv.includes('deploy') && process.argv.some(a => a === '--dry' || a === '-d')
}
