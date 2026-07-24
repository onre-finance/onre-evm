// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IOnReAppErrors} from "./IOnReAppErrors.sol";
import {IOnReAppEvents} from "./IOnReAppEvents.sol";
import {IOnReAccessControl} from "./IOnReAccessControl.sol";
import {OnReTypes} from "../types/OnReTypes.sol";

interface IOnReApp is IOnReAppEvents, IOnReAppErrors, IOnReAccessControl {
    function registerOnReToken(address onReToken, address inventorySource) external;
    function setOnReTokenEnabled(address onReToken, bool enabled) external;
    function setOnReTokenInventorySource(address onReToken, address inventorySource) external;
    function addExcludedSupplyAddress(address onReToken, address account) external;
    function removeExcludedSupplyAddress(address onReToken, address account) external;
    function addApprover(address approver) external;
    function removeApprover(address approver) external;
    function setKillSwitch(bool killed) external;

    function createPricer(address onReToken, OnReTypes.PricingDenomination denomination)
        external
        returns (bytes32 pricerId);
    function addPricingVector(bytes32 pricerId, OnReTypes.PricingVector calldata vector) external;
    function deletePricingVector(bytes32 pricerId, uint64 startTime) external;
    function deleteAllPricingVectors(bytes32 pricerId) external;
    function setPricerDisabled(bytes32 pricerId, bool disabled) external;
    function currentPrice(bytes32 pricerId) external view returns (uint256);

    function createQuoter(OnReTypes.QuoterKind kind, uint64 quoterInstanceId) external returns (bytes32 quoterId);
    function setQuoterDisabled(bytes32 quoterId, bool disabled) external;
    function quote(bytes32 offerConfigId, uint256 netInputAmount)
        external
        view
        returns (OnReTypes.QuoteResult memory result);

    function createFeeConfig(uint64 feeConfigInstanceId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId)
        external
        returns (bytes32 feeConfigId);
    function updateFeeConfig(bytes32 feeConfigId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId)
        external;
    function setFeeConfigEnabled(bytes32 feeConfigId, bool enabled) external;

    function makeOfferConfig(OnReTypes.MakeOfferConfigParams calldata params) external returns (bytes32 offerConfigId);
    function updateOfferConfigReferences(
        bytes32 offerConfigId,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) external;
    function setOfferConfigDisabled(bytes32 offerConfigId, bool disabled) external;
    function takeOffer(OnReTypes.TakeOfferParams calldata params) external returns (uint256 amountOut);
    function previewExecution(bytes32 offerConfigId, uint256 grossInputAmount)
        external
        view
        returns (OnReTypes.ExecutionAccounting memory accounting);

    function createFulfillmentRequest(bytes32 offerConfigId, uint64 requestId, uint256 inputAmount)
        external
        returns (bytes32 fulfillmentRequestId);
    function cancelFulfillmentRequest(bytes32 fulfillmentRequestId) external;
    function fulfillWorkerRequest(bytes32 fulfillmentRequestId, uint256 inputAmount)
        external
        returns (uint256 amountOut);

    function createConfigurableVault(
        OnReTypes.ConfigurableVaultKind kind,
        uint64 vaultInstanceId,
        address withdrawalDestination,
        uint16 refillTargetBps
    ) external returns (bytes32 vaultId);
    function updateConfigurableVault(bytes32 vaultId, address withdrawalDestination, uint16 refillTargetBps) external;
    function depositConfigurableVault(bytes32 vaultId, address token, uint256 amount) external;
    function withdrawConfigurableVault(bytes32 vaultId, address token, uint256 amount)
        external
        returns (uint256 withdrawnAmount);
    function configurableVaultBalance(bytes32 vaultId, address token) external view returns (uint256);

    function marketStats(address onReToken) external view returns (OnReTypes.MarketStats memory stats);
    function getOnReTokenConfig(address onReToken) external view returns (OnReTypes.OnReTokenConfig memory);
    function getPricer(bytes32 pricerId) external view returns (OnReTypes.Pricer memory);
    function getPricingVector(bytes32 pricerId, uint8 vectorIndex)
        external
        view
        returns (OnReTypes.PricingVector memory);
    function getQuoter(bytes32 quoterId) external view returns (OnReTypes.Quoter memory);
    function getFeeConfig(bytes32 feeConfigId) external view returns (OnReTypes.FeeConfig memory);
    function getOfferConfig(bytes32 offerConfigId) external view returns (OnReTypes.OfferConfig memory);
    function getFulfillmentRequest(bytes32 fulfillmentRequestId)
        external
        view
        returns (OnReTypes.FulfillmentRequest memory);
    function getConfigurableVault(bytes32 vaultId) external view returns (OnReTypes.ConfigurableVault memory);
    function getExcludedSupplyAccounts(address onReToken) external view returns (address[] memory);
    function appConfig() external view returns (bool isKilled, address approver1, address approver2);
}
