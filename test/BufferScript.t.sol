// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {InitializeBuffer} from "../script/InitializeBuffer.s.sol";
import {EnvironmentScript} from "../script/base/EnvironmentScript.sol";
import {BufferAlreadyExistsError} from "../src/types/OnReAppErrors.sol";
import {BufferState, ConfigurableVaultKind} from "../src/types/OnReTypes.sol";
import {OnReAppTestBase} from "./helpers/OnReAppTestBase.sol";

contract BufferScriptHarness is InitializeBuffer {
    Environment internal environment;
    address internal managedToken;
    bool internal swapFeeVaults;

    function swapFees() external {
        swapFeeVaults = true;
    }

    function configure(address app, address safeAddress, address token) external {
        environment = Environment({chainId: 84532, diamond: app, safe: safeAddress, settlementAccount: address(0)});
        managedToken = token;
    }

    function _loadEnvironment() internal view override returns (Environment memory) {
        return environment;
    }

    function _loadBufferConfiguration() internal view override returns (BufferConfiguration memory config) {
        config = super._loadBufferConfiguration();
        config.managedToken = managedToken;
        config.reserveVault.bufferManagedToken = managedToken;
        config.managementFeeVault.bufferManagedToken = managedToken;
        config.performanceFeeVault.bufferManagedToken = managedToken;
        config.reserveVault.withdrawalDestination = environment.safe;
        config.managementFeeVault.withdrawalDestination = environment.safe;
        config.performanceFeeVault.withdrawalDestination = environment.safe;
        if (swapFeeVaults) {
            VaultDefinition memory management = config.managementFeeVault;
            config.managementFeeVault = config.performanceFeeVault;
            config.performanceFeeVault = management;
        }
    }

    function transactions() external view returns (SafeTx[] memory) {
        return _txs;
    }
}

contract BufferScriptTest is OnReAppTestBase {
    BufferScriptHarness internal setupScript;

    function setUp() public override {
        super.setUp();
        vm.chainId(84532);
        managedToken.mint(user, 1_000_000e9);
        setupScript = new BufferScriptHarness();
        setupScript.configure(address(app), address(this), address(managedToken));
    }

    function test_InitializesVaultsAndSeedsSupplyWithoutMinting() public {
        uint256 supply = managedToken.totalSupply();
        setupScript.run();
        _assertSetup(supply);
        assertEq(setupScript.transactions().length, 7);
        assertEq(managedToken.balanceOf(address(app)), 0);
    }

    function test_PrintedTransactionsCanBeReplayedAsSafeAndAccrueToAllThreeVaults() public {
        uint256 supply = managedToken.totalSupply();
        uint256 snapshot = vm.snapshotState();
        setupScript.run();
        InitializeBuffer.SafeTx[] memory txs = setupScript.transactions();
        vm.revertToState(snapshot);

        // Replay only the exported calls at a later execution time.
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < txs.length; ++i) {
            (bool ok, bytes memory result) = txs[i].to.call(txs[i].data);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(result, 32), mload(result))
                }
            }
        }
        _assertSetup(supply);
        assertEq(managedToken.totalSupply(), supply);
        vm.warp(block.timestamp + 365 days);
        vm.prank(worker);
        app.settleBuffer(address(managedToken));
        BufferState memory state = app.getBufferState(address(managedToken));
        uint256 minted = supply / 5;
        uint256 management = minted * 300 / 2_000;
        uint256 performance = (minted - management) * 500 / 10_000;
        assertEq(app.configurableVaultBalance(state.managementFeeVaultId, address(managedToken)), management);
        assertEq(app.configurableVaultBalance(state.performanceFeeVaultId, address(managedToken)), performance);
        assertEq(
            app.configurableVaultBalance(state.reserveVaultId, address(managedToken)), minted - management - performance
        );
        assertEq(managedToken.balanceOf(address(app)), minted);
    }

    function test_RejectsMainnetEvenWithBaseSepoliaEnvironment() public {
        vm.chainId(1);
        vm.expectRevert("BUFFER setup is Base Sepolia only");
        setupScript.run();
    }

    function test_RejectsBothMainnetEnvironmentsEvenOnBaseSepolia() public {
        InitializeBuffer productionScript = new InitializeBuffer();
        vm.setEnv("ONRE_ENV", "ethereum-mainnet-test");
        vm.expectRevert("BUFFER setup is Base Sepolia only");
        productionScript.run();
        vm.setEnv("ONRE_ENV", "ethereum-mainnet-live");
        vm.expectRevert("BUFFER setup is Base Sepolia only");
        productionScript.run();
    }

    function test_RejectsExistingBuffer() public {
        app.initializeBuffer(address(managedToken));
        vm.expectRevert(abi.encodeWithSelector(BufferAlreadyExistsError.selector, address(managedToken)));
        setupScript.run();
    }

    function test_DoesNotReplaceAnotherController() public {
        managedToken.setBufferController(address(usd));
        vm.expectRevert("Managed token has another BUFFER controller");
        setupScript.run();
    }

    function test_RejectsNamedVaultWithWrongBufferRole() public {
        setupScript.swapFees();
        vm.expectRevert("Named vault does not match BUFFER role/token");
        setupScript.run();
    }

    function _assertSetup(uint256 supply) private view {
        BufferState memory state = app.getBufferState(address(managedToken));
        assertTrue(state.exists);
        assertEq(state.grossApr, 200_000);
        assertEq(state.managementFeeBasisPoints, 300);
        assertEq(state.performanceFeeBasisPoints, 500);
        assertTrue(state.performanceFeeHighWatermarkEnabled);
        assertEq(state.previousSupply, supply);
        assertEq(state.performanceFeeHighWatermark, 1e9);
        assertEq(state.lastAccrualTimestamp, block.timestamp);
        assertEq(managedToken.bufferController(), address(app));
        assertEq(uint8(app.getConfigurableVault(state.reserveVaultId).kind), uint8(ConfigurableVaultKind.BufferReserve));
        assertEq(uint8(app.getConfigurableVault(state.managementFeeVaultId).kind), uint8(ConfigurableVaultKind.Fee));
        assertEq(uint8(app.getConfigurableVault(state.performanceFeeVaultId).kind), uint8(ConfigurableVaultKind.Fee));
        assertEq(app.getConfigurableVault(state.reserveVaultId).withdrawalDestination, address(this));
        assertEq(app.getConfigurableVault(state.managementFeeVaultId).withdrawalDestination, address(this));
        assertEq(app.getConfigurableVault(state.performanceFeeVaultId).withdrawalDestination, address(this));
    }
}
