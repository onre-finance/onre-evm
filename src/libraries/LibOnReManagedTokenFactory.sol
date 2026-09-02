// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC1822Proxiable} from "@openzeppelin/contracts/interfaces/draft-IERC1822.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {IManagedToken} from "../IManagedToken.sol";
import {ManagedToken} from "../ManagedToken.sol";
import {InvalidManagedTokenImplementationError} from "../types/OnReAppErrors.sol";
import {ManagedTokenDeployed} from "../types/OnReAppEvents.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReConfig} from "./LibOnReConfig.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";

/// @notice Diamond-owned deployment and enumeration of canonical managed tokens.
library LibOnReManagedTokenFactory {
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function _deployManagedToken(
        address implementation,
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address admin,
        address ccipAdmin,
        address[] calldata initialMinters,
        address[] calldata initialBurners
    ) internal returns (address managedToken) {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        _validateImplementation(implementation);

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
        managedToken = address(new ERC1967Proxy(implementation, abi.encodeCall(ManagedToken.initialize, (params))));

        s.deployedManagedTokens.push(managedToken);
        s.managedTokenDeployedByDiamond[managedToken] = true;
        LibOnReConfig._registerManagedToken(managedToken);

        emit ManagedTokenDeployed(managedToken, admin, ccipAdmin, implementation, name, symbol, decimals);
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

    function _validateImplementation(address implementation) private view {
        if (
            implementation == address(0) || implementation.code.length == 0
                || !ERC165Checker.supportsInterface(implementation, type(IManagedToken).interfaceId)
        ) {
            revert InvalidManagedTokenImplementationError(implementation);
        }

        try IERC1822Proxiable(implementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != IMPLEMENTATION_SLOT) revert InvalidManagedTokenImplementationError(implementation);
        } catch {
            revert InvalidManagedTokenImplementationError(implementation);
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
