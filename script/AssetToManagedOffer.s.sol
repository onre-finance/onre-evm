// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script, console} from "forge-std/Script.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import {
    ConfigurableVaultKind,
    MakeOfferConfigParams,
    OfferFlow,
    PricingDenomination,
    PricingVector,
    QuoterKind
} from "../src/types/OnReTypes.sol";

/// SAFE must hold DEFAULT_ADMIN_ROLE.
/// Run: forge script script/AssetToManagedOffer.s.sol --rpc-url $RPC_URL
contract AssetToManagedOffer is Script {
    // TODO: fill in before running.
    address constant DIAMOND = address(0);
    address constant SAFE = address(0);
    address constant MANAGED_TOKEN = address(0);
    address constant ASSET_TOKEN = address(0);
    address constant SETTLEMENT_ACCOUNT = address(0);

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
        require(DIAMOND != address(0) && SAFE != address(0), "DIAMOND/SAFE not set");
        require(MANAGED_TOKEN != address(0) && ASSET_TOKEN != address(0), "tokens not set");
        require(SETTLEMENT_ACCOUNT != address(0), "SETTLEMENT_ACCOUNT not set");

        bytes32 pricerId = OnReIds._pricerId(MANAGED_TOKEN, PricingDenomination.Usd);
        bytes32 quoterId = OnReIds._quoterId(QuoterKind.NavPermissionless, QUOTER_INSTANCE_ID);
        bytes32 feeVaultId = OnReIds._configurableVaultId(ConfigurableVaultKind.Fee, FEE_VAULT_INSTANCE_ID);
        bytes32 proceedsVaultId =
            OnReIds._configurableVaultId(ConfigurableVaultKind.Proceeds, PROCEEDS_VAULT_INSTANCE_ID);
        bytes32 feeConfigId = OnReIds._feeConfigId(FEE_CONFIG_INSTANCE_ID);
        bytes32 offerId = OnReIds._offerConfigId(ASSET_TOKEN, MANAGED_TOKEN, OfferFlow.Permissionless);
        IDiamondProxy app = IDiamondProxy(DIAMOND);

        bytes[] memory data = new bytes[](8);
        string[8] memory names = [
            "setPermissionlessSettlementAccount",
            "createPricer",
            "addPricingVector",
            "createQuoter",
            "createConfigurableVault (Fee)",
            "createConfigurableVault (Proceeds)",
            "createFeeConfig",
            "makeOfferConfig"
        ];
        data[0] = abi.encodeCall(IDiamondProxy.setPermissionlessSettlementAccount, (SETTLEMENT_ACCOUNT));
        data[1] = abi.encodeCall(IDiamondProxy.createPricer, (MANAGED_TOKEN, PricingDenomination.Usd));
        data[2] = abi.encodeCall(
            IDiamondProxy.addPricingVector,
            (
                pricerId,
                PricingVector({
                    startTime: START_TIME,
                    baseTime: BASE_TIME,
                    basePrice: BASE_PRICE,
                    apr: APR,
                    priceFixDuration: PRICE_FIX_DURATION
                })
            )
        );
        data[3] = abi.encodeCall(IDiamondProxy.createQuoter, (QuoterKind.NavPermissionless, QUOTER_INSTANCE_ID));
        data[4] = abi.encodeCall(
            IDiamondProxy.createConfigurableVault,
            (ConfigurableVaultKind.Fee, FEE_VAULT_INSTANCE_ID, SAFE, VAULT_REFILL_TARGET_BPS)
        );
        data[5] = abi.encodeCall(
            IDiamondProxy.createConfigurableVault,
            (ConfigurableVaultKind.Proceeds, PROCEEDS_VAULT_INSTANCE_ID, SAFE, VAULT_REFILL_TARGET_BPS)
        );
        data[6] = abi.encodeCall(
            IDiamondProxy.createFeeConfig, (FEE_CONFIG_INSTANCE_ID, FEE_BPS, MIN_FEE_AMOUNT, feeVaultId)
        );
        data[7] = abi.encodeCall(
            IDiamondProxy.makeOfferConfig,
            (MakeOfferConfigParams({
                    tokenIn: ASSET_TOKEN,
                    tokenOut: MANAGED_TOKEN,
                    flow: OfferFlow.Permissionless,
                    quoterId: quoterId,
                    feeConfigId: feeConfigId,
                    proceedsVaultId: proceedsVaultId,
                    liquidityVaultId: bytes32(0)
                }))
        );

        vm.startPrank(SAFE);
        for (uint256 i; i < data.length; ++i) {
            (bool ok,) = DIAMOND.call(data[i]);
            require(ok, string.concat(names[i], " simulation failed"));
        }
        vm.stopPrank();

        require(app.getOfferConfig(offerId).quoterId == quoterId, "offer quoter not set");

        console.log("Safe:            ", SAFE);
        console.log("Pricer ID:       ", vm.toString(pricerId));
        console.log("Quoter ID:       ", vm.toString(quoterId));
        console.log("Fee vault:       ", vm.toString(feeVaultId));
        console.log("Proceeds vault:  ", vm.toString(proceedsVaultId));
        console.log("Fee config ID:   ", vm.toString(feeConfigId));
        console.log("Offer ID:        ", vm.toString(offerId));
        for (uint256 i; i < data.length; ++i) {
            console.log("");
            console.log(string.concat("Tx ", vm.toString(i + 1), ": ", names[i]));
            console.log("  to:   ", DIAMOND);
            console.log("  value: 0");
            console.log("  data: ", vm.toString(data[i]));
        }
    }
}
