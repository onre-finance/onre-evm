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

/// @notice Token, approver, gateway, and emergency configuration.
library LibOnReConfig {
    uint8 internal constant ONRE_TOKEN_DECIMALS = 9;
    uint8 internal constant MAX_EXCLUDED_SUPPLY_ADDRESSES = 20;

    function registerOnReToken(address onReToken, uint256 maxSupply, uint256 maxMintAmount) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
        if (onReToken == address(0)) revert IOnReAppErrors.ZeroAddressError();

        OnReTypes.OnReTokenConfig storage config = LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
        if (config.enabled || config.decimals != 0) {
            revert IOnReAppErrors.TokenAlreadyRegisteredError(onReToken);
        }

        uint8 decimals = IERC20Metadata(onReToken).decimals();
        if (decimals != ONRE_TOKEN_DECIMALS) revert IOnReAppErrors.InvalidTokenError();

        config.enabled = true;
        config.decimals = decimals;
        config.maxSupply = maxSupply;
        config.maxMintAmount = maxMintAmount;
        emit IOnReAppEvents.OnReTokenRegistered(onReToken, decimals, maxSupply, maxMintAmount);
    }

    function setOnReTokenEnabled(address onReToken, bool enabled) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
        LibOnReValidation.requireRegisteredOnReToken(onReToken);

        OnReTypes.OnReTokenConfig storage config = LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
        if (config.enabled == enabled) revert IOnReAppErrors.NoChangeError();
        config.enabled = enabled;
        emit IOnReAppEvents.OnReTokenEnabledSet(onReToken, enabled);
    }

    function setOnReTokenLimits(address onReToken, uint256 maxSupply, uint256 maxMintAmount) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
        LibOnReValidation.requireRegisteredOnReToken(onReToken);

        OnReTypes.OnReTokenConfig storage config = LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
        if (config.maxSupply == maxSupply && config.maxMintAmount == maxMintAmount) {
            revert IOnReAppErrors.NoChangeError();
        }
        config.maxSupply = maxSupply;
        config.maxMintAmount = maxMintAmount;
        emit IOnReAppEvents.OnReTokenLimitsUpdated(onReToken, maxSupply, maxMintAmount);
    }

    function addExcludedSupplyAddress(address onReToken, address account) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
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
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
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

    function setMintGateway(address newMintGateway) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
        if (newMintGateway == address(0)) revert IOnReAppErrors.ZeroAddressError();

        address oldMintGateway = LibOnReStorage.appStorage().mintGateway;
        if (oldMintGateway == newMintGateway) revert IOnReAppErrors.NoChangeError();
        LibOnReStorage.appStorage().mintGateway = newMintGateway;
        emit IOnReAppEvents.MintGatewayUpdated(oldMintGateway, newMintGateway);
    }

    function addApprover(address approver) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
        _addApprover(approver);
    }

    function removeApprover(address approver) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.CONFIG_ADMIN_ROLE);
        if (approver == address(0)) revert IOnReAppErrors.ZeroAddressError();

        if (LibOnReStorage.appStorage().approver1 == approver) {
            LibOnReStorage.appStorage().approver1 = address(0);
        } else if (LibOnReStorage.appStorage().approver2 == approver) {
            LibOnReStorage.appStorage().approver2 = address(0);
        } else {
            revert IOnReAppErrors.NotApproverError(approver);
        }
        emit IOnReAppEvents.ApproverRemoved(approver);
    }

    function setKillSwitch(bool killed) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.PAUSER_ROLE);
        if (LibOnReStorage.appStorage().isKilled == killed) revert IOnReAppErrors.NoChangeError();
        LibOnReStorage.appStorage().isKilled = killed;
        emit IOnReAppEvents.KillSwitchSet(killed);
    }

    function _addApprover(address approver) internal {
        if (approver == address(0)) revert IOnReAppErrors.ZeroAddressError();
        if (approver == LibOnReStorage.appStorage().approver1 || approver == LibOnReStorage.appStorage().approver2) {
            revert IOnReAppErrors.ApproverAlreadyExistsError(approver);
        }

        if (LibOnReStorage.appStorage().approver1 == address(0)) {
            LibOnReStorage.appStorage().approver1 = approver;
        } else if (LibOnReStorage.appStorage().approver2 == address(0)) {
            LibOnReStorage.appStorage().approver2 = approver;
        } else {
            revert IOnReAppErrors.BothApproversFilledError();
        }
        emit IOnReAppEvents.ApproverAdded(approver);
    }
}
