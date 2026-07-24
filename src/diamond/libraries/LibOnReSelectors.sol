// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../interfaces/IDiamondLoupe.sol";
import {IDiamondOwnership} from "../interfaces/IDiamondOwnership.sol";
import {IOnReApp} from "../../interfaces/IOnReApp.sol";
import {IOnReAccessControl} from "../../interfaces/IOnReAccessControl.sol";

/// @notice Canonical selector sets for fresh OnRe Diamond deployments.
/// @dev Existing deployments should use loupe output plus an explicit upgrade manifest.
library LibOnReSelectors {
    function diamondCut() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IDiamondCut.diamondCut.selector;
    }

    function diamondLoupe() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IDiamondLoupe.facets.selector;
        selectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        selectors[2] = IDiamondLoupe.facetAddresses.selector;
        selectors[3] = IDiamondLoupe.facetAddress.selector;
        selectors[4] = IERC165.supportsInterface.selector;
    }

    function diamondOwnership() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IDiamondOwnership.owner.selector;
        selectors[1] = IDiamondOwnership.transferOwnership.selector;
    }

    function marketStats() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IOnReApp.marketStats.selector;
    }

    function accessControl() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = IAccessControl.hasRole.selector;
        selectors[1] = IAccessControl.getRoleAdmin.selector;
        selectors[2] = IAccessControl.grantRole.selector;
        selectors[3] = IAccessControl.revokeRole.selector;
        selectors[4] = IAccessControl.renounceRole.selector;
        selectors[5] = IOnReAccessControl.DEFAULT_ADMIN_ROLE.selector;
        selectors[6] = IOnReAccessControl.CONFIG_ADMIN_ROLE.selector;
        selectors[7] = IOnReAccessControl.WORKER_ROLE.selector;
        selectors[8] = IOnReAccessControl.VAULT_ADMIN_ROLE.selector;
        selectors[9] = IOnReAccessControl.PAUSER_ROLE.selector;
    }

    function config() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = IOnReApp.registerOnReToken.selector;
        selectors[1] = IOnReApp.setOnReTokenEnabled.selector;
        selectors[2] = IOnReApp.setOnReTokenInventorySource.selector;
        selectors[3] = IOnReApp.addExcludedSupplyAddress.selector;
        selectors[4] = IOnReApp.removeExcludedSupplyAddress.selector;
        selectors[5] = IOnReApp.addApprover.selector;
        selectors[6] = IOnReApp.removeApprover.selector;
        selectors[7] = IOnReApp.setKillSwitch.selector;
    }

    function pricer() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = IOnReApp.createPricer.selector;
        selectors[1] = IOnReApp.addPricingVector.selector;
        selectors[2] = IOnReApp.deletePricingVector.selector;
        selectors[3] = IOnReApp.deleteAllPricingVectors.selector;
        selectors[4] = IOnReApp.setPricerDisabled.selector;
        selectors[5] = IOnReApp.currentPrice.selector;
    }

    function quoter() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IOnReApp.createQuoter.selector;
        selectors[1] = IOnReApp.setQuoterDisabled.selector;
        selectors[2] = IOnReApp.quote.selector;
    }

    function offer() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = IOnReApp.createFeeConfig.selector;
        selectors[1] = IOnReApp.updateFeeConfig.selector;
        selectors[2] = IOnReApp.setFeeConfigEnabled.selector;
        selectors[3] = IOnReApp.makeOfferConfig.selector;
        selectors[4] = IOnReApp.updateOfferConfigReferences.selector;
        selectors[5] = IOnReApp.setOfferConfigDisabled.selector;
        selectors[6] = IOnReApp.takeOffer.selector;
        selectors[7] = IOnReApp.previewExecution.selector;
    }

    function fulfillment() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IOnReApp.createFulfillmentRequest.selector;
        selectors[1] = IOnReApp.cancelFulfillmentRequest.selector;
        selectors[2] = IOnReApp.fulfillWorkerRequest.selector;
    }

    function viewFunctions() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = IOnReApp.getOnReTokenConfig.selector;
        selectors[1] = IOnReApp.getPricer.selector;
        selectors[2] = IOnReApp.getPricingVector.selector;
        selectors[3] = IOnReApp.getQuoter.selector;
        selectors[4] = IOnReApp.getFeeConfig.selector;
        selectors[5] = IOnReApp.getOfferConfig.selector;
        selectors[6] = IOnReApp.getFulfillmentRequest.selector;
        selectors[7] = IOnReApp.getConfigurableVault.selector;
        selectors[8] = IOnReApp.getExcludedSupplyAccounts.selector;
        selectors[9] = IOnReApp.appConfig.selector;
    }

    function configurableVault() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IOnReApp.createConfigurableVault.selector;
        selectors[1] = IOnReApp.updateConfigurableVault.selector;
        selectors[2] = IOnReApp.depositConfigurableVault.selector;
        selectors[3] = IOnReApp.withdrawConfigurableVault.selector;
        selectors[4] = IOnReApp.configurableVaultBalance.selector;
    }
}
