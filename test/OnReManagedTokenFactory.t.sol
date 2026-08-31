// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IManagedToken} from "../src/IManagedToken.sol";
import {ManagedToken} from "../src/ManagedToken.sol";
import {
    InvalidDecimalsError,
    InvalidManagedTokenImplementationError,
    NoChangeError
} from "../src/types/OnReAppErrors.sol";
import {ManagedTokenConfig} from "../src/types/OnReTypes.sol";
import {OnReAppTestBase} from "./helpers/OnReAppTestBase.sol";

contract OnReManagedTokenFactoryFacetTest is OnReAppTestBase {
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address private tokenAdmin = makeAddr("tokenAdmin");
    address private ccipAdmin = makeAddr("ccipAdmin");
    address private additionalMinter = makeAddr("additionalMinter");
    address private additionalBurner = makeAddr("additionalBurner");

    function test_BossDeploysRegistersAndRecordsManagedToken() public {
        address tokenAddress = app.deployManagedToken(
            "Managed EUR",
            "MEUR",
            6,
            tokenAdmin,
            ccipAdmin,
            _singleAddress(additionalMinter),
            _singleAddress(additionalBurner)
        );

        ManagedToken token = ManagedToken(tokenAddress);
        assertEq(token.name(), "Managed EUR");
        assertEq(token.symbol(), "MEUR");
        assertEq(token.decimals(), 6);
        assertEq(token.getCCIPAdmin(), ccipAdmin);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), tokenAdmin));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), tokenAdmin));
        assertTrue(token.isMinter(address(app)));
        assertTrue(token.isBurner(address(app)));
        assertTrue(token.isMinter(additionalMinter));
        assertTrue(token.isBurner(additionalBurner));

        ManagedTokenConfig memory config = app.getManagedTokenConfig(tokenAddress);
        assertTrue(config.exists);
        assertTrue(config.enabled);
        assertEq(config.decimals, 6);

        assertEq(app.managedTokenImplementation(), managedTokenImplementation);
        assertEq(_implementationOf(tokenAddress), managedTokenImplementation);
        assertEq(app.deployedManagedTokenCount(), 2);
        assertEq(app.deployedManagedTokenAt(1), tokenAddress);
        assertTrue(app.isManagedTokenDeployed(tokenAddress));
        assertEq(app.getDeployedManagedTokens()[1], tokenAddress);
    }

    function test_OnlyBossCanDeployManagedToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, app.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        app.deployManagedToken("Managed EUR", "MEUR", 6, tokenAdmin, ccipAdmin, new address[](0), new address[](0));
    }

    function test_FailedDeploymentDoesNotRegisterOrRecordToken() public {
        uint256 countBefore = app.deployedManagedTokenCount();

        vm.expectRevert(InvalidDecimalsError.selector);
        app.deployManagedToken("Managed EUR", "MEUR", 19, tokenAdmin, ccipAdmin, new address[](0), new address[](0));
        assertEq(app.deployedManagedTokenCount(), countBefore);

        vm.expectRevert(IManagedToken.ZeroAddressError.selector);
        app.deployManagedToken(
            "Managed EUR", "MEUR", 6, tokenAdmin, ccipAdmin, _singleAddress(address(0)), new address[](0)
        );
        assertEq(app.deployedManagedTokenCount(), countBefore);
    }

    function test_TokenAdminUpgradesOnlyTheSelectedDiamondToken() public {
        ManagedToken secondToken = ManagedToken(
            app.deployManagedToken("Managed EUR", "MEUR", 6, tokenAdmin, ccipAdmin, new address[](0), new address[](0))
        );
        DiamondManagedTokenV2 newImplementation = new DiamondManagedTokenV2();

        assertEq(_implementationOf(address(managedToken)), managedTokenImplementation);
        assertEq(_implementationOf(address(secondToken)), managedTokenImplementation);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, secondToken.UPGRADER_ROLE()
            )
        );
        vm.prank(user);
        secondToken.upgradeToAndCall(address(newImplementation), "");

        vm.prank(tokenAdmin);
        secondToken.upgradeToAndCall(address(newImplementation), "");

        assertEq(_implementationOf(address(managedToken)), managedTokenImplementation);
        assertEq(_implementationOf(address(secondToken)), address(newImplementation));
        (bool firstUpgraded,) = address(managedToken).staticcall(abi.encodeCall(DiamondManagedTokenV2.version, ()));
        assertFalse(firstUpgraded);
        assertEq(DiamondManagedTokenV2(address(secondToken)).version(), 2);
        assertEq(managedToken.decimals(), 9);
        assertEq(secondToken.decimals(), 6);
    }

    function test_BossChangesImplementationOnlyForFutureDeployments() public {
        DiamondManagedTokenV2 newImplementation = new DiamondManagedTokenV2();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, app.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        app.setManagedTokenImplementation(address(newImplementation));

        vm.expectRevert(abi.encodeWithSelector(InvalidManagedTokenImplementationError.selector, address(0)));
        app.setManagedTokenImplementation(address(0));

        vm.expectRevert(abi.encodeWithSelector(InvalidManagedTokenImplementationError.selector, user));
        app.setManagedTokenImplementation(user);

        IncompatibleManagedTokenImplementation incompatible = new IncompatibleManagedTokenImplementation();
        vm.expectRevert(abi.encodeWithSelector(InvalidManagedTokenImplementationError.selector, address(incompatible)));
        app.setManagedTokenImplementation(address(incompatible));

        vm.expectRevert(NoChangeError.selector);
        app.setManagedTokenImplementation(managedTokenImplementation);

        app.setManagedTokenImplementation(address(newImplementation));
        ManagedToken futureToken = ManagedToken(
            app.deployManagedToken("Managed EUR", "MEUR", 6, tokenAdmin, ccipAdmin, new address[](0), new address[](0))
        );

        assertEq(app.managedTokenImplementation(), address(newImplementation));
        assertEq(_implementationOf(address(managedToken)), managedTokenImplementation);
        assertEq(_implementationOf(address(futureToken)), address(newImplementation));
        assertEq(DiamondManagedTokenV2(address(futureToken)).version(), 2);
    }

    function test_ExternallyRegisteredTokenIsNotInDiamondDeploymentRegistry() public {
        ManagedToken externalToken = _deployToken(address(app), 6);
        uint256 countBefore = app.deployedManagedTokenCount();

        app.registerManagedToken(address(externalToken));

        assertTrue(app.getManagedTokenConfig(address(externalToken)).exists);
        assertFalse(app.isManagedTokenDeployed(address(externalToken)));
        assertEq(app.deployedManagedTokenCount(), countBefore);
    }

    function _singleAddress(address account) private pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account;
    }

    function _implementationOf(address proxy) private view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }
}

contract DiamondManagedTokenV2 is ManagedToken {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract IncompatibleManagedTokenImplementation {}
