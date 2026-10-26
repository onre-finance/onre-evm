// Runs setup, settlement approvals, named liquidity deposits, vault withdrawals, and production buys/sells on a disposable Anvil fork.
// Usage: node scripts/test-buy-offers-anvil.cjs [Ethereum RPC URL]
const fs = require('node:fs')
const path = require('node:path')
const net = require('node:net')
const assert = require('node:assert/strict')
const { spawn, execFileSync } = require('node:child_process')

const root = path.resolve(__dirname, '..')
const upstream = process.argv[2] || process.env.ETH_MAINNET_RPC_URL || 'https://ethereum-rpc.publicnode.com'
const environment = 'ethereum-mainnet-live'
const config = JSON.parse(fs.readFileSync(path.join(root, 'script/config', `${environment}.json`)))
const allOffers = Object.entries(config.offers).map(([name, definition]) => ({ name, ...definition }))
const offers = allOffers.filter(offer => offer.flow === 'permissionless' && offer.direction === 'assetToManaged')
const redemptions = allOffers.filter(offer => offer.flow === 'permissionless' && offer.direction === 'managedToAsset')
assert.ok(offers.length > 0)
const first = offers[0]
const managedToken = first.managedToken
const pricerDefinition = config.pricers[first.pricer]
const assetTokens = offers.map(offer => offer.assetToken)
assert.ok(offers.every(offer => offer.managedToken === managedToken && offer.pricer === first.pricer && offer.liquidityVault === 'none'))
const output = path.join(root, '.ignore/buy-offers-anvil')
const zeroAddress = '0x' + '0'.repeat(40)
const max = (2n ** 256n - 1n).toString()
const hex = value => '0x' + BigInt(value).toString(16)
const cast = (...args) => execFileSync('cast', args.map(String), { cwd: root, encoding: 'utf8' }).trim()
const calldata = (signature, ...args) => cast('calldata', signature, ...args)
const words = data => (data.slice(2).match(/.{64}/g) || []).map(word => BigInt('0x' + word))
const id = (seed, types, args) => cast('keccak', cast('abi-encode', `f(bytes32,${types})`, cast('keccak', seed), ...args))
const format = (value, decimals) => `${value / 10n ** BigInt(decimals)}.${(value % 10n ** BigInt(decimals)).toString().padStart(decimals, '0')}`

async function rpc(url, method, params = []) {
  const response = await fetch(url, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }), signal: AbortSignal.timeout(30000),
  })
  const body = await response.json()
  if (body.error) throw Object.assign(new Error(`${method}: ${body.error.message}`), { data: body.error.data })
  return body.result
}

async function command(binary, args, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(binary, args, { cwd: root, env: { ...process.env, ...env } })
    let text = ''
    child.stdout.on('data', data => { text += data })
    child.stderr.on('data', data => { text += data })
    child.on('error', reject)
    child.on('exit', code => code === 0 ? resolve(text) : reject(new Error(text)))
  })
}

async function main() {
  fs.mkdirSync(output, { recursive: true })
  assert.equal(Number(BigInt(await rpc(upstream, 'eth_chainId'))), 1, 'Fork source must be Ethereum mainnet')
  const forkBlock = await rpc(upstream, 'eth_blockNumber')
  const server = net.createServer()
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  const port = server.address().port
  await new Promise(resolve => server.close(resolve))
  const local = `http://127.0.0.1:${port}`
  const anvilLog = fs.openSync(path.join(output, 'anvil.log'), 'w')
  const anvil = spawn('anvil', ['--fork-url', upstream, '--fork-block-number', String(BigInt(forkBlock)), '--port', String(port), '--silent'], {
    cwd: root, stdio: ['ignore', anvilLog, anvilLog],
  })
  const read = (to, data) => rpc(local, 'eth_call', [{ to, data }, 'latest'])
  const balance = async (token, account) => words(await read(token, calldata('balanceOf(address)', account)))[0]
  const vaultBalance = async (vault, token) => words(await read(config.diamond, calldata('configurableVaultBalance(bytes32,address)', vault, token)))[0]
  async function impersonate(account) {
    await rpc(local, 'anvil_impersonateAccount', [account])
    await rpc(local, 'anvil_setBalance', [account, hex(10n ** 20n)])
  }
  async function send(from, to, data) {
    const hash = await rpc(local, 'eth_sendTransaction', [{ from, to, data, gas: '0x989680' }])
    let receipt
    for (let attempt = 0; attempt < 200; attempt++) {
      receipt = await rpc(local, 'eth_getTransactionReceipt', [hash])
      if (receipt) break
      await new Promise(resolve => setTimeout(resolve, 100))
    }
    assert.ok(receipt, `Local transaction was not mined: ${hash}`)
    assert.equal(receipt.status, '0x1', `Local transaction failed: ${hash}`)
    return hash
  }
  async function runScript(script, filename, args = []) {
    const log = await command('forge', ['script', script, ...args, '--rpc-url', local], { ONRE_ENV: environment, NO_COLOR: '1' })
    fs.writeFileSync(path.join(output, filename), log)
    const plain = log.replace(/\x1b\[[0-9;]*m/g, '')
    return [...plain.matchAll(/to:\s*(0x[\da-f]{40})\s+value:\s*0\s+data:\s*(0x[\da-f]*)/gi)]
      .map(match => ({ to: match[1], value: '0', data: match[2] }))
  }
  function batch(filename, safe, transactions) {
    fs.writeFileSync(path.join(output, filename), JSON.stringify({
      version: '1.0', chainId: '1', createdAt: Date.now(),
      meta: { name: 'Production offer setup / liquidity', createdFromSafeAddress: safe, createdFromOwnerAddress: '' },
      transactions: transactions.map(tx => ({ ...tx, contractMethod: null, contractInputsValues: null })),
    }, null, 2) + '\n')
  }

  try {
    for (let attempt = 0; ; attempt++) {
      try { if ((await rpc(local, 'web3_clientVersion')).toLowerCase().includes('anvil')) break } catch {}
      if (attempt >= 100 || anvil.exitCode !== null) throw new Error('Anvil failed to start; inspect .ignore/buy-offers-anvil/anvil.log')
      await new Promise(resolve => setTimeout(resolve, 200))
    }
    console.log(`Anvil fork ready at Ethereum block ${BigInt(forkBlock)}`)
    const setup = await runScript('script/SetupOffers.s.sol', 'setup.log')
    batch('setup.batch.json', config.safe, setup)
    await impersonate(config.safe)
    for (const tx of setup) await send(config.safe, tx.to, tx.data)
    console.log(`Applied ${setup.length} admin setup calls on Anvil`)

    const offerIdFor = offer => id('onre.offer_config', 'address,address,uint8', [
      offer.direction === 'assetToManaged' ? offer.assetToken : offer.managedToken,
      offer.direction === 'assetToManaged' ? offer.managedToken : offer.assetToken,
      { permissioned: 0, permissionless: 1, worker: 2 }[offer.flow],
    ])
    const disabledOffers = allOffers.filter(offer => !offer.enabled)
    const now = await rpc(local, 'eth_getBlockByNumber', ['latest', false])
    for (const definition of allOffers) {
      const offerId = offerIdFor(definition)
      assert.equal(words(await read(config.diamond, calldata('getOfferConfig(bytes32)', offerId)))[10], definition.enabled ? 1n : 0n)
      if (!definition.enabled) {
        const data = calldata('takeOffer((bytes32,uint256,uint256,uint64,(address,uint64),bytes))', `(${offerId},1000000,0,${BigInt(now.timestamp) + 3600n},(${zeroAddress},0),0x)`)
        const disabledError = calldata('OfferConfigDisabledError(bytes32)', offerId)
        const [caller] = await rpc(local, 'eth_accounts')
        await assert.rejects(rpc(local, 'eth_call', [{ from: caller, to: config.diamond, data }, 'latest']), error => error.data === disabledError)
      }
    }
    assert.equal((await runScript('script/SetupOffers.s.sol', 'initial-rerun.log')).length, 0)
    console.log(`PASS: initial setup matches configured enabled states; ${disabledOffers.length} disabled offers reject trades; rerun emits no calls`)

    const approvals = await runScript('script/ApproveSettlementTokens.s.sol', 'approvals.log')
    batch('settlement-approvals.batch.json', config.settlementAccount, approvals)
    await impersonate(config.settlementAccount)
    for (const tx of approvals) await send(config.settlementAccount, tx.to, tx.data)
    console.log(`Applied ${approvals.length} settlement approval calls on Anvil`)

    // Enable only on this disposable Anvil fork to retain buy/sell and withdrawal regression coverage.
    for (const offer of disabledOffers) await send(config.safe, config.diamond, calldata('setOfferConfigEnabled(bytes32,bool)', offerIdFor(offer), true))
    if (disabledOffers.length) console.log(`Temporarily enabled ${disabledOffers.length} offers locally for trade/withdrawal tests`)

    const pricerId = id('onre.pricer', 'address,uint8', [managedToken, 0])
    const pricer = words(await read(config.diamond, calldata('getPricer(bytes32)', pricerId)))
    const index = (Number(pricer[52]) - 1) * 5 // ten fixed vectors, then managed token/denomination/count
    const activation = pricer[index]
    const expected = pricerDefinition.vector
    assert.equal(pricer[index + 1], BigInt(expected.baseTime))
    assert.equal(pricer[index + 2], BigInt(expected.basePrice))
    assert.equal(pricer[index + 3], BigInt(expected.apr))
    assert.equal(pricer[index + 4], BigInt(expected.priceFixDuration))
    const latest = await rpc(local, 'eth_getBlockByNumber', ['latest', false])
    if (activation > BigInt(latest.timestamp)) {
      await rpc(local, 'evm_setNextBlockTimestamp', [Number(activation)])
      await rpc(local, 'evm_mine')
    }

    const [user] = await rpc(local, 'eth_accounts')
    const proceedsByOffer = offers.map(offer => id('onre.configurable_vault', 'uint8,uint64', [1, config.vaults[offer.proceedsVault].instanceId]))
    const feesByOffer = offers.map(offer => id('onre.configurable_vault', 'uint8,uint64', [0, config.vaults[config.feeConfigs[offer.feeConfig].feeVault].instanceId]))
    const transferTopic = cast('keccak', 'Transfer(address,address,uint256)')
    async function fundAsset(asset, recipient, amount, symbol) {
      const candidates = [process.env[`${symbol}_HOLDER`], config.settlementAccount, '0x28C6c06298d514Db089934071355E5743bf21d60'].filter(Boolean)
      let donor
      for (const account of candidates) if (await balance(asset, account) >= amount) { donor = account; break }
      if (!donor) {
        const logs = await rpc(upstream, 'eth_getLogs', [{ address: asset, topics: [transferTopic], fromBlock: hex(BigInt(forkBlock) - 1000n), toBlock: forkBlock }])
        for (const log of logs.reverse()) {
          if (BigInt(log.data) < amount || log.topics.length < 3) continue
          const account = '0x' + log.topics[2].slice(-40)
          if (account === zeroAddress || candidates.some(x => x.toLowerCase() === account)) continue
          candidates.push(account)
          if (await balance(asset, account) >= amount) { donor = account; break }
        }
      }
      assert.ok(donor, `No funded ${symbol} holder found; supply ${symbol}_HOLDER for this fork block`)
      await impersonate(donor)
      await send(donor, asset, calldata('transfer(address,uint256)', recipient, amount))
    }
    async function testVaultWithdrawals() {
      const [, outsider, worker, operator] = await rpc(local, 'eth_accounts')
      const adminRole = await read(config.diamond, calldata('DEFAULT_ADMIN_ROLE()'))
      const unauthorized = cast('sig', 'AccessControlUnauthorizedAccount(address,bytes32)')
      const missingDestination = cast('sig', 'MissingConfigurableVaultDestinationError(bytes32)')
      const expectRevert = (from, data, selector) => assert.rejects(
        rpc(local, 'eth_call', [{ from, to: config.diamond, data }, 'latest']),
        error => typeof error.data === 'string' && error.data.startsWith(selector),
      )
      for (const [account, roleName] of [[worker, 'WORKER_ROLE()'], [operator, 'ADMIN_ROLE()']]) {
        const role = await read(config.diamond, calldata(roleName))
        await send(config.safe, config.diamond, calldata('grantRole(bytes32,address)', role, account))
      }
      for (const account of [outsider, worker, operator]) {
        assert.equal(words(await read(config.diamond, calldata('hasRole(bytes32,address)', adminRole, account)))[0], 0n)
      }
      const kinds = { fee: 0, proceeds: 1, liquidity: 2, bufferReserve: 3 }
      const vaultIds = Object.fromEntries(Object.entries(config.vaults).map(([name, vault]) =>
        [name, id('onre.configurable_vault', 'uint8,uint64', [kinds[vault.kind], vault.instanceId])]))
      const tokens = [...new Set([managedToken, ...assetTokens])]
      const cases = new Map()
      const add = (name, token) => cases.set(`${name}:${token}`, { name, token })
      for (const offer of allOffers) {
        add(config.feeConfigs[offer.feeConfig].feeVault, offer.direction === 'assetToManaged' ? offer.assetToken : offer.managedToken)
        add(offer.proceedsVault, offer.assetToken)
        if (offer.liquidityVault !== 'none') add(offer.liquidityVault, offer.assetToken)
      }
      assert.equal(new Set([...cases.values()].map(test => test.name)).size, Object.keys(config.vaults).length)
      const checks = []
      for (const { name, token } of cases.values()) {
        const snapshot = await rpc(local, 'evm_snapshot')
        try {
          const definition = config.vaults[name]
          const vaultId = vaultIds[name]
          const vault = words(await read(config.diamond, calldata('getConfigurableVault(bytes32)', vaultId)))
          assert.notEqual(BigInt(definition.withdrawalDestination), 0n)
          assert.equal(BigInt(definition.withdrawalDestination), BigInt(config.safe), 'Production vault destination must be the configured admin Safe')
          assert.equal(vault[2], BigInt(definition.withdrawalDestination))
          const restricted = definition.kind === 'liquidity' || definition.kind === 'bufferReserve'
          const caller = restricted ? config.safe : outsider
          if (await vaultBalance(vaultId, token) === 0n) {
            const symbol = token.toLowerCase() === '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48' ? 'USDC' : 'USDG'
            assert.notEqual(token, managedToken, 'Trade should have generated the ONyc fees')
            await fundAsset(token, config.safe, 2n * 10n ** 6n, symbol)
            await send(config.safe, token, calldata('approve(address,uint256)', config.diamond, max))
            await send(config.safe, config.diamond, calldata('depositConfigurableVault(bytes32,address,uint256)', vaultId, token, 2n * 10n ** 6n))
          }
          const amount = await vaultBalance(vaultId, token)
          const partial = amount / 2n
          assert.ok(partial > 0n)
          const withdraw = calldata('withdrawConfigurableVault(bytes32,address,uint256)', vaultId, token, partial)
          const withdrawAll = calldata('withdrawAllConfigurableVault(bytes32,address)', vaultId, token)
          const redirect = calldata('updateConfigurableVault(bytes32,address,uint16)', vaultId, outsider, definition.refillTargetBps)
          for (const account of [outsider, worker, operator]) {
            await expectRevert(account, redirect, unauthorized)
            if (restricted) {
              await expectRevert(account, withdraw, unauthorized)
              await expectRevert(account, withdrawAll, unauthorized)
            }
          }
          const others = []
          for (const otherVault of Object.values(vaultIds)) {
            for (const otherToken of tokens) {
              if (otherVault === vaultId && otherToken === token) continue
              others.push([otherVault, otherToken, await vaultBalance(otherVault, otherToken)])
            }
          }
          const destinationBefore = await balance(token, definition.withdrawalDestination)
          const callerBefore = await balance(token, outsider)
          const diamondBefore = await balance(token, config.diamond)
          // Appended recipient data cannot replace the destination read from vault storage.
          const recipientSuffix = cast('abi-encode', 'f(address)', outsider).slice(2)
          await send(caller, config.diamond, withdraw + recipientSuffix)
          assert.equal(await vaultBalance(vaultId, token), amount - partial)
          assert.equal(await balance(token, definition.withdrawalDestination), destinationBefore + partial)
          assert.equal(await balance(token, outsider), callerBefore)
          await send(caller, config.diamond, withdrawAll + recipientSuffix)
          assert.equal(await vaultBalance(vaultId, token), 0n)
          assert.equal(await balance(token, definition.withdrawalDestination), destinationBefore + amount)
          assert.equal(await balance(token, outsider), callerBefore)
          assert.equal(await balance(token, config.diamond), diamondBefore - amount)
          for (const [otherVault, otherToken, before] of others) assert.equal(await vaultBalance(otherVault, otherToken), before)

          // The default admin can deliberately change the destination; zero blocks withdrawals.
          await send(config.safe, token, calldata('approve(address,uint256)', config.diamond, max))
          await send(config.safe, config.diamond, calldata('depositConfigurableVault(bytes32,address,uint256)', vaultId, token, 1))
          await send(config.safe, config.diamond, calldata('updateConfigurableVault(bytes32,address,uint16)', vaultId, zeroAddress, definition.refillTargetBps))
          await expectRevert(caller, withdrawAll, missingDestination)
          assert.equal(await vaultBalance(vaultId, token), 1n)
          await send(config.safe, config.diamond, redirect)
          const oldDestinationBefore = await balance(token, definition.withdrawalDestination)
          await send(caller, config.diamond, withdrawAll)
          assert.equal(await balance(token, outsider), callerBefore + 1n)
          assert.equal(await balance(token, definition.withdrawalDestination), oldDestinationBefore)
          checks.push({ name, kind: definition.kind, vaultId, token, destination: definition.withdrawalDestination, withdrawn: amount.toString(), caller, partialAndFull: true, recipientOverridePrevented: true, otherVaultsAndTokensUnchanged: true, unauthorizedUpdatesRejected: true, liquidityAccessChecked: restricted, adminCanChangeDestination: true, zeroDestinationBlocksWithdrawal: true })
          console.log(`PASS: ${name} / ${token}: partial/full withdrawals only to ${definition.withdrawalDestination}; permissions, isolation, and admin destination changes verified`)
        } finally {
          assert.equal(await rpc(local, 'evm_revert', [snapshot]), true)
        }
      }
      fs.writeFileSync(path.join(output, 'withdrawals.json'), JSON.stringify(checks, null, 2) + '\n')
      return checks
    }
    const results = []
    const initialProceeds = await Promise.all(assetTokens.map((asset, index) => vaultBalance(proceedsByOffer[index], asset)))

    for (let n = 0; n < assetTokens.length; n++) {
      const asset = assetTokens[n]
      const proceeds = proceedsByOffer[n]
      const fees = feesByOffer[n]
      const definition = offers[n]
      const symbol = asset.toLowerCase() === '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48' ? 'USDC' : 'USDG'
      const decimals = Number(words(await read(asset, calldata('decimals()')))[0])
      const amount = 1000n * 10n ** BigInt(decimals)
      await fundAsset(asset, user, amount, symbol)
      await send(user, asset, calldata('approve(address,uint256)', config.diamond, max))

      const offerId = id('onre.offer_config', 'address,address,uint8', [asset, managedToken, 1])
      const offer = words(await read(config.diamond, calldata('getOfferConfig(bytes32)', offerId)))
      assert.equal(offer[1], 1n, 'Offer must be permissionless')
      const quoter = config.quoters[definition.quoter]
      const quoterKinds = { nav: 0, navPermissionless: 1, propAmm: 2 }
      assert.equal(offer[3], BigInt(id('onre.quoter', 'uint8,uint64', [quoterKinds[quoter.kind], quoter.instanceId])))
      assert.equal(offer[4], BigInt(id('onre.fee_config', 'uint64', [config.feeConfigs[definition.feeConfig].instanceId])))
      assert.equal(offer[5], BigInt(proceeds))
      assert.equal(offer[6], 0n, 'Buy offer must have no liquidity vault')
      const quote = words(await read(config.diamond, calldata('previewExecution(bytes32,uint256)', offerId, amount)))
      const block = await rpc(local, 'eth_getBlockByNumber', ['latest', false])
      const deadline = BigInt(block.timestamp) + 3600n
      const take = min => calldata('takeOffer((bytes32,uint256,uint256,uint64,(address,uint64),bytes))', `(${offerId},${amount},${min},${deadline},(${zeroAddress},0),0x)`)
      const before = { input: await balance(asset, user), output: await balance(managedToken, user), proceeds: await vaultBalance(proceeds, asset), fees: await vaultBalance(fees, asset), hopInput: await balance(asset, config.settlementAccount), hopOutput: await balance(managedToken, config.settlementAccount) }
      await assert.rejects(rpc(local, 'eth_call', [{ from: user, to: config.diamond, data: take(quote[4] + 1n) }, 'latest']))
      const hash = await send(user, config.diamond, take(quote[4]))
      assert.equal(await balance(asset, user), before.input - amount)
      assert.equal(await balance(managedToken, user), before.output + quote[4])
      assert.equal(await vaultBalance(proceeds, asset), before.proceeds + quote[3])
      assert.equal(await vaultBalance(fees, asset), before.fees + quote[2])
      assert.equal(await balance(asset, config.settlementAccount), before.hopInput)
      assert.equal(await balance(managedToken, config.settlementAccount), before.hopOutput)
      for (let j = n + 1; j < assetTokens.length; j++) assert.equal(await vaultBalance(proceedsByOffer[j], assetTokens[j]), initialProceeds[j])
      if (n > 0) assert.equal(await vaultBalance(proceedsByOffer[0], assetTokens[0]), initialProceeds[0] + BigInt(results[0].netInput))
      results.push({ symbol, offerId, quoter: definition.quoter, feeConfig: definition.feeConfig, input: amount.toString(), fee: quote[2].toString(), netInput: quote[3].toString(), amountOut: quote[4].toString(), onyc: format(quote[4], 9), localTransaction: hash })
      console.log(`PASS: 1000 ${symbol} -> ${format(quote[4], 9)} ONyc; proceeds isolated, minimum enforced, hop balances unchanged`)
    }
    for (const definition of redemptions) {
      const asset = definition.assetToken
      const decimals = Number(words(await read(asset, calldata('decimals()')))[0])
      const symbol = asset.toLowerCase() === '0xe343167631d89b6ffc58b88d6b7fb0228795491d' ? 'USDG' : 'USDC'
      const vault = config.vaults[definition.liquidityVault]
      assert.equal(vault.kind, 'liquidity')
      const liquidityId = id('onre.configurable_vault', 'uint8,uint64', [2, vault.instanceId])
      const fundingAmount = 10000n * 10n ** BigInt(decimals)
      await fundAsset(asset, config.safe, fundingAmount, symbol)
      const deposit = await runScript('script/DepositLiquidityVault.s.sol', `deposit-${definition.name}.log`, ['--sig', 'run(string,uint256)', definition.name, fundingAmount.toString()])
      batch(`deposit-${definition.name}.batch.json`, config.safe, deposit)
      for (const tx of deposit) await send(config.safe, tx.to, tx.data)
      const liquidityBefore = await vaultBalance(liquidityId, asset)
      assert.ok(liquidityBefore >= fundingAmount)
      await send(user, definition.managedToken, calldata('approve(address,uint256)', config.diamond, max))
      const offerId = id('onre.offer_config', 'address,address,uint8', [definition.managedToken, asset, 1])
      const offer = words(await read(config.diamond, calldata('getOfferConfig(bytes32)', offerId)))
      const feeDefinition = config.feeConfigs[definition.feeConfig]
      const feesId = id('onre.configurable_vault', 'uint8,uint64', [0, config.vaults[feeDefinition.feeVault].instanceId])
      const proceedsId = id('onre.configurable_vault', 'uint8,uint64', [1, config.vaults[definition.proceedsVault].instanceId])
      const quoterDefinition = config.quoters[definition.quoter]
      assert.equal(quoterDefinition.kind, 'propAmm')
      const quoterId = id('onre.quoter', 'uint8,uint64', [2, quoterDefinition.instanceId])
      assert.equal(offer[3], BigInt(quoterId))
      assert.equal(offer[4], BigInt(id('onre.fee_config', 'uint64', [feeDefinition.instanceId])))
      assert.equal(offer[5], BigInt(proceedsId))
      assert.equal(offer[6], BigInt(liquidityId))
      const input = 100n * 10n ** 9n
      const quote = words(await read(config.diamond, calldata('previewExecution(bytes32,uint256)', offerId, input)))
      const percentageFee = (input * BigInt(feeDefinition.basisPoints) + 9999n) / 10000n
      assert.equal(quote[2], percentageFee > BigInt(feeDefinition.minimumFeeAmount) ? percentageFee : BigInt(feeDefinition.minimumFeeAmount))
      const before = { input: await balance(definition.managedToken, user), output: await balance(asset, user), fees: await vaultBalance(feesId, definition.managedToken), hopInput: await balance(definition.managedToken, config.settlementAccount), hopOutput: await balance(asset, config.settlementAccount) }
      const block = await rpc(local, 'eth_getBlockByNumber', ['latest', false])
      const deadline = BigInt(block.timestamp) + 3600n
      const take = min => calldata('takeOffer((bytes32,uint256,uint256,uint64,(address,uint64),bytes))', `(${offerId},${input},${min},${deadline},(${zeroAddress},0),0x)`)
      await assert.rejects(rpc(local, 'eth_call', [{ from: user, to: config.diamond, data: take(quote[4] + 1n) }, 'latest']))
      const hash = await send(user, config.diamond, take(quote[4]))
      assert.equal(await balance(definition.managedToken, user), before.input - input)
      assert.equal(await balance(asset, user), before.output + quote[4])
      assert.equal(await vaultBalance(liquidityId, asset), liquidityBefore - quote[4])
      assert.equal(await vaultBalance(feesId, definition.managedToken), before.fees + quote[2])
      assert.equal(await balance(definition.managedToken, config.settlementAccount), before.hopInput)
      assert.equal(await balance(asset, config.settlementAccount), before.hopOutput)
      assert.equal(await vaultBalance(proceedsId, definition.managedToken), 0n)
      const pressure = words(await read(config.diamond, calldata('getPropAmmState(bytes32)', quoterId)))[0]
      assert.ok(pressure > 0n)
      results.push({ name: definition.name, direction: definition.direction, offerId, input: input.toString(), inputSymbol: 'ONyc', fee: quote[2].toString(), amountOut: quote[4].toString(), outputSymbol: symbol, assetOut: format(quote[4], decimals), localTransaction: hash })
      console.log(`PASS: 100 ONyc -> ${format(quote[4], decimals)} ${symbol} through Prop AMM; ${feeDefinition.basisPoints} bps fee, liquidity debited, hop unchanged`)
    }
    const withdrawals = await testVaultWithdrawals()
    const restore = await runScript('script/SetupOffers.s.sol', 'restore-configured-state.log')
    assert.equal(restore.length, disabledOffers.length, 'Setup must disable the temporarily enabled offers again')
    for (const tx of restore) {
      assert.ok(disabledOffers.some(offer => tx.data === calldata('setOfferConfigEnabled(bytes32,bool)', offerIdFor(offer), false)))
      await send(config.safe, tx.to, tx.data)
    }
    for (const offer of allOffers) assert.equal(words(await read(config.diamond, calldata('getOfferConfig(bytes32)', offerIdFor(offer))))[10], offer.enabled ? 1n : 0n)
    const repeated = await runScript('script/SetupOffers.s.sol', 'rerun.log')
    assert.equal(repeated.length, 0, 'Repeated setup must not emit new transactions')
    for (const script of ['AssetToManagedOffer', 'PropAmmManagedToAssetOfferMainnet']) {
      assert.equal((await runScript(`script/${script}.s.sol`, `${script}.log`)).length, 0)
    }
    await assert.rejects(
      runScript('script/AssetToManagedPermissionedOffer.s.sol', 'permissioned.log'),
      /No matching offers configured/,
    )

    // All writes below still go only to the disposable Anvil fork.
    assert.equal((await runScript('script/SetSettlementAccount.s.sol', 'settlement-unchanged.log')).length, 0)
    await send(config.safe, config.diamond, calldata('setPermissionlessSettlementAccount(address)', user))
    const settlementUpdate = await runScript('script/SetSettlementAccount.s.sol', 'settlement-update.log')
    assert.equal(settlementUpdate.length, 1)
    for (const tx of settlementUpdate) await send(config.safe, tx.to, tx.data)
    assert.equal(BigInt(await read(config.diamond, calldata('permissionlessSettlementAccount()'))), BigInt(config.settlementAccount))
    assert.equal((await runScript('script/SetSettlementAccount.s.sol', 'settlement-repeat.log')).length, 0)

    const countBefore = words(await read(config.diamond, calldata('deployedManagedTokenCount()')))[0]
    const deployArgs = ['--sig', 'run(string,string,uint8,bytes32)', 'Script Test Token', 'SCRIPT', '9', cast('keccak', 'offer-script-anvil-validation-v1')]
    const deployment = await runScript('script/DeployManagedToken.s.sol', 'deploy-managed-token.log', deployArgs)
    assert.equal(deployment.length, 2)
    for (const tx of deployment) await send(config.safe, tx.to, tx.data)
    assert.equal(words(await read(config.diamond, calldata('deployedManagedTokenCount()')))[0], countBefore + 1n)
    const tokenAddress = '0x' + (await read(config.diamond, calldata('deployedManagedTokenAt(uint256)', countBefore))).slice(-40)
    assert.equal(cast('abi-decode', 'f()(string)', await read(tokenAddress, calldata('name()'))), '"Script Test Token"')
    assert.equal(words(await read(tokenAddress, calldata('decimals()')))[0], 9n)
    for (const role of ['isMinter(address)', 'isBurner(address)']) {
      assert.equal(words(await read(tokenAddress, calldata(role, config.diamond)))[0], 1n)
    }
    await assert.rejects(runScript('script/DeployManagedToken.s.sol', 'deploy-repeat.log', deployArgs), /implementation already deployed/)

    const disableId = results[0].offerId
    if (words(await read(config.diamond, calldata('getOfferConfig(bytes32)', disableId)))[10] === 0n) {
      await send(config.safe, config.diamond, calldata('setOfferConfigEnabled(bytes32,bool)', disableId, true))
    }
    const disableArgs = ['--sig', 'run(bytes32)', disableId]
    const disable = await runScript('script/DisableOffer.s.sol', 'disable-offer.log', disableArgs)
    assert.equal(disable.length, 1)
    for (const tx of disable) await send(config.safe, tx.to, tx.data)
    assert.equal(words(await read(config.diamond, calldata('getOfferConfig(bytes32)', disableId)))[10], 0n)
    assert.equal((await runScript('script/DisableOffer.s.sol', 'disable-repeat.log', disableArgs)).length, 0)
    console.log('PASS: all operational script entry points; token deployment, settlement updates, disabling, and repeat calls')
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ environment, forkBlock: String(BigInt(forkBlock)), pricerId, activation: activation.toString(), results, withdrawals, configuredDisabledOffers: disabledOffers.map(offer => offer.name), restoredDisabledOffers: restore.length, repeatSetupTransactions: repeated.length }, null, 2) + '\n')
    console.log(`PASS: repeated setup emits no transactions. Evidence: ${output}`)
  } finally {
    anvil.kill('SIGTERM')
    fs.closeSync(anvilLog)
  }
}

main().catch(error => { console.error(error.message); process.exitCode = 1 })
