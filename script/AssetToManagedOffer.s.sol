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

/// The configured Safe must hold DEFAULT_ADMIN_ROLE.
/// Run with ONRE_ENV set and --rpc-url for the selected environment.
contract AssetToManagedOffer is OnReOps {
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
        Environment memory env = _loadEnvironment();
        _init(env.diamond, env.safe);
        require(env.managedToken != address(0) && env.assetToken != address(0), "tokens not set");
        require(env.settlementAccount != address(0), "SETTLEMENT_ACCOUNT not set");

        _setPermissionlessSettlementAccount(env.settlementAccount);
        bytes32 pricerId = _createPricer(env.managedToken, PricingDenomination.Usd);
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
                tokenIn: env.assetToken,
                tokenOut: env.managedToken,
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
