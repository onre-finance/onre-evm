// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    ExcludedSupplyAddressAlreadyExistsError,
    ExcludedSupplyAddressNotFoundError,
    InvalidTokenError,
    NoChangeError,
    TokenAlreadyRegisteredError,
    TooManyExcludedSupplyAddressesError,
    ZeroAddressError
} from "../types/OnReAppErrors.sol";
import {
    ExcludedSupplyAddressAdded,
    ExcludedSupplyAddressRemoved,
    OnReTokenEnabledSet,
    OnReTokenInventorySourceUpdated,
    OnReTokenRegistered
} from "../types/OnReAppEvents.sol";
import {OnReTokenConfig} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";

/// @notice OnRe-token registration, inventory source, and supply-exclusion configuration.
library LibOnReConfig {
    uint8 internal constant ONRE_TOKEN_DECIMALS = 9;
    uint8 internal constant MAX_EXCLUDED_SUPPLY_ADDRESSES = 20;

    function _registerOnReToken(address onReToken, address inventorySource) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (onReToken == address(0) || inventorySource == address(0)) revert ZeroAddressError();

        OnReTokenConfig storage config = LibOnReStorage._appStorage().onReTokenConfigs[onReToken];
        if (config.enabled || config.decimals != 0) {
            revert TokenAlreadyRegisteredError(onReToken);
        }

        uint8 decimals = IERC20Metadata(onReToken).decimals();
        if (decimals != ONRE_TOKEN_DECIMALS) revert InvalidTokenError();

        config.inventorySource = inventorySource;
        config.enabled = true;
        config.decimals = decimals;
        emit OnReTokenRegistered(onReToken, inventorySource, decimals);
    }

    function _setOnReTokenEnabled(address onReToken, bool enabled) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation._requireRegisteredOnReToken(onReToken);

        OnReTokenConfig storage config = LibOnReStorage._appStorage().onReTokenConfigs[onReToken];
        if (config.enabled == enabled) revert NoChangeError();
        config.enabled = enabled;
        emit OnReTokenEnabledSet(onReToken, enabled);
    }

    function _setOnReTokenInventorySource(address onReToken, address inventorySource) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation._requireRegisteredOnReToken(onReToken);
        if (inventorySource == address(0)) revert ZeroAddressError();

        OnReTokenConfig storage config = LibOnReStorage._appStorage().onReTokenConfigs[onReToken];
        address oldInventorySource = config.inventorySource;
        if (oldInventorySource == inventorySource) revert NoChangeError();
        config.inventorySource = inventorySource;
        emit OnReTokenInventorySourceUpdated(onReToken, oldInventorySource, inventorySource);
    }

    function _addExcludedSupplyAddress(address onReToken, address account) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation._requireRegisteredOnReToken(onReToken);
        if (account == address(0)) revert ZeroAddressError();
        if (LibOnReStorage._appStorage().excludedSupplyIndexPlusOne[onReToken][account] != 0) {
            revert ExcludedSupplyAddressAlreadyExistsError(onReToken, account);
        }

        address[] storage accounts = LibOnReStorage._appStorage().excludedSupplyAccounts[onReToken];
        if (accounts.length >= MAX_EXCLUDED_SUPPLY_ADDRESSES) {
            revert TooManyExcludedSupplyAddressesError(onReToken);
        }
        accounts.push(account);
        LibOnReStorage._appStorage().excludedSupplyIndexPlusOne[onReToken][account] = accounts.length;
        emit ExcludedSupplyAddressAdded(onReToken, account);
    }

    function _removeExcludedSupplyAddress(address onReToken, address account) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation._requireRegisteredOnReToken(onReToken);
        if (account == address(0)) revert ZeroAddressError();

        uint256 indexPlusOne = LibOnReStorage._appStorage().excludedSupplyIndexPlusOne[onReToken][account];
        if (indexPlusOne == 0) {
            revert ExcludedSupplyAddressNotFoundError(onReToken, account);
        }

        address[] storage accounts = LibOnReStorage._appStorage().excludedSupplyAccounts[onReToken];
        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = accounts.length - 1;
        if (index != lastIndex) {
            address lastAccount = accounts[lastIndex];
            accounts[index] = lastAccount;
            LibOnReStorage._appStorage().excludedSupplyIndexPlusOne[onReToken][lastAccount] = index + 1;
        }
        accounts.pop();
        delete LibOnReStorage._appStorage().excludedSupplyIndexPlusOne[onReToken][account];
        emit ExcludedSupplyAddressRemoved(onReToken, account);
    }
}
