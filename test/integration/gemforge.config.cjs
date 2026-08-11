const base = require('../../gemforge.config.cjs')

const fixtures = {
  v1: 'test/integration/facets/GemforgeIntegrationFacetV1.sol',
  v2: 'test/integration/facets/GemforgeIntegrationFacetV2.sol',
  v3: 'test/integration/facets/GemforgeIntegrationFacetV3.sol',
}

const fixtureName = required('GEMFORGE_INTEGRATION_FIXTURE')
const fixtureFacet = fixtures[fixtureName]
if (!fixtureFacet) {
  throw new Error(`Unknown GEMFORGE_INTEGRATION_FIXTURE: ${fixtureName}`)
}

module.exports = {
  ...base,
  commands: {
    ...base.commands,
    build: `${base.commands.build} ${fixtureFacet}`,
  },
  paths: {
    ...base.paths,
    src: {
      ...base.paths.src,
      facets: [...base.paths.src.facets, fixtureFacet],
    },
    generated: {
      ...base.paths.generated,
      deployments: required('GEMFORGE_DEPLOYMENTS_PATH'),
    },
  },
  networks: {
    ...base.networks,
    local: {
      ...base.networks.local,
      rpcUrl: required('GEMFORGE_LOCAL_RPC_URL'),
    },
  },
  targets: {
    ...base.targets,
    local: {
      ...base.targets.local,
      create3Salt: required('ONRE_CREATE3_SALT'),
      // Exercise the same calldata-only upgrade path used by mainnet.
      upgrades: { manualCut: true },
    },
  },
}

function required(name) {
  const value = process.env[name]
  if (!value) {
    throw new Error(`Missing integration-test environment variable: ${name}`)
  }
  return value
}
