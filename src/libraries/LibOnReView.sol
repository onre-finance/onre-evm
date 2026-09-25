// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {InvalidQuoterKindError, VectorIndexOutOfBoundsError} from "../types/OnReAppErrors.sol";
import {
    ConfigurableVault,
    FeeConfig,
    FulfillmentRequest,
    OfferConfig,
    ManagedTokenConfig,
    Pricer,
    PricingVector,
    PropAmmState,
    Quoter,
    QuoterKind
} from "../types/OnReTypes.sol";

/// @notice Read helpers shared by the view facet.
/// @dev Object getters require existence, but permit disabled records and reads while killed.
library LibOnReView {
    function _getManagedTokenConfig(address managedToken) internal view returns (ManagedTokenConfig memory) {
        LibOnReValidation._requireRegisteredManagedToken(managedToken);
        return LibOnReStorage._appStorage().managedTokenConfigs[managedToken];
    }

    function _getPricer(bytes32 pricerId) internal view returns (Pricer memory) {
        return LibOnReValidation._requirePricer(pricerId);
    }

    function _getPricingVector(bytes32 pricerId, uint8 vectorIndex) internal view returns (PricingVector memory) {
        Pricer storage pricer = LibOnReValidation._requirePricer(pricerId);
        if (vectorIndex >= pricer.vectorCount) {
            revert VectorIndexOutOfBoundsError(vectorIndex, pricer.vectorCount);
        }
        return pricer.vectors[vectorIndex];
    }

    function _getQuoter(bytes32 quoterId) internal view returns (Quoter memory) {
        return LibOnReValidation._requireQuoter(quoterId);
    }

    function _getPropAmmState(bytes32 quoterId) internal view returns (PropAmmState memory) {
        Quoter storage quoter = LibOnReValidation._requireQuoter(quoterId);
        if (quoter.kind != QuoterKind.PropAmm) {
            revert InvalidQuoterKindError(quoterId, uint8(QuoterKind.PropAmm), uint8(quoter.kind));
        }
        return LibOnReStorage._appStorage().propAmmStates[quoterId];
    }

    function _getFeeConfig(bytes32 feeConfigId) internal view returns (FeeConfig memory) {
        return LibOnReValidation._requireFeeConfig(feeConfigId);
    }

    function _getOfferConfig(bytes32 offerConfigId) internal view returns (OfferConfig memory) {
        return LibOnReValidation._requireOfferConfig(offerConfigId);
    }

    function _getFulfillmentRequest(bytes32 fulfillmentRequestId) internal view returns (FulfillmentRequest memory) {
        return LibOnReValidation._requireFulfillmentRequest(fulfillmentRequestId);
    }

    function _getConfigurableVault(bytes32 vaultId) internal view returns (ConfigurableVault memory) {
        return LibOnReValidation._requireConfigurableVault(vaultId);
    }

    function _getExcludedSupplyAccounts(address managedToken) internal view returns (address[] memory) {
        LibOnReValidation._requireRegisteredManagedToken(managedToken);
        return LibOnReStorage._appStorage().excludedSupplyAccounts[managedToken];
    }

    function _appConfig() internal view returns (bool isKilled, address approver1, address approver2) {
        LibOnReStorage.AppStorage storage s = LibOnReStorage._appStorage();
        (isKilled, approver1, approver2) = (s.isKilled, s.approver1, s.approver2);
    }

    function _permissionlessSettlementAccount() internal view returns (address) {
        return LibOnReStorage._appStorage().permissionlessSettlementAccount;
    }
}
