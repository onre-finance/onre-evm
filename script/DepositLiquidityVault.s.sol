// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import {ConfigurableVaultKind} from "../src/types/OnReTypes.sol";
import {OfferConfiguration} from "./base/OfferConfiguration.sol";

/// Run with ONRE_ENV, --rpc-url, and --sig "run(string,uint256)" <offerName> <amountInBaseUnits>.
/// Uses the named offer's asset token and liquidity vault; the Safe must already hold the funds.
contract DepositLiquidityVault is OfferConfiguration {
    function run(string memory offerName, uint256 amount) external {
        Environment memory env = _loadEnvironment();
        Configuration memory config = _loadOfferConfiguration();
        _init(env.diamond, env.safe);
        require(amount > 0, "Deposit amount is zero");
        OfferDefinition memory offer = _offer(config, offerName);
        bytes32 vaultId = _liquidityVaultId(config, offer.liquidityVault);
        IDiamondProxy app = IDiamondProxy(diamond);
        (address tokenIn, address tokenOut) = _tokens(offer);
        require(
            app.getOfferConfig(OnReIds._offerConfigId(tokenIn, tokenOut, offer.flow)).liquidityVaultId == vaultId,
            "Live offer liquidity vault differs from config"
        );
        require(
            app.getConfigurableVault(vaultId).kind == ConfigurableVaultKind.Liquidity,
            "Live vault must be liquidity kind"
        );
        uint256 balanceBefore = app.configurableVaultBalance(vaultId, offer.assetToken);
        require(IERC20(offer.assetToken).balanceOf(safe) >= amount, "Safe asset balance below deposit amount");
        _ensureApproval(offer.assetToken, amount);
        _depositConfigurableVault(vaultId, offer.assetToken, amount);
        require(
            app.configurableVaultBalance(vaultId, offer.assetToken) == balanceBefore + amount,
            "Unexpected vault balance after deposit"
        );
        _log("Deposit asset", offer.assetToken);
        _log("Liquidity vault", vaultId);
        _log("Deposit amount", amount);
        _printTxs();
    }
}
