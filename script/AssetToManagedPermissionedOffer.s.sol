// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script, console} from "forge-std/Script.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import {MakeOfferConfigParams, OfferFlow, QuoterKind} from "../src/types/OnReTypes.sol";

/// SAFE must hold DEFAULT_ADMIN_ROLE.
/// Run: forge script script/AssetToManagedPermissionedOffer.s.sol --rpc-url $RPC_URL
contract AssetToManagedPermissionedOffer is Script {
    // TODO: fill in before running.
    address constant DIAMOND = 0x3DBd1B71332f7935dc2DAeFD16C353Ba055d690D;
    address constant SAFE = 0x99CDC01fF619EB512F50161B296D0910a5b06738;

    address constant MANAGED_TOKEN = 0x3D6b4235A796563781ADf6505882e5d45867FE49;
    address constant ASSET_TOKEN = 0xd3eDe529DFA604761c24DF35879D39d9358165FF;

    bytes32 constant FEE_VAULT_ID = 0x07bb608cea39e3d4b78d130da64b81e26ab8855f8cfe81106bb80fb5b324ac2b;
    bytes32 constant PROCEEDS_VAULT_ID = 0x9a4b6e53b2f935d25c3d8a22a4b20f256ac5eb4e7ea4b9266cecc63326e53149;

    uint64 constant QUOTER_INSTANCE_ID = 0;

    uint64 constant FEE_CONFIG_INSTANCE_ID = 1;
    uint16 constant FEE_BPS = 20;
    uint256 constant MIN_FEE_AMOUNT = 0;

    function run() external {
        require(DIAMOND != address(0) && SAFE != address(0), "DIAMOND/SAFE not set");
        require(MANAGED_TOKEN != address(0) && ASSET_TOKEN != address(0), "tokens not set");
        require(FEE_VAULT_ID != bytes32(0) && PROCEEDS_VAULT_ID != bytes32(0), "FEE_VAULT_ID/PROCEEDS_VAULT_ID not set");

        bytes32 quoterId = OnReIds._quoterId(QuoterKind.Nav, QUOTER_INSTANCE_ID);
        bytes32 feeConfigId = OnReIds._feeConfigId(FEE_CONFIG_INSTANCE_ID);
        bytes32 offerId = OnReIds._offerConfigId(ASSET_TOKEN, MANAGED_TOKEN, OfferFlow.Permissioned);
        IDiamondProxy app = IDiamondProxy(DIAMOND);

        bytes[] memory data = new bytes[](3);
        string[3] memory names = ["createQuoter", "createFeeConfig", "makeOfferConfig"];
        data[0] = abi.encodeCall(IDiamondProxy.createQuoter, (QuoterKind.Nav, QUOTER_INSTANCE_ID));
        data[1] = abi.encodeCall(
            IDiamondProxy.createFeeConfig, (FEE_CONFIG_INSTANCE_ID, FEE_BPS, MIN_FEE_AMOUNT, FEE_VAULT_ID)
        );
        data[2] = abi.encodeCall(
            IDiamondProxy.makeOfferConfig,
            (MakeOfferConfigParams({
                    tokenIn: ASSET_TOKEN,
                    tokenOut: MANAGED_TOKEN,
                    flow: OfferFlow.Permissioned,
                    quoterId: quoterId,
                    feeConfigId: feeConfigId,
                    proceedsVaultId: PROCEEDS_VAULT_ID,
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
        console.log("Quoter ID:       ", vm.toString(quoterId));
        console.log("Fee vault:       ", vm.toString(FEE_VAULT_ID));
        console.log("Proceeds vault:  ", vm.toString(PROCEEDS_VAULT_ID));
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
