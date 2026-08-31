// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReManagedTokenFactory} from "../libraries/LibOnReManagedTokenFactory.sol";

contract OnReManagedTokenFactoryFacet {
    /// @notice Deploys, initializes, and registers a managed token.
    /// @dev The Diamond is always added to the supplied initial minter and burner sets.
    function deployManagedToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address admin,
        address ccipAdmin,
        address[] calldata initialMinters,
        address[] calldata initialBurners
    ) external returns (address managedToken) {
        return LibOnReManagedTokenFactory._deployManagedToken(
            name, symbol, decimals, admin, ccipAdmin, initialMinters, initialBurners
        );
    }

    /// @notice Changes the UUPS implementation used only for future deployments.
    function setManagedTokenImplementation(address newImplementation) external {
        LibOnReManagedTokenFactory._setManagedTokenImplementation(newImplementation);
    }

    function managedTokenImplementation() external view returns (address) {
        return LibOnReManagedTokenFactory._managedTokenImplementation();
    }

    function deployedManagedTokenCount() external view returns (uint256) {
        return LibOnReManagedTokenFactory._deployedManagedTokenCount();
    }

    function deployedManagedTokenAt(uint256 index) external view returns (address) {
        return LibOnReManagedTokenFactory._deployedManagedTokenAt(index);
    }

    function getDeployedManagedTokens() external view returns (address[] memory) {
        return LibOnReManagedTokenFactory._getDeployedManagedTokens();
    }

    function isManagedTokenDeployed(address managedToken) external view returns (bool) {
        return LibOnReManagedTokenFactory._isManagedTokenDeployed(managedToken);
    }
}
