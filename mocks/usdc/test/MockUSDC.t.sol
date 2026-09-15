// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import {MockUSDC} from "../src/MockUSDC.sol";

interface Vm {
    function prank(address sender) external;
    function expectRevert() external;
    function expectRevert(bytes calldata reason) external;
    function addr(uint256 privateKey) external returns (address);
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8, bytes32, bytes32);
    function warp(uint256 timestamp) external;
}

contract MockUSDCtest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant ADMIN = 0x99CDC01fF619EB512F50161B296D0910a5b06738;
    address private constant USER = address(0x1234);
    MockUSDC private token;

    function setUp() public {
        token = new MockUSDC(ADMIN);
    }

    function test_ConstructorInitializesAndLocksAllVersions() public {
        require(token.decimals() == 6, "decimals");
        require(keccak256(bytes(token.name())) == keccak256("Mock USD Coin"), "name");
        require(keccak256(bytes(token.symbol())) == keccak256("USDC"), "symbol");
        require(token.owner() == ADMIN && token.pauser() == ADMIN, "owner/pauser");
        require(token.blacklister() == ADMIN && token.masterMinter() == ADMIN, "roles");
        require(token.totalSupply() == 0 && token.isBlacklisted(address(token)), "fresh state");
        vm.expectRevert();
        token.initialize("Other", "OTHER", "USD", 18, USER, USER, USER, USER);
        vm.expectRevert();
        token.initializeV2("Other");
        vm.expectRevert();
        token.initializeV2_1(USER);
        vm.expectRevert();
        token.initializeV2_2(new address[](0), "OTHER");
        vm.expectRevert();
        new MockUSDC(address(0));
    }

    function test_PublicMintNeedsNoRoleOrAllowanceAndTransfersNormally() public {
        require(!token.isMinter(USER), "unexpected minter");
        vm.prank(USER);
        require(token.mint(USER, 1_000_000 * 1e6), "mint");
        vm.prank(USER);
        token.approve(address(this), 2 * 1e6);
        token.transferFrom(USER, ADMIN, 2 * 1e6);
        require(token.balanceOf(ADMIN) == 2 * 1e6, "transfer");
        require(token.totalSupply() == 1_000_000 * 1e6, "supply");
    }

    function test_PublicMintPreservesPauseAndBlacklistRules() public {
        vm.prank(ADMIN);
        token.pause();
        vm.expectRevert();
        token.mint(USER, 1e6);
        vm.prank(ADMIN);
        token.unpause();
        vm.prank(ADMIN);
        token.blacklist(USER);
        vm.expectRevert();
        token.mint(USER, 1e6);
        vm.expectRevert();
        vm.prank(USER);
        token.mint(ADMIN, 1e6);
        vm.prank(ADMIN);
        token.unBlacklist(USER);
        token.mint(USER, 1e6);
        require(token.balanceOf(USER) == 1e6, "unblacklisted mint");
        vm.expectRevert();
        vm.prank(USER);
        token.pause();
    }

    function test_InvalidMintAndBalanceLimitRevertAtomically() public {
        vm.expectRevert();
        token.mint(address(0), 1);
        vm.expectRevert();
        token.mint(USER, 0);
        token.mint(USER, (uint256(1) << 255) - 1);
        vm.expectRevert();
        token.mint(USER, 1);
        require(token.totalSupply() == (uint256(1) << 255) - 1, "supply rollback");
    }

    function test_PermitUsesInitializedDomainAndRejectsReplay() public {
        uint256 key = 0xA11CE;
        address holder = vm.addr(key);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 hash = keccak256(abi.encode(token.PERMIT_TYPEHASH(), holder, USER, 1e6, 0, deadline));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, _digest(hash));
        token.permit(holder, USER, 1e6, deadline, v, r, s);
        require(token.allowance(holder, USER) == 1e6 && token.nonces(holder) == 1, "permit");
        vm.expectRevert();
        token.permit(holder, USER, 1e6, deadline, v, r, s);
    }

    function test_TransferWithAuthorizationAndReplayProtection() public {
        vm.warp(100);
        uint256 key = 0xA11CE;
        address holder = vm.addr(key);
        token.mint(holder, 2e6);
        bytes32 nonce = keccak256("transfer");
        bytes32 hash =
            keccak256(abi.encode(token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(), holder, USER, 1e6, 0, 1000, nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, _digest(hash));
        token.transferWithAuthorization(holder, USER, 1e6, 0, 1000, nonce, abi.encodePacked(r, s, v));
        require(token.balanceOf(USER) == 1e6 && token.authorizationState(holder, nonce), "authorization");
        vm.expectRevert();
        token.transferWithAuthorization(holder, USER, 1e6, 0, 1000, nonce, abi.encodePacked(r, s, v));
    }

    function test_ContractWalletPermitUsesERC1271() public {
        AcceptingWallet wallet = new AcceptingWallet();
        token.permit(address(wallet), USER, 1e6, block.timestamp + 1 days, hex"1234");
        require(token.allowance(address(wallet), USER) == 1e6, "ERC1271 permit");
    }

    function test_NoUpgradeEntryPoint() public {
        vm.prank(ADMIN);
        (bool success,) = address(token).call(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", USER, ""));
        require(!success, "upgrade exposed");
    }

    function _digest(bytes32 hash) private view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), hash));
    }
}

contract AcceptingWallet {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0x1626ba7e;
    }
}
