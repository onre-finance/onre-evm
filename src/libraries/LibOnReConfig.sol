// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {IManagedToken} from "../IManagedToken.sol";
import {
    ExcludedSupplyAddressAlreadyExistsError,
    ExcludedSupplyAddressNotFoundError,
    InvalidDecimalsError,
    InvalidTokenError,
    NoChangeError,
    TokenAlreadyRegisteredError,
    TooManyExcludedSupplyAddressesError,
    ZeroAddressError
} from "../types/OnReAppErrors.sol";
import {
    ExcludedSupplyAddressAdded,
    ExcludedSupplyAddressRemoved,
    ManagedTokenEnabledSet,
    ManagedTokenRegistered
} from "../types/OnReAppEvents.sol";
import {ManagedTokenConfig} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice managed-token registration and supply-exclusion configuration.
library LibOnReConfig {
    uint8 internal constant MAX_EXCLUDED_SUPPLY_ADDRESSES = 20;

    function _registerManagedToken(address managedToken) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (managedToken == address(0)) revert ZeroAddressError();

        ManagedTokenConfig storage config = LibOnReStorage._appStorage().managedTokenConfigs[managedToken];
        if (config.exists) revert TokenAlreadyRegisteredError(managedToken);
        if (!ERC165Checker.supportsInterface(managedToken, type(IManagedToken).interfaceId)) {
            revert InvalidTokenError();
        }

        uint8 decimals = IERC20Metadata(managedToken).decimals();
        if (decimals > OnReMath.MAX_TOKEN_DECIMALS) revert InvalidDecimalsError();

        config.decimals = decimals;
        config.enabled = true;
        config.exists = true;
        emit ManagedTokenRegistered(managedToken, decimals);
    }

    function _setManagedTokenEnabled(address managedToken, bool enabled) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation._requireRegisteredManagedToken(managedToken);

        ManagedTokenConfig storage config = LibOnReStorage._appStorage().managedTokenConfigs[managedToken];
        if (config.enabled == enabled) revert NoChangeError();
        config.enabled = enabled;
        emit ManagedTokenEnabledSet(managedToken, enabled);
    }

    function _addExcludedSupplyAddress(address managedToken, address account) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation._requireRegisteredManagedToken(managedToken);
        if (account == address(0)) revert ZeroAddressError();
        if (LibOnReStorage._appStorage().excludedSupplyIndexPlusOne[managedToken][account] != 0) {
            revert ExcludedSupplyAddressAlreadyExistsError(managedToken, account);
        }

        address[] storage accounts = LibOnReStorage._appStorage().excludedSupplyAccounts[managedToken];
        if (accounts.length >= MAX_EXCLUDED_SUPPLY_ADDRESSES) {
            revert TooManyExcludedSupplyAddressesError(managedToken);
        }
        accounts.push(account);
        LibOnReStorage._appStorage().excludedSupplyIndexPlusOne[managedToken][account] = accounts.length;
        emit ExcludedSupplyAddressAdded(managedToken, account);
    }

    function _removeExcludedSupplyAddress(address managedToken, address account) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation._requireRegisteredManagedToken(managedToken);
        if (account == address(0)) revert ZeroAddressError();

        uint256 indexPlusOne = LibOnReStorage._appStorage().excludedSupplyIndexPlusOne[managedToken][account];
        if (indexPlusOne == 0) {
            revert ExcludedSupplyAddressNotFoundError(managedToken, account);
        }

        address[] storage accounts = LibOnReStorage._appStorage().excludedSupplyAccounts[managedToken];
        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = accounts.length - 1;
        if (index != lastIndex) {
            address lastAccount = accounts[lastIndex];
            accounts[index] = lastAccount;
            LibOnReStorage._appStorage().excludedSupplyIndexPlusOne[managedToken][lastAccount] = index + 1;
        }
        accounts.pop();
        delete LibOnReStorage._appStorage().excludedSupplyIndexPlusOne[managedToken][account];
        emit ExcludedSupplyAddressRemoved(managedToken, account);
    }
}
