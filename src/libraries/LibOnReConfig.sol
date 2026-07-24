// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {IOnReAppEvents} from "../interfaces/IOnReAppEvents.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";

/// @notice OnRe-token registration, inventory source, and supply-exclusion configuration.
library LibOnReConfig {
    uint8 internal constant ONRE_TOKEN_DECIMALS = 9;
    uint8 internal constant MAX_EXCLUDED_SUPPLY_ADDRESSES = 20;

    function registerOnReToken(address onReToken, address inventorySource) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (onReToken == address(0) || inventorySource == address(0)) revert IOnReAppErrors.ZeroAddressError();

        OnReTypes.OnReTokenConfig storage config = LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
        if (config.enabled || config.decimals != 0) {
            revert IOnReAppErrors.TokenAlreadyRegisteredError(onReToken);
        }

        uint8 decimals = IERC20Metadata(onReToken).decimals();
        if (decimals != ONRE_TOKEN_DECIMALS) revert IOnReAppErrors.InvalidTokenError();

        config.inventorySource = inventorySource;
        config.enabled = true;
        config.decimals = decimals;
        emit IOnReAppEvents.OnReTokenRegistered(onReToken, inventorySource, decimals);
    }

    function setOnReTokenEnabled(address onReToken, bool enabled) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation.requireRegisteredOnReToken(onReToken);

        OnReTypes.OnReTokenConfig storage config = LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
        if (config.enabled == enabled) revert IOnReAppErrors.NoChangeError();
        config.enabled = enabled;
        emit IOnReAppEvents.OnReTokenEnabledSet(onReToken, enabled);
    }

    function setOnReTokenInventorySource(address onReToken, address inventorySource) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation.requireRegisteredOnReToken(onReToken);
        if (inventorySource == address(0)) revert IOnReAppErrors.ZeroAddressError();

        OnReTypes.OnReTokenConfig storage config = LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
        address oldInventorySource = config.inventorySource;
        if (oldInventorySource == inventorySource) revert IOnReAppErrors.NoChangeError();
        config.inventorySource = inventorySource;
        emit IOnReAppEvents.OnReTokenInventorySourceUpdated(onReToken, oldInventorySource, inventorySource);
    }

    function addExcludedSupplyAddress(address onReToken, address account) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation.requireRegisteredOnReToken(onReToken);
        if (account == address(0)) revert IOnReAppErrors.ZeroAddressError();
        if (LibOnReStorage.appStorage().excludedSupplyIndexPlusOne[onReToken][account] != 0) {
            revert IOnReAppErrors.ExcludedSupplyAddressAlreadyExistsError(onReToken, account);
        }

        address[] storage accounts = LibOnReStorage.appStorage().excludedSupplyAccounts[onReToken];
        if (accounts.length >= MAX_EXCLUDED_SUPPLY_ADDRESSES) {
            revert IOnReAppErrors.TooManyExcludedSupplyAddressesError(onReToken);
        }
        accounts.push(account);
        LibOnReStorage.appStorage().excludedSupplyIndexPlusOne[onReToken][account] = accounts.length;
        emit IOnReAppEvents.ExcludedSupplyAddressAdded(onReToken, account);
    }

    function removeExcludedSupplyAddress(address onReToken, address account) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation.requireRegisteredOnReToken(onReToken);
        if (account == address(0)) revert IOnReAppErrors.ZeroAddressError();

        uint256 indexPlusOne = LibOnReStorage.appStorage().excludedSupplyIndexPlusOne[onReToken][account];
        if (indexPlusOne == 0) {
            revert IOnReAppErrors.ExcludedSupplyAddressNotFoundError(onReToken, account);
        }

        address[] storage accounts = LibOnReStorage.appStorage().excludedSupplyAccounts[onReToken];
        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = accounts.length - 1;
        if (index != lastIndex) {
            address lastAccount = accounts[lastIndex];
            accounts[index] = lastAccount;
            LibOnReStorage.appStorage().excludedSupplyIndexPlusOne[onReToken][lastAccount] = index + 1;
        }
        accounts.pop();
        delete LibOnReStorage.appStorage().excludedSupplyIndexPlusOne[onReToken][account];
        emit IOnReAppEvents.ExcludedSupplyAddressRemoved(onReToken, account);
    }
}
