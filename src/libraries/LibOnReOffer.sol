// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    InvalidAmountError,
    InvalidApprovalError,
    InvalidOfferDirectionError,
    InvalidPermissionlessSettlementAccountError,
    MinimumAmountOutNotMetError,
    PermissionlessSettlementAccountNotSetError,
    TakeOfferDeadlineExpiredError,
    UnsupportedOfferFlowError,
    WorkerOfferRequiresFulfillmentRequestError
} from "../types/OnReAppErrors.sol";
import {OfferExecuted} from "../types/OnReAppEvents.sol";
import {IOnReToken} from "../IOnReToken.sol";
import {
    ConfigurableVault,
    ExecutionAccounting,
    FeeConfig,
    OfferConfig,
    OfferDirection,
    OfferFlow,
    QuoteResult,
    TakeOfferParams
} from "../types/OnReTypes.sol";
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

    function _takeOffer(TakeOfferParams calldata params) internal returns (uint256 amountOut) {
        OfferConfig storage offer = LibOnReValidation._requireExecutableOfferConfig(params.offerConfigId);
        if (block.timestamp > params.deadline) {
            revert TakeOfferDeadlineExpiredError(params.deadline);
        }

        _validateTakeOfferFlow(params, offer.flow);

        amountOut =
            _executeCollectedFromUser(params.offerConfigId, offer, params.grossInputAmount, params.minimumAmountOut);
    }

    function _previewExecution(bytes32 offerConfigId, uint256 grossInputAmount)
        internal
        view
        returns (ExecutionAccounting memory accounting)
    {
        OfferConfig storage offer = LibOnReValidation._requireExecutableOfferConfig(offerConfigId);
        accounting = _previewExecution(offer, grossInputAmount);
    }

    function _previewExecution(OfferConfig storage offer, uint256 grossInputAmount)
        internal
        view
        returns (ExecutionAccounting memory accounting)
    {
        if (grossInputAmount == 0) revert InvalidAmountError();
        FeeConfig storage feeConfig = LibOnReValidation._requireExecutableFeeConfig(offer.feeConfigId);
        uint256 feeAmount = LibOnReFeeConfig._calculateFee(grossInputAmount, feeConfig);
        uint256 netInputAmount = grossInputAmount - feeAmount;
        if (netInputAmount == 0) revert InvalidAmountError();
        QuoteResult memory quoteResult = LibOnReQuoter._quote(offer, netInputAmount);

        accounting = ExecutionAccounting({
            price: quoteResult.price,
            grossInputAmount: grossInputAmount,
            feeAmount: feeAmount,
            netInputAmount: netInputAmount,
            amountOut: quoteResult.amountOut,
            liquidityRefillAmount: 0,
            proceedsAmount: 0
        });
    }

    function _settleEscrowedWorkerInput(
        bytes32 offerConfigId,
        OfferConfig storage offer,
        address recipient,
        uint256 grossInputAmount
    ) internal returns (ExecutionAccounting memory accounting) {
        accounting = _previewExecution(offer, grossInputAmount);
        LibOnReQuoter._recordExecution(offer, accounting.netInputAmount, accounting.price);
        _settleCollectedInput(offerConfigId, offer, recipient, recipient, accounting);
    }

    function _executeCollectedFromUser(
        bytes32 offerConfigId,
        OfferConfig storage offer,
        uint256 grossInputAmount,
        uint256 minimumAmountOut
    ) private returns (uint256 amountOut) {
        ExecutionAccounting memory accounting = _previewExecution(offer, grossInputAmount);
        if (accounting.amountOut < minimumAmountOut) {
            revert MinimumAmountOutNotMetError(minimumAmountOut, accounting.amountOut);
        }
        LibOnReQuoter._recordExecution(offer, accounting.netInputAmount, accounting.price);

        address outputAccount = msg.sender;
        if (offer.flow == OfferFlow.Permissionless) {
            outputAccount = _requirePermissionlessSettlementAccount(msg.sender);
            LibOnReVault._transferExactTokenAmountFrom(offer.tokenIn, msg.sender, outputAccount, grossInputAmount);
            LibOnReVault._transferExactTokenAmountFrom(offer.tokenIn, outputAccount, address(this), grossInputAmount);
        } else {
            LibOnReVault._pullExactTokenAmount(offer.tokenIn, msg.sender, grossInputAmount);
        }

        _settleCollectedInput(offerConfigId, offer, msg.sender, outputAccount, accounting);
        amountOut = accounting.amountOut;
    }

    function _settleCollectedInput(
        bytes32 offerConfigId,
        OfferConfig storage offer,
        address recipient,
        address outputAccount,
        ExecutionAccounting memory accounting
    ) private {
        FeeConfig storage feeConfig = LibOnReValidation._requireExecutableFeeConfig(offer.feeConfigId);
        LibOnReVault._accrue(feeConfig.feeVaultId, offer.tokenIn, accounting.feeAmount);

        if (offer.direction == OfferDirection.AssetToOnRe) {
            _settleAssetToOnRe(offer, outputAccount, accounting);
        } else if (offer.direction == OfferDirection.OnReToAsset) {
            _settleOnReToAsset(offer, outputAccount, accounting);
        } else {
            revert InvalidOfferDirectionError();
        }

        if (outputAccount != recipient) {
            LibOnReVault._transferExactTokenAmountFrom(offer.tokenOut, outputAccount, recipient, accounting.amountOut);
        }

        emit OfferExecuted(
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

    function _settleAssetToOnRe(OfferConfig storage offer, address recipient, ExecutionAccounting memory accounting)
        private
    {
        accounting.liquidityRefillAmount = _calculateLiquidityRefill(offer, accounting.netInputAmount);
        accounting.proceedsAmount = accounting.netInputAmount - accounting.liquidityRefillAmount;
        LibOnReVault._accrue(offer.liquidityVaultId, offer.tokenIn, accounting.liquidityRefillAmount);
        LibOnReVault._accrue(offer.proceedsVaultId, offer.tokenIn, accounting.proceedsAmount);
        IOnReToken(offer.tokenOut).mint(recipient, accounting.amountOut);
    }

    function _settleOnReToAsset(OfferConfig storage offer, address recipient, ExecutionAccounting memory accounting)
        private
    {
        IOnReToken(offer.tokenIn).burn(accounting.netInputAmount);
        LibOnReVault._consumeLiquidity(offer.liquidityVaultId, offer.tokenOut, recipient, accounting.amountOut);
    }

    function _calculateLiquidityRefill(OfferConfig storage offer, uint256 netInputAmount)
        private
        view
        returns (uint256)
    {
        if (offer.liquidityVaultId == bytes32(0) || netInputAmount == 0) return 0;
        ConfigurableVault storage liquidityVault =
            LibOnReStorage._appStorage().configurableVaults[offer.liquidityVaultId];
        if (liquidityVault.refillTargetBps == 0) return 0;

        address onReToken = LibOnReValidation._offerOnReToken(offer);
        uint256 tvl = LibOnReMarketStats._currentTvl(onReToken);
        return OnReMath._calculateRedemptionVaultRefillAmount(
            tvl,
            liquidityVault.refillTargetBps,
            MAX_BASIS_POINTS,
            offer.tokenInDecimals,
            LibOnReStorage._appStorage().onReTokenConfigs[onReToken].decimals,
            LibOnReVault._balance(offer.liquidityVaultId, offer.tokenIn),
            netInputAmount
        );
    }

    function _requirePermissionlessSettlementAccount(address user) private view returns (address account) {
        account = LibOnReStorage._appStorage().permissionlessSettlementAccount;
        if (account == address(0)) revert PermissionlessSettlementAccountNotSetError();
        if (account == address(this) || account == user) {
            revert InvalidPermissionlessSettlementAccountError(account);
        }
    }

    function _validateTakeOfferFlow(TakeOfferParams calldata params, OfferFlow flow) private view {
        if (flow == OfferFlow.Permissioned) {
            if (!LibOnReApproval._isValidForUser(msg.sender, params.approval, params.signature)) {
                revert InvalidApprovalError();
            }
            return;
        }
        if (flow == OfferFlow.Permissionless) {
            if (params.approval.user != address(0) || params.approval.expiry != 0 || params.signature.length != 0) {
                revert InvalidApprovalError();
            }
            return;
        }
        if (flow == OfferFlow.Worker) revert WorkerOfferRequiresFulfillmentRequestError(params.offerConfigId);
        revert UnsupportedOfferFlowError(uint8(flow));
    }
}
