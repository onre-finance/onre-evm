// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../interfaces/IDiamondLoupe.sol";
import {IOnReAccessControl} from "../../interfaces/IOnReAccessControl.sol";
import {IOnReConfig} from "../../interfaces/IOnReConfig.sol";
import {IOnRePricer} from "../../interfaces/IOnRePricer.sol";
import {IOnReQuoter} from "../../interfaces/IOnReQuoter.sol";
import {IOnReOffer} from "../../interfaces/IOnReOffer.sol";
import {IOnReFulfillment} from "../../interfaces/IOnReFulfillment.sol";
import {IOnReConfigurableVault} from "../../interfaces/IOnReConfigurableVault.sol";
import {IOnReView} from "../../interfaces/IOnReView.sol";
import {IOnReMarketStats} from "../../interfaces/IOnReMarketStats.sol";

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

    function marketStats() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IOnReMarketStats.marketStats.selector;
    }

    function accessControl() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](14);
        selectors[0] = IAccessControl.hasRole.selector;
        selectors[1] = IAccessControl.getRoleAdmin.selector;
        selectors[2] = IAccessControl.grantRole.selector;
        selectors[3] = IAccessControl.revokeRole.selector;
        selectors[4] = IAccessControl.renounceRole.selector;
        selectors[5] = IOnReAccessControl.DEFAULT_ADMIN_ROLE.selector;
        selectors[6] = IOnReAccessControl.ADMIN_ROLE.selector;
        selectors[7] = IOnReAccessControl.WORKER_ROLE.selector;
        selectors[8] = IOnReAccessControl.boss.selector;
        selectors[9] = IOnReAccessControl.pendingBoss.selector;
        selectors[10] = IOnReAccessControl.beginBossTransfer.selector;
        selectors[11] = IOnReAccessControl.cancelBossTransfer.selector;
        selectors[12] = IOnReAccessControl.acceptBossTransfer.selector;
        selectors[13] = IOnReAccessControl.UPGRADER_ROLE.selector;
    }

    function config() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = IOnReConfig.registerOnReToken.selector;
        selectors[1] = IOnReConfig.setOnReTokenEnabled.selector;
        selectors[2] = IOnReConfig.setOnReTokenInventorySource.selector;
        selectors[3] = IOnReConfig.addExcludedSupplyAddress.selector;
        selectors[4] = IOnReConfig.removeExcludedSupplyAddress.selector;
        selectors[5] = IOnReConfig.addApprover.selector;
        selectors[6] = IOnReConfig.removeApprover.selector;
        selectors[7] = IOnReConfig.setKillSwitch.selector;
    }

    function pricer() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = IOnRePricer.createPricer.selector;
        selectors[1] = IOnRePricer.addPricingVector.selector;
        selectors[2] = IOnRePricer.deletePricingVector.selector;
        selectors[3] = IOnRePricer.deleteAllPricingVectors.selector;
        selectors[4] = IOnRePricer.setPricerDisabled.selector;
        selectors[5] = IOnRePricer.currentPrice.selector;
    }

    function quoter() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IOnReQuoter.createQuoter.selector;
        selectors[1] = IOnReQuoter.setQuoterDisabled.selector;
        selectors[2] = IOnReQuoter.quote.selector;
    }

    function offer() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = IOnReOffer.createFeeConfig.selector;
        selectors[1] = IOnReOffer.updateFeeConfig.selector;
        selectors[2] = IOnReOffer.setFeeConfigEnabled.selector;
        selectors[3] = IOnReOffer.makeOfferConfig.selector;
        selectors[4] = IOnReOffer.updateOfferConfigReferences.selector;
        selectors[5] = IOnReOffer.setOfferConfigDisabled.selector;
        selectors[6] = IOnReOffer.takeOffer.selector;
        selectors[7] = IOnReOffer.previewExecution.selector;
    }

    function fulfillment() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IOnReFulfillment.createFulfillmentRequest.selector;
        selectors[1] = IOnReFulfillment.cancelFulfillmentRequest.selector;
        selectors[2] = IOnReFulfillment.fulfillWorkerRequest.selector;
    }

    function viewFunctions() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = IOnReView.getOnReTokenConfig.selector;
        selectors[1] = IOnReView.getPricer.selector;
        selectors[2] = IOnReView.getPricingVector.selector;
        selectors[3] = IOnReView.getQuoter.selector;
        selectors[4] = IOnReView.getFeeConfig.selector;
        selectors[5] = IOnReView.getOfferConfig.selector;
        selectors[6] = IOnReView.getFulfillmentRequest.selector;
        selectors[7] = IOnReView.getConfigurableVault.selector;
        selectors[8] = IOnReView.getExcludedSupplyAccounts.selector;
        selectors[9] = IOnReView.appConfig.selector;
    }

    function configurableVault() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IOnReConfigurableVault.createConfigurableVault.selector;
        selectors[1] = IOnReConfigurableVault.updateConfigurableVault.selector;
        selectors[2] = IOnReConfigurableVault.depositConfigurableVault.selector;
        selectors[3] = IOnReConfigurableVault.withdrawConfigurableVault.selector;
        selectors[4] = IOnReConfigurableVault.configurableVaultBalance.selector;
    }
}
