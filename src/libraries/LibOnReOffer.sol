// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {IOnReAppEvents} from "../interfaces/IOnReAppEvents.sol";
import {IOnReMintGateway} from "../interfaces/IOnReMintGateway.sol";
import {IOnReToken} from "../interfaces/IOnReToken.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnRePricer} from "./LibOnRePricer.sol";
import {LibOnReQuoter} from "./LibOnReQuoter.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {LibOnReVault} from "./LibOnReVault.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Pair-and-flow offer configuration, fee policy, and direct execution.
library LibOnReOffer {
    bytes32 private constant APPROVAL_TYPEHASH = keccak256("ApprovalMessage(address user,uint64 expiry)");
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant EIP712_NAME_HASH = keccak256("OnReApp");
    bytes32 private constant EIP712_VERSION_HASH = keccak256("1");

    uint16 internal constant MAX_BASIS_POINTS = 10_000;
    uint16 internal constant MAX_ALLOWED_FEE_BPS = 1_000;

    function createFeeConfig(uint64 feeConfigInstanceId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId)
        internal
        returns (bytes32 feeConfigId)
    {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
        _validateFeePolicy(basisPoints, feeVaultId);

        feeConfigId = OnReIds.feeConfigId(feeConfigInstanceId);
        OnReTypes.FeeConfig storage feeConfig = LibOnReStorage.appStorage().feeConfigs[feeConfigId];
        if (feeConfig.exists) revert IOnReAppErrors.FeeConfigAlreadyExistsError(feeConfigId);

        feeConfig.feeConfigId = feeConfigInstanceId;
        feeConfig.basisPoints = basisPoints;
        feeConfig.minimumAmount = minimumAmount;
        feeConfig.feeVaultId = feeVaultId;
        feeConfig.enabled = true;
        feeConfig.exists = true;
        emit IOnReAppEvents.FeeConfigCreated(feeConfigId, feeConfigInstanceId, basisPoints, minimumAmount, feeVaultId);
    }

    function updateFeeConfig(bytes32 feeConfigId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId)
        internal
    {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
        _validateFeePolicy(basisPoints, feeVaultId);
        OnReTypes.FeeConfig storage feeConfig = LibOnReValidation.requireFeeConfig(feeConfigId);
        if (
            feeConfig.basisPoints == basisPoints && feeConfig.minimumAmount == minimumAmount
                && feeConfig.feeVaultId == feeVaultId
        ) {
            revert IOnReAppErrors.NoChangeError();
        }

        feeConfig.basisPoints = basisPoints;
        feeConfig.minimumAmount = minimumAmount;
        feeConfig.feeVaultId = feeVaultId;
        emit IOnReAppEvents.FeeConfigUpdated(feeConfigId, basisPoints, minimumAmount, feeVaultId);
    }

    function setFeeConfigEnabled(bytes32 feeConfigId, bool enabled) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
        OnReTypes.FeeConfig storage feeConfig = LibOnReValidation.requireFeeConfig(feeConfigId);
        if (feeConfig.enabled == enabled) revert IOnReAppErrors.NoChangeError();
        feeConfig.enabled = enabled;
        emit IOnReAppEvents.FeeConfigEnabledSet(feeConfigId, enabled);
    }

    function makeOfferConfig(OnReTypes.MakeOfferConfigParams calldata params) internal returns (bytes32 offerConfigId) {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
        if (params.tokenIn == address(0) || params.tokenOut == address(0)) {
            revert IOnReAppErrors.ZeroAddressError();
        }
        if (params.tokenIn == params.tokenOut) revert IOnReAppErrors.InvalidTokenError();

        OnReTypes.Pricer storage pricer = LibOnReValidation.requirePricer(params.pricerId);
        OnReTypes.OfferDirection direction = _deriveDirection(params.tokenIn, params.tokenOut, pricer.onReToken);
        uint8 tokenInDecimals = IERC20Metadata(params.tokenIn).decimals();
        uint8 tokenOutDecimals = IERC20Metadata(params.tokenOut).decimals();
        if (tokenInDecimals > OnReMath.MAX_TOKEN_DECIMALS || tokenOutDecimals > OnReMath.MAX_TOKEN_DECIMALS) {
            revert IOnReAppErrors.InvalidDecimalsError();
        }

        offerConfigId = OnReIds.offerConfigId(params.tokenIn, params.tokenOut, params.flow);
        OnReTypes.OfferConfig storage offer = LibOnReStorage.appStorage().offerConfigs[offerConfigId];
        if (offer.exists) revert IOnReAppErrors.OfferConfigAlreadyExistsError(offerConfigId);

        offer.tokenIn = params.tokenIn;
        offer.tokenOut = params.tokenOut;
        offer.flow = params.flow;
        offer.direction = direction;
        offer.tokenInDecimals = tokenInDecimals;
        offer.tokenOutDecimals = tokenOutDecimals;
        offer.exists = true;
        _setOfferReferences(
            offerConfigId,
            offer,
            params.pricerId,
            params.quoterId,
            params.feeConfigId,
            params.proceedsVaultId,
            params.liquidityVaultId
        );

        emit IOnReAppEvents.OfferConfigCreated(
            offerConfigId,
            params.tokenIn,
            params.tokenOut,
            params.flow,
            direction,
            params.pricerId,
            params.quoterId,
            params.feeConfigId,
            params.proceedsVaultId,
            params.liquidityVaultId
        );
    }

    function updateOfferConfigReferences(
        bytes32 offerConfigId,
        bytes32 pricerId,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
        OnReTypes.OfferConfig storage offer = LibOnReValidation.requireOfferConfig(offerConfigId);
        if (
            offer.pricerId == pricerId && offer.quoterId == quoterId && offer.feeConfigId == feeConfigId
                && offer.proceedsVaultId == proceedsVaultId && offer.liquidityVaultId == liquidityVaultId
        ) {
            revert IOnReAppErrors.NoChangeError();
        }
        _setOfferReferences(offerConfigId, offer, pricerId, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId);
        emit IOnReAppEvents.OfferConfigReferencesUpdated(
            offerConfigId, pricerId, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId
        );
    }

    function setOfferConfigDisabled(bytes32 offerConfigId, bool disabled) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
        OnReTypes.OfferConfig storage offer = LibOnReValidation.requireOfferConfig(offerConfigId);
        if (offer.disabled == disabled) revert IOnReAppErrors.NoChangeError();
        offer.disabled = disabled;
        emit IOnReAppEvents.OfferConfigDisabledSet(offerConfigId, disabled);
    }

    function takeOffer(OnReTypes.TakeOfferParams calldata params) internal returns (uint256 amountOut) {
        OnReTypes.OfferConfig storage offer = LibOnReValidation.requireExecutableOfferConfig(params.offerConfigId);
        if (block.timestamp > params.deadline) {
            revert IOnReAppErrors.TakeOfferDeadlineExpiredError(params.deadline);
        }

        if (offer.flow == OnReTypes.OfferFlow.Permissioned) {
            if (!_isValidApprovalForUser(msg.sender, params.approval, params.signature)) {
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
        uint256 feeAmount = _calculateFee(grossInputAmount, feeConfig);
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
        LibOnReValidation.validateMintLimits(offer.tokenOut, accounting.amountOut);
        address configuredMintGateway = LibOnReStorage.appStorage().mintGateway;
        if (configuredMintGateway == address(0)) revert IOnReAppErrors.MintGatewayNotSetError();

        accounting.liquidityRefillAmount = _calculateLiquidityRefill(offer, accounting.netInputAmount);
        accounting.proceedsAmount = accounting.netInputAmount - accounting.liquidityRefillAmount;
        LibOnReVault.accrue(offer.liquidityVaultId, offer.tokenIn, accounting.liquidityRefillAmount);
        LibOnReVault.accrue(offer.proceedsVaultId, offer.tokenIn, accounting.proceedsAmount);
        IOnReMintGateway(configuredMintGateway).mint(offer.tokenOut, recipient, accounting.amountOut);
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

        OnReTypes.Pricer storage pricer = LibOnReValidation.requirePricer(offer.pricerId);
        uint256 tvl = LibOnRePricer.currentTvl(pricer.onReToken, offer.pricerId);
        return OnReMath.calculateRedemptionVaultRefillAmount(
            tvl,
            liquidityVault.refillTargetBps,
            MAX_BASIS_POINTS,
            offer.tokenInDecimals,
            LibOnReStorage.appStorage().onReTokenConfigs[pricer.onReToken].decimals,
            LibOnReVault.balance(offer.liquidityVaultId, offer.tokenIn),
            netInputAmount
        );
    }

    function _setOfferReferences(
        bytes32 offerConfigId,
        OnReTypes.OfferConfig storage offer,
        bytes32 pricerId,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) private {
        OnReTypes.Pricer storage pricer = LibOnReValidation.requirePricer(pricerId);
        if (pricer.onReToken != _onReToken(offer)) revert IOnReAppErrors.InvalidTokenError();

        LibOnReValidation.requireQuoter(quoterId);
        OnReTypes.FeeConfig storage feeConfig = LibOnReValidation.requireFeeConfig(feeConfigId);
        LibOnReValidation.requireVaultKind(feeConfig.feeVaultId, OnReTypes.ConfigurableVaultKind.Fee);
        LibOnReValidation.requireVaultKind(proceedsVaultId, OnReTypes.ConfigurableVaultKind.Proceeds);
        if (liquidityVaultId != bytes32(0)) {
            LibOnReValidation.requireVaultKind(liquidityVaultId, OnReTypes.ConfigurableVaultKind.Liquidity);
        }
        if (offer.direction == OnReTypes.OfferDirection.OnReToAsset && liquidityVaultId == bytes32(0)) {
            revert IOnReAppErrors.LiquidityVaultRequiredError(offerConfigId);
        }

        offer.pricerId = pricerId;
        offer.quoterId = quoterId;
        offer.feeConfigId = feeConfigId;
        offer.proceedsVaultId = proceedsVaultId;
        offer.liquidityVaultId = liquidityVaultId;
        LibOnReQuoter.validateFlowQuoter(offerConfigId, offer);
    }

    function _validateFeePolicy(uint16 basisPoints, bytes32 feeVaultId) private view {
        if (basisPoints > MAX_ALLOWED_FEE_BPS) revert IOnReAppErrors.InvalidFeeError();
        LibOnReValidation.requireVaultKind(feeVaultId, OnReTypes.ConfigurableVaultKind.Fee);
    }

    function _calculateFee(uint256 grossInputAmount, OnReTypes.FeeConfig storage feeConfig)
        private
        view
        returns (uint256 feeAmount)
    {
        feeAmount = Math.mulDiv(grossInputAmount, feeConfig.basisPoints, MAX_BASIS_POINTS, Math.Rounding.Ceil);
        if (feeAmount < feeConfig.minimumAmount) feeAmount = feeConfig.minimumAmount;
        if (feeAmount > grossInputAmount) revert IOnReAppErrors.InvalidFeeError();
    }

    function _deriveDirection(address tokenIn, address tokenOut, address onReToken)
        private
        view
        returns (OnReTypes.OfferDirection)
    {
        bool inputIsOnRe = tokenIn == onReToken;
        bool outputIsOnRe = tokenOut == onReToken;
        if (inputIsOnRe == outputIsOnRe) revert IOnReAppErrors.InvalidOfferDirectionError();
        LibOnReValidation.requireEnabledOnReToken(onReToken);
        return inputIsOnRe ? OnReTypes.OfferDirection.OnReToAsset : OnReTypes.OfferDirection.AssetToOnRe;
    }

    function _onReToken(OnReTypes.OfferConfig storage offer) private view returns (address) {
        return offer.direction == OnReTypes.OfferDirection.AssetToOnRe ? offer.tokenOut : offer.tokenIn;
    }

    function _isValidApprovalForUser(
        address user,
        OnReTypes.ApprovalMessage calldata approval,
        bytes calldata signature
    ) private view returns (bool) {
        // forge-lint: disable-next-line(block-timestamp)
        if (user == address(0) || approval.user != user || block.timestamp > approval.expiry) return false;
        (address signer, ECDSA.RecoverError recoverError,) =
            ECDSA.tryRecoverCalldata(_approvalDigest(approval), signature);
        return recoverError == ECDSA.RecoverError.NoError
            && (signer == LibOnReStorage.appStorage().approver1 || signer == LibOnReStorage.appStorage().approver2);
    }

    function _approvalDigest(OnReTypes.ApprovalMessage calldata approval) private view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, EIP712_NAME_HASH, EIP712_VERSION_HASH, block.chainid, address(this))
        );
        bytes32 structHash = keccak256(abi.encode(APPROVAL_TYPEHASH, approval.user, approval.expiry));
        return keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));
    }
}
