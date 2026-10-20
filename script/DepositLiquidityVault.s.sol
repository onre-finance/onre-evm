// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import {ConfigurableVaultKind} from "../src/types/OnReTypes.sol";

/// Run:
//  forge script script/DepositLiquidityVault.s.sol --rpc-url $RPC_URL
contract DepositLiquidityVault is Script {
    address constant DIAMOND = 0xF43b84eC9829a2d8D273fB4EC082FC357ed59DEa;
    address constant SAFE = 0x0F8326Eff929B23d01991990c5b4bC1dd9B5e8a4;

    address constant ASSET_TOKEN = 0x977048BfC71b5B0143b057508712974A7Ec18468;
    uint64 constant LIQUIDITY_VAULT_INSTANCE_ID = 0;

    uint256 constant AMOUNT = 10_000e6;

    function run() external {
        bytes32 liquidityVaultId =
            OnReIds._configurableVaultId(ConfigurableVaultKind.Liquidity, LIQUIDITY_VAULT_INSTANCE_ID);

        IDiamondProxy app = IDiamondProxy(DIAMOND);

        bytes memory approveData = abi.encodeCall(IERC20.approve, (DIAMOND, AMOUNT));
        bytes memory depositData =
            abi.encodeCall(IDiamondProxy.depositConfigurableVault, (liquidityVaultId, ASSET_TOKEN, AMOUNT));

        uint256 balanceBefore = app.configurableVaultBalance(liquidityVaultId, ASSET_TOKEN);
        uint256 safeBalance = IERC20(ASSET_TOKEN).balanceOf(SAFE);

        require(
            safeBalance >= AMOUNT,
            string.concat("Safe asset balance below AMOUNT. Balance: ", vm.toString(safeBalance))
        );

        vm.startPrank(SAFE);

        (bool ok,) = ASSET_TOKEN.call(approveData);
        require(ok, "approve simulation failed");

        (ok,) = DIAMOND.call(depositData);
        require(ok, "depositConfigurableVault simulation failed");

        vm.stopPrank();

        uint256 balanceAfter = app.configurableVaultBalance(liquidityVaultId, ASSET_TOKEN);
        require(balanceAfter == balanceBefore + AMOUNT, "unexpected vault balance after deposit");

        console.log("Simulated vault balance after: ", balanceAfter);

        console.log("Safe:            ", SAFE);
        console.log("Liquidity vault: ", vm.toString(liquidityVaultId));
        console.log("Amount:          ", AMOUNT);
        console.log("Vault balance:   ", balanceBefore);
        console.log("");
        console.log("Tx 1: USDC approve");
        console.log("  to:   ", ASSET_TOKEN);
        console.log("  value: 0");
        console.log("  data: ", vm.toString(approveData));
        console.log("Tx 2: depositConfigurableVault");
        console.log("  to:   ", DIAMOND);
        console.log("  value: 0");
        console.log("  data: ", vm.toString(depositData));
    }
}
