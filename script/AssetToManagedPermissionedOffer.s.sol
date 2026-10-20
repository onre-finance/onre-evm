// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {EnvironmentScript} from "./base/EnvironmentScript.sol";
import {console} from "forge-std/Script.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import {MakeOfferConfigParams, OfferFlow, QuoterKind} from "../src/types/OnReTypes.sol";

/// The configured Safe must hold DEFAULT_ADMIN_ROLE.
/// Run with ONRE_ENV set and --rpc-url for the selected environment.
contract AssetToManagedPermissionedOffer is EnvironmentScript {
    bytes32 constant FEE_VAULT_ID = 0x07bb608cea39e3d4b78d130da64b81e26ab8855f8cfe81106bb80fb5b324ac2b;
    bytes32 constant PROCEEDS_VAULT_ID = 0x9a4b6e53b2f935d25c3d8a22a4b20f256ac5eb4e7ea4b9266cecc63326e53149;

    uint64 constant QUOTER_INSTANCE_ID = 0;

    uint64 constant FEE_CONFIG_INSTANCE_ID = 1;
    uint16 constant FEE_BPS = 20;
    uint256 constant MIN_FEE_AMOUNT = 0;

    function run() external {
        Environment memory env = _loadEnvironment();
        require(env.managedToken != address(0) && env.assetToken != address(0), "tokens not set");
        require(FEE_VAULT_ID != bytes32(0) && PROCEEDS_VAULT_ID != bytes32(0), "FEE_VAULT_ID/PROCEEDS_VAULT_ID not set");

        bytes32 quoterId = OnReIds._quoterId(QuoterKind.Nav, QUOTER_INSTANCE_ID);
        bytes32 feeConfigId = OnReIds._feeConfigId(FEE_CONFIG_INSTANCE_ID);
        bytes32 offerId = OnReIds._offerConfigId(env.assetToken, env.managedToken, OfferFlow.Permissioned);
        IDiamondProxy app = IDiamondProxy(env.diamond);

        bytes[] memory data = new bytes[](3);
        string[3] memory names = ["createQuoter", "createFeeConfig", "makeOfferConfig"];
        data[0] = abi.encodeCall(IDiamondProxy.createQuoter, (QuoterKind.Nav, QUOTER_INSTANCE_ID));
        data[1] = abi.encodeCall(
            IDiamondProxy.createFeeConfig, (FEE_CONFIG_INSTANCE_ID, FEE_BPS, MIN_FEE_AMOUNT, FEE_VAULT_ID)
        );
        data[2] = abi.encodeCall(
            IDiamondProxy.makeOfferConfig,
            (MakeOfferConfigParams({
                    tokenIn: env.assetToken,
                    tokenOut: env.managedToken,
                    flow: OfferFlow.Permissioned,
                    quoterId: quoterId,
                    feeConfigId: feeConfigId,
                    proceedsVaultId: PROCEEDS_VAULT_ID,
                    liquidityVaultId: bytes32(0)
                }))
        );

        vm.startPrank(env.safe);
        for (uint256 i; i < data.length; ++i) {
            (bool ok,) = env.diamond.call(data[i]);
            require(ok, string.concat(names[i], " simulation failed"));
        }
        vm.stopPrank();

        require(app.getOfferConfig(offerId).quoterId == quoterId, "offer quoter not set");

        console.log("Safe:            ", env.safe);
        console.log("Quoter ID:       ", vm.toString(quoterId));
        console.log("Fee vault:       ", vm.toString(FEE_VAULT_ID));
        console.log("Proceeds vault:  ", vm.toString(PROCEEDS_VAULT_ID));
        console.log("Fee config ID:   ", vm.toString(feeConfigId));
        console.log("Offer ID:        ", vm.toString(offerId));
        for (uint256 i; i < data.length; ++i) {
            console.log("");
            console.log(string.concat("Tx ", vm.toString(i + 1), ": ", names[i]));
            console.log("  to:   ", env.diamond);
            console.log("  value: 0");
            console.log("  data: ", vm.toString(data[i]));
        }
    }
}
