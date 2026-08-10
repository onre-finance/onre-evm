require('dotenv').config()

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
    ],
  },
  hooks: {
    preBuild: '',
    postBuild: '',
    preDeploy: '',
    postDeploy: '',
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
    deployer: {
      type: 'private-key',
      config: {
        key: () => process.env.PRIVATE_KEY,
      },
    },
  },
  networks: {
    local: {
      rpcUrl: 'http://localhost:8545',
    },
    sepolia: {
      rpcUrl: () => process.env.SEPOLIA_RPC_URL,
      contractVerification: {
        foundry: {
          apiKey: () => process.env.ETHERSCAN_API_KEY,
          apiUrl: 'https://api-sepolia.etherscan.io/api',
        },
      },
    },
    mainnet: {
      rpcUrl: () => process.env.MAINNET_RPC_URL,
      contractVerification: {
        foundry: {
          apiKey: () => process.env.ETHERSCAN_API_KEY,
          apiUrl: 'https://api.etherscan.io/api',
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
      network: 'sepolia',
      wallet: 'deployer',
      initArgs: [initArgs()],
      // CREATE3 keeps the diamond at the same address on every chain. Set
      // ONRE_CREATE3_SALT to reuse a known address; omit it and Gemforge
      // randomises the salt on a fresh deployment.
      create3Salt: process.env.ONRE_CREATE3_SALT,
    },
    mainnet: {
      network: 'mainnet',
      wallet: 'deployer',
      initArgs: [initArgs()],
      create3Salt: process.env.ONRE_CREATE3_SALT,
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
