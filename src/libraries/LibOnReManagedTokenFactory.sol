// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {IManagedToken} from "../IManagedToken.sol";
import {ManagedToken} from "../ManagedToken.sol";
import {InvalidManagedTokenBeaconError} from "../types/OnReAppErrors.sol";
import {ManagedTokenBeaconConfigured, ManagedTokenDeployed} from "../types/OnReAppEvents.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReConfig} from "./LibOnReConfig.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";

/// @notice Diamond-owned deployment and enumeration of canonical managed tokens.
library LibOnReManagedTokenFactory {
    function _initialize(address beacon) internal {
        _validateBeacon(beacon);
        LibOnReStorage._appStorage().managedTokenBeacon = beacon;
        emit ManagedTokenBeaconConfigured(beacon);
    }

    function _deployManagedToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address admin,
        address ccipAdmin,
        address[] calldata initialMinters,
        address[] calldata initialBurners
    ) internal returns (address managedToken) {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);

        address[] memory minters = _withDiamond(initialMinters);
        address[] memory burners = _withDiamond(initialBurners);
        IManagedToken.InitializeParams memory params = IManagedToken.InitializeParams({
            name: name,
            symbol: symbol,
            decimals: decimals,
            admin: admin,
            ccipAdmin: ccipAdmin,
            initialMinters: minters,
            initialBurners: burners
        });

        LibOnReStorage.AppStorage storage s = LibOnReStorage._appStorage();
        managedToken = address(new BeaconProxy(s.managedTokenBeacon, abi.encodeCall(ManagedToken.initialize, (params))));

        s.deployedManagedTokens.push(managedToken);
        s.managedTokenDeployedByDiamond[managedToken] = true;
        LibOnReConfig._registerManagedToken(managedToken);

        emit ManagedTokenDeployed(managedToken, admin, ccipAdmin, name, symbol, decimals);
    }

    function _managedTokenBeacon() internal view returns (address) {
        return LibOnReStorage._appStorage().managedTokenBeacon;
    }

    function _deployedManagedTokenCount() internal view returns (uint256) {
        return LibOnReStorage._appStorage().deployedManagedTokens.length;
    }

    function _deployedManagedTokenAt(uint256 index) internal view returns (address) {
        return LibOnReStorage._appStorage().deployedManagedTokens[index];
    }

    function _getDeployedManagedTokens() internal view returns (address[] memory) {
        return LibOnReStorage._appStorage().deployedManagedTokens;
    }

    function _isManagedTokenDeployed(address managedToken) internal view returns (bool) {
        return LibOnReStorage._appStorage().managedTokenDeployedByDiamond[managedToken];
    }

    function _validateBeacon(address beacon) private view {
        if (beacon == address(0) || beacon.code.length == 0) {
            revert InvalidManagedTokenBeaconError(beacon);
        }

        try IBeacon(beacon).implementation() returns (address implementation) {
            if (
                implementation.code.length == 0
                    || !ERC165Checker.supportsInterface(implementation, type(IManagedToken).interfaceId)
            ) {
                revert InvalidManagedTokenBeaconError(beacon);
            }
        } catch {
            revert InvalidManagedTokenBeaconError(beacon);
        }
    }

    function _withDiamond(address[] calldata accounts) private view returns (address[] memory result) {
        uint256 length = accounts.length;
        result = new address[](length + 1);
        result[0] = address(this);
        for (uint256 i = 0; i < length;) {
            result[i + 1] = accounts[i];
            unchecked {
                ++i;
            }
        }
    }
}
