// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {
    ConfigurableVaultKind,
    MakeOfferConfigParams,
    OfferFlow,
    PricingDenomination,
    PricingVector,
    QuoterKind
} from "../src/types/OnReTypes.sol";
import {OnReOps} from "./base/OnReOps.sol";

/// SAFE must hold DEFAULT_ADMIN_ROLE.
/// Run: forge script script/AssetToManagedOfferV2.s.sol --rpc-url $RPC_URL
contract AssetToManagedOfferV2 is OnReOps {
    // TODO: fill in before running.
    address constant DIAMOND = 0x3DBd1B71332f7935dc2DAeFD16C353Ba055d690D;
    address constant SAFE = 0x99CDC01fF619EB512F50161B296D0910a5b06738;


    address constant MANAGED_TOKEN = 0x3D6b4235A796563781ADf6505882e5d45867FE49;
    address constant ASSET_TOKEN = 0xd3eDe529DFA604761c24DF35879D39d9358165FF;
    address constant SETTLEMENT_ACCOUNT = 0x3D6b4235A796563781ADf6505882e5d45867FE49;

    uint64 constant QUOTER_INSTANCE_ID = 0;

    uint64 constant FEE_VAULT_INSTANCE_ID = 0;

    uint64 constant PROCEEDS_VAULT_INSTANCE_ID = 0;

    uint64 constant FEE_CONFIG_INSTANCE_ID = 0;
    uint16 constant FEE_BPS = 0;
    uint256 constant MIN_FEE_AMOUNT = 0;
    uint16 constant VAULT_REFILL_TARGET_BPS = 0;

    // --- Pricing vector ---
    uint64 constant START_TIME = 1_791_291_600; // 2026-10-06 13:00 UTC
    uint64 constant BASE_TIME = 1_789_776_000; // 2026-09-19 00:00 UTC
    uint64 constant BASE_PRICE = 1_146_935_367;
    uint64 constant APR = 104_555;
    uint64 constant PRICE_FIX_DURATION = 86_400;

    function run() external {
        _init(DIAMOND, SAFE);
        require(MANAGED_TOKEN != address(0) && ASSET_TOKEN != address(0), "tokens not set");
        require(SETTLEMENT_ACCOUNT != address(0), "SETTLEMENT_ACCOUNT not set");

        _setPermissionlessSettlementAccount(SETTLEMENT_ACCOUNT);
        bytes32 pricerId = _createPricer(MANAGED_TOKEN, PricingDenomination.Usd);
        _addPricingVector(
            pricerId,
            PricingVector({
                startTime: START_TIME,
                baseTime: BASE_TIME,
                basePrice: BASE_PRICE,
                apr: APR,
                priceFixDuration: PRICE_FIX_DURATION
            })
        );
        bytes32 quoterId = _createQuoter(QuoterKind.NavPermissionless, QUOTER_INSTANCE_ID);
        bytes32 feeVaultId =
            _createConfigurableVault(ConfigurableVaultKind.Fee, FEE_VAULT_INSTANCE_ID, VAULT_REFILL_TARGET_BPS);
        bytes32 proceedsVaultId = _createConfigurableVault(
            ConfigurableVaultKind.Proceeds, PROCEEDS_VAULT_INSTANCE_ID, VAULT_REFILL_TARGET_BPS
        );
        bytes32 feeConfigId = _createFeeConfig(FEE_CONFIG_INSTANCE_ID, FEE_BPS, MIN_FEE_AMOUNT, feeVaultId);
        bytes32 offerId = _makeOfferConfig(
            MakeOfferConfigParams({
                tokenIn: ASSET_TOKEN,
                tokenOut: MANAGED_TOKEN,
                flow: OfferFlow.Permissionless,
                quoterId: quoterId,
                feeConfigId: feeConfigId,
                proceedsVaultId: proceedsVaultId,
                liquidityVaultId: bytes32(0)
            })
        );

        require(IDiamondProxy(diamond).getOfferConfig(offerId).quoterId == quoterId, "offer quoter not set");

        _log("Pricer ID", pricerId);
        _log("Quoter ID", quoterId);
        _log("Fee vault", feeVaultId);
        _log("Proceeds vault", proceedsVaultId);
        _log("Fee config ID", feeConfigId);
        _log("Offer ID", offerId);
        _printTxs();
    }
}
