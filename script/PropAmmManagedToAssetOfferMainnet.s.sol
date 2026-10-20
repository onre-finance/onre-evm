// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {EnvironmentScript} from "./base/EnvironmentScript.sol";
import {console} from "forge-std/Script.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import {
    MakeOfferConfigParams,
    OfferFlow,
    PropAmmConfig,
    QuoterKind,
    ConfigurableVaultKind
} from "../src/types/OnReTypes.sol";

/// Run with ONRE_ENV set and --rpc-url for the selected environment.
contract PropAmmManagedToAssetOfferMainnet is EnvironmentScript {
    bytes32 constant FEE_CONFIG_ID = 0xC2990AFCA3939851ED4EBF93B8A36D35CE539FDEDF446BBE5289A89A9626694D;
    bytes32 constant PROCEEDS_VAULT_ID = 0x9A4B6E53B2F935D25C3D8A22A4B20F256AC5EB4E7EA4B9266CECC63326E53149;

    uint64 constant QUOTER_INSTANCE_ID = 0;

    uint64 constant LIQUIDITY_VAULT_INSTANCE_ID = 0;
    uint16 constant LIQUIDITY_VAULT_REFILL_TARGET_BPS = 0; // TODO: Check

    // --- PropAmm config ---
    uint16 constant CURVE_PEG_HAIRCUT_BPS = 3650;
    uint32 constant CURVE_EXPONENT_SCALED = 19_000;
    uint32 constant CADENCE_THRESHOLD = 20;
    uint32 constant CADENCE_WAVE_SCALED = 2_000;
    uint64 constant EPOCH_DURATION_SECONDS = 300;
    uint32 constant WALL_SENSITIVITY_SCALED = 20_000;

    function run() external {
        Environment memory env = _loadEnvironment();
        require(env.managedToken != address(0) && env.assetToken != address(0), "tokens not set");
        require(
            FEE_CONFIG_ID != bytes32(0) && PROCEEDS_VAULT_ID != bytes32(0), "FEE_CONFIG_ID/PROCEEDS_VAULT_ID not set"
        );

        bytes32 quoterId = OnReIds._quoterId(QuoterKind.PropAmm, QUOTER_INSTANCE_ID);
        bytes32 offerId = OnReIds._offerConfigId(env.managedToken, env.assetToken, OfferFlow.Permissionless);
        bytes32 liquidityVaultId =
            OnReIds._configurableVaultId(ConfigurableVaultKind.Liquidity, LIQUIDITY_VAULT_INSTANCE_ID);

        IDiamondProxy app = IDiamondProxy(env.diamond);

        bytes memory createQuoterData =
            abi.encodeCall(IDiamondProxy.createQuoter, (QuoterKind.PropAmm, QUOTER_INSTANCE_ID));

        bytes memory configurePropAmmData = abi.encodeCall(
            IDiamondProxy.configurePropAmm,
            (
                quoterId,
                env.assetToken,
                env.managedToken,
                PropAmmConfig({
                    epochDurationSeconds: EPOCH_DURATION_SECONDS,
                    curveExponentScaled: CURVE_EXPONENT_SCALED,
                    cadenceThreshold: CADENCE_THRESHOLD,
                    cadenceWaveScaled: CADENCE_WAVE_SCALED,
                    wallSensitivityScaled: WALL_SENSITIVITY_SCALED,
                    curvePegHaircutBps: CURVE_PEG_HAIRCUT_BPS
                })
            )
        );

        bytes memory createLiquidityVaultData = abi.encodeCall(
            IDiamondProxy.createConfigurableVault,
            (ConfigurableVaultKind.Liquidity, LIQUIDITY_VAULT_INSTANCE_ID, env.safe, LIQUIDITY_VAULT_REFILL_TARGET_BPS)
        );

        bytes memory makeOfferData = abi.encodeCall(
            IDiamondProxy.makeOfferConfig,
            (MakeOfferConfigParams({
                    tokenIn: env.managedToken,
                    tokenOut: env.assetToken,
                    flow: OfferFlow.Permissionless,
                    quoterId: quoterId,
                    feeConfigId: FEE_CONFIG_ID,
                    proceedsVaultId: PROCEEDS_VAULT_ID,
                    liquidityVaultId: liquidityVaultId
                }))
        );

        vm.startPrank(env.safe);
        (bool ok,) = env.diamond.call(createQuoterData);
        require(ok, "createQuoter simulation failed");

        (ok,) = env.diamond.call(configurePropAmmData);
        require(ok, "configurePropAmm simulation failed");

        (ok,) = env.diamond.call(createLiquidityVaultData);
        require(ok, "createConfigurableVault (liquidity) simulation failed");

        (ok,) = env.diamond.call(makeOfferData);
        require(ok, "makeOfferConfig simulation failed");
        vm.stopPrank();

        require(app.getOfferConfig(offerId).quoterId == quoterId, "offer quoter not set");
        require(app.getOfferConfig(offerId).liquidityVaultId == liquidityVaultId, "offer liquidity vault not set");

        console.log("Safe:            ", env.safe);
        console.log("Offer ID:        ", vm.toString(offerId));
        console.log("PropAmm quoter:  ", vm.toString(quoterId));
        console.log("Liquidity vault: ", vm.toString(liquidityVaultId));
        console.log("Epoch start:     ", app.getPropAmmState(quoterId).epochStart);
        console.log("");
        console.log("Tx 1: createQuoter");
        console.log("  to:   ", env.diamond);
        console.log("  value: 0");
        console.log("  data: ", vm.toString(createQuoterData));
        console.log("Tx 2: configurePropAmm");
        console.log("  to:   ", env.diamond);
        console.log("  value: 0");
        console.log("  data: ", vm.toString(configurePropAmmData));
        console.log("Tx 3: createConfigurableVault (liquidity)");
        console.log("  to:   ", env.diamond);
        console.log("  value: 0");
        console.log("  data: ", vm.toString(createLiquidityVaultData));
        console.log("Tx 4: makeOfferConfig");
        console.log("  to:   ", env.diamond);
        console.log("  value: 0");
        console.log("  data: ", vm.toString(makeOfferData));
    }
}
