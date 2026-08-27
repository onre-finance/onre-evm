// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IManagedToken} from "../src/IManagedToken.sol";
import {ManagedToken} from "../src/ManagedToken.sol";
import {InvalidDecimalsError} from "../src/types/OnReAppErrors.sol";
import {ManagedTokenConfig} from "../src/types/OnReTypes.sol";
import {OnReAppTestBase} from "./helpers/OnReAppTestBase.sol";

contract OnReManagedTokenFactoryFacetTest is OnReAppTestBase {
    address private tokenAdmin = makeAddr("tokenAdmin");
    address private ccipAdmin = makeAddr("ccipAdmin");
    address private additionalMinter = makeAddr("additionalMinter");
    address private additionalBurner = makeAddr("additionalBurner");
    address private beaconOwner = makeAddr("beaconOwner");

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
        assertTrue(token.isMinter(address(app)));
        assertTrue(token.isBurner(address(app)));
        assertTrue(token.isMinter(additionalMinter));
        assertTrue(token.isBurner(additionalBurner));

        ManagedTokenConfig memory config = app.getManagedTokenConfig(tokenAddress);
        assertTrue(config.exists);
        assertTrue(config.enabled);
        assertEq(config.decimals, 6);

        assertEq(app.managedTokenBeacon(), address(managedTokenBeacon));
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

    function test_BeaconOwnerRemainsSeparateAndUpgradesEveryDiamondToken() public {
        ManagedToken secondToken = ManagedToken(
            app.deployManagedToken("Managed EUR", "MEUR", 6, tokenAdmin, ccipAdmin, new address[](0), new address[](0))
        );
        DiamondManagedTokenV2 newImplementation = new DiamondManagedTokenV2();
        managedTokenBeacon.transferOwnership(beaconOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        managedTokenBeacon.upgradeTo(address(newImplementation));

        vm.prank(beaconOwner);
        managedTokenBeacon.upgradeTo(address(newImplementation));

        assertEq(DiamondManagedTokenV2(address(managedToken)).version(), 2);
        assertEq(DiamondManagedTokenV2(address(secondToken)).version(), 2);
        assertEq(managedToken.decimals(), 9);
        assertEq(secondToken.decimals(), 6);
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
}

contract DiamondManagedTokenV2 is ManagedToken {
    function version() external pure returns (uint256) {
        return 2;
    }
}
