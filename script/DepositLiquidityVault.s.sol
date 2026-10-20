// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {EnvironmentScript} from "./base/EnvironmentScript.sol";
import {console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import {ConfigurableVaultKind} from "../src/types/OnReTypes.sol";

/// Run with ONRE_ENV set and --rpc-url for the selected environment.
contract DepositLiquidityVault is EnvironmentScript {
    uint64 constant LIQUIDITY_VAULT_INSTANCE_ID = 0;

    uint256 constant AMOUNT = 10_000e6;

    function run() external {
        Environment memory env = _loadEnvironment();
        require(env.assetToken != address(0), "Environment assetToken not set");
        bytes32 liquidityVaultId =
            OnReIds._configurableVaultId(ConfigurableVaultKind.Liquidity, LIQUIDITY_VAULT_INSTANCE_ID);

        IDiamondProxy app = IDiamondProxy(env.diamond);

        bytes memory approveData = abi.encodeCall(IERC20.approve, (env.diamond, AMOUNT));
        bytes memory depositData =
            abi.encodeCall(IDiamondProxy.depositConfigurableVault, (liquidityVaultId, env.assetToken, AMOUNT));

        uint256 balanceBefore = app.configurableVaultBalance(liquidityVaultId, env.assetToken);
        uint256 safeBalance = IERC20(env.assetToken).balanceOf(env.safe);

        require(
            safeBalance >= AMOUNT, string.concat("Safe asset balance below AMOUNT. Balance: ", vm.toString(safeBalance))
        );

        vm.startPrank(env.safe);

        (bool ok,) = env.assetToken.call(approveData);
        require(ok, "approve simulation failed");

        (ok,) = env.diamond.call(depositData);
        require(ok, "depositConfigurableVault simulation failed");

        vm.stopPrank();

        uint256 balanceAfter = app.configurableVaultBalance(liquidityVaultId, env.assetToken);
        require(balanceAfter == balanceBefore + AMOUNT, "unexpected vault balance after deposit");

        console.log("Simulated vault balance after: ", balanceAfter);

        console.log("Safe:            ", env.safe);
        console.log("Liquidity vault: ", vm.toString(liquidityVaultId));
        console.log("Amount:          ", AMOUNT);
        console.log("Vault balance:   ", balanceBefore);
        console.log("");
        console.log("Tx 1: asset token approve");
        console.log("  to:   ", env.assetToken);
        console.log("  value: 0");
        console.log("  data: ", vm.toString(approveData));
        console.log("Tx 2: depositConfigurableVault");
        console.log("  to:   ", env.diamond);
        console.log("  value: 0");
        console.log("  data: ", vm.toString(depositData));
    }
}
