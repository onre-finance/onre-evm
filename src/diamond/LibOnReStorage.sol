// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {
    BufferState,
    ConfigurableVault,
    FeeConfig,
    FulfillmentRequest,
    OfferConfig,
    ManagedTokenConfig,
    Pricer,
    PropAmmState,
    Quoter
} from "../types/OnReTypes.sol";

library LibOnReStorage {
    /// @custom:storage-location erc7201:onre.storage.App
    struct AppStorage {
        mapping(address managedToken => ManagedTokenConfig config) managedTokenConfigs;
        mapping(bytes32 pricerId => Pricer pricer) pricers;
        mapping(bytes32 quoterId => Quoter quoter) quoters;
        mapping(bytes32 feeConfigId => FeeConfig feeConfig) feeConfigs;
        mapping(bytes32 vaultId => ConfigurableVault vault) configurableVaults;
        mapping(bytes32 vaultId => mapping(address token => uint256 amount)) configurableVaultBalances;
        mapping(bytes32 offerConfigId => OfferConfig offerConfig) offerConfigs;
        mapping(bytes32 requestId => FulfillmentRequest request) fulfillmentRequests;
        mapping(address managedToken => address[] accounts) excludedSupplyAccounts;
        mapping(address managedToken => mapping(address account => uint256 indexPlusOne)) excludedSupplyIndexPlusOne;
        bool initialized;
        bool isKilled;
        address approver1;
        address approver2;
        mapping(bytes32 quoterId => PropAmmState state) propAmmStates;
        address permissionlessSettlementAccount;
        mapping(address managedToken => BufferState state) bufferStates;
        address[] deployedManagedTokens;
        mapping(address managedToken => bool deployedByDiamond) managedTokenDeployedByDiamond;
    }

    bytes32 internal constant APP_STORAGE_LOCATION = 0x31164558df59313d3ca3903acf513b2eda293f9424839a72cebf9d8c78813700;

    function _appStorage() internal pure returns (AppStorage storage s) {
        bytes32 location = APP_STORAGE_LOCATION;
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            s.slot := location
        }
    }
}
