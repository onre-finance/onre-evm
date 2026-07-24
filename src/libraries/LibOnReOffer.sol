// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {IOnReAppEvents} from "../interfaces/IOnReAppEvents.sol";
import {IOnReToken} from "../interfaces/IOnReToken.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReApproval} from "./LibOnReApproval.sol";
import {LibOnReFeeConfig} from "./LibOnReFeeConfig.sol";
import {LibOnReMarketStats} from "./LibOnReMarketStats.sol";
import {LibOnReQuoter} from "./LibOnReQuoter.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {LibOnReVault} from "./LibOnReVault.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Direct and worker offer execution against prevalidated configuration.
library LibOnReOffer {
    uint16 internal constant MAX_BASIS_POINTS = 10_000;

    function takeOffer(OnReTypes.TakeOfferParams calldata params) internal returns (uint256 amountOut) {
        OnReTypes.OfferConfig storage offer = LibOnReValidation.requireExecutableOfferConfig(params.offerConfigId);
        if (block.timestamp > params.deadline) {
            revert IOnReAppErrors.TakeOfferDeadlineExpiredError(params.deadline);
        }

        if (offer.flow == OnReTypes.OfferFlow.Permissioned) {
            if (!LibOnReApproval.isValidForUser(msg.sender, params.approval, params.signature)) {
                revert IOnReAppErrors.InvalidApprovalError();
            }
        } else if (offer.flow == OnReTypes.OfferFlow.Permissionless) {
            if (params.approval.user != address(0) || params.approval.expiry != 0 || params.signature.length != 0) {
                revert IOnReAppErrors.InvalidApprovalError();
            }
        } else {
            revert IOnReAppErrors.WorkerOfferRequiresFulfillmentRequestError(params.offerConfigId);
        }

        return _executeCollectedFromUser(params.offerConfigId, offer, params.grossInputAmount, params.minimumAmountOut);
    }

    function previewExecution(bytes32 offerConfigId, uint256 grossInputAmount)
        internal
        view
        returns (OnReTypes.ExecutionAccounting memory accounting)
    {
        OnReTypes.OfferConfig storage offer = LibOnReValidation.requireExecutableOfferConfig(offerConfigId);
        return previewExecution(offerConfigId, offer, grossInputAmount);
    }

    function previewExecution(bytes32 offerConfigId, OnReTypes.OfferConfig storage offer, uint256 grossInputAmount)
        internal
        view
        returns (OnReTypes.ExecutionAccounting memory accounting)
    {
        if (grossInputAmount == 0) revert IOnReAppErrors.InvalidAmountError();
        OnReTypes.FeeConfig storage feeConfig = LibOnReValidation.requireExecutableFeeConfig(offer.feeConfigId);
        uint256 feeAmount = LibOnReFeeConfig.calculateFee(grossInputAmount, feeConfig);
        uint256 netInputAmount = grossInputAmount - feeAmount;
        if (netInputAmount == 0) revert IOnReAppErrors.InvalidAmountError();
        OnReTypes.QuoteResult memory quoteResult = LibOnReQuoter.quote(offerConfigId, offer, netInputAmount);

        return OnReTypes.ExecutionAccounting({
            price: quoteResult.price,
            grossInputAmount: grossInputAmount,
            feeAmount: feeAmount,
            netInputAmount: netInputAmount,
            amountOut: quoteResult.amountOut,
            liquidityRefillAmount: 0,
            proceedsAmount: 0
        });
    }

    function settleEscrowedWorkerInput(
        bytes32 offerConfigId,
        OnReTypes.OfferConfig storage offer,
        address recipient,
        uint256 grossInputAmount
    ) internal returns (OnReTypes.ExecutionAccounting memory accounting) {
        accounting = previewExecution(offerConfigId, offer, grossInputAmount);
        _settleCollectedInput(offerConfigId, offer, recipient, accounting);
    }

    function _executeCollectedFromUser(
        bytes32 offerConfigId,
        OnReTypes.OfferConfig storage offer,
        uint256 grossInputAmount,
        uint256 minimumAmountOut
    ) private returns (uint256 amountOut) {
        OnReTypes.ExecutionAccounting memory accounting = previewExecution(offerConfigId, offer, grossInputAmount);
        if (accounting.amountOut < minimumAmountOut) {
            revert IOnReAppErrors.MinimumAmountOutNotMetError(minimumAmountOut, accounting.amountOut);
        }
        LibOnReVault.pullExactTokenAmount(offer.tokenIn, msg.sender, grossInputAmount);
        _settleCollectedInput(offerConfigId, offer, msg.sender, accounting);
        return accounting.amountOut;
    }

    function _settleCollectedInput(
        bytes32 offerConfigId,
        OnReTypes.OfferConfig storage offer,
        address recipient,
        OnReTypes.ExecutionAccounting memory accounting
    ) private {
        OnReTypes.FeeConfig storage feeConfig = LibOnReValidation.requireExecutableFeeConfig(offer.feeConfigId);
        LibOnReVault.accrue(feeConfig.feeVaultId, offer.tokenIn, accounting.feeAmount);

        if (offer.direction == OnReTypes.OfferDirection.AssetToOnRe) {
            _settleAssetToOnRe(offer, recipient, accounting);
        } else {
            _settleOnReToAsset(offerConfigId, offer, recipient, accounting);
        }

        emit IOnReAppEvents.OfferExecuted(
            offerConfigId,
            recipient,
            offer.flow,
            accounting.grossInputAmount,
            accounting.feeAmount,
            accounting.netInputAmount,
            accounting.amountOut,
            accounting.price,
            accounting.liquidityRefillAmount,
            accounting.proceedsAmount
        );
    }

    function _settleAssetToOnRe(
        OnReTypes.OfferConfig storage offer,
        address recipient,
        OnReTypes.ExecutionAccounting memory accounting
    ) private {
        accounting.liquidityRefillAmount = _calculateLiquidityRefill(offer, accounting.netInputAmount);
        accounting.proceedsAmount = accounting.netInputAmount - accounting.liquidityRefillAmount;
        LibOnReVault.accrue(offer.liquidityVaultId, offer.tokenIn, accounting.liquidityRefillAmount);
        LibOnReVault.accrue(offer.proceedsVaultId, offer.tokenIn, accounting.proceedsAmount);
        address inventorySource = LibOnReStorage.appStorage().onReTokenConfigs[offer.tokenOut].inventorySource;
        LibOnReVault.transferExactTokenAmountFrom(offer.tokenOut, inventorySource, recipient, accounting.amountOut);
    }

    function _settleOnReToAsset(
        bytes32 offerConfigId,
        OnReTypes.OfferConfig storage offer,
        address recipient,
        OnReTypes.ExecutionAccounting memory accounting
    ) private {
        if (offer.liquidityVaultId == bytes32(0)) {
            revert IOnReAppErrors.LiquidityVaultRequiredError(offerConfigId);
        }
        IOnReToken(offer.tokenIn).burn(accounting.netInputAmount);
        LibOnReVault.consumeLiquidity(offer.liquidityVaultId, offer.tokenOut, recipient, accounting.amountOut);
    }

    function _calculateLiquidityRefill(OnReTypes.OfferConfig storage offer, uint256 netInputAmount)
        private
        view
        returns (uint256)
    {
        if (offer.liquidityVaultId == bytes32(0) || netInputAmount == 0) return 0;
        OnReTypes.ConfigurableVault storage liquidityVault =
            LibOnReValidation.requireVaultKind(offer.liquidityVaultId, OnReTypes.ConfigurableVaultKind.Liquidity);
        if (liquidityVault.refillTargetBps == 0) return 0;

        address onReToken = _onReToken(offer);
        uint256 tvl = LibOnReMarketStats.currentTvl(onReToken);
        return OnReMath.calculateRedemptionVaultRefillAmount(
            tvl,
            liquidityVault.refillTargetBps,
            MAX_BASIS_POINTS,
            offer.tokenInDecimals,
            LibOnReStorage.appStorage().onReTokenConfigs[onReToken].decimals,
            LibOnReVault.balance(offer.liquidityVaultId, offer.tokenIn),
            netInputAmount
        );
    }

    function _onReToken(OnReTypes.OfferConfig storage offer) private view returns (address) {
        return offer.direction == OnReTypes.OfferDirection.AssetToOnRe ? offer.tokenOut : offer.tokenIn;
    }
}
