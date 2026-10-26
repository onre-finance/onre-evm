// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SetupOffers} from "../script/SetupOffers.s.sol";
import {ApproveSettlementTokens} from "../script/ApproveSettlementTokens.s.sol";
import {DepositLiquidityVault} from "../script/DepositLiquidityVault.s.sol";
import {OfferConfiguration} from "../script/base/OfferConfiguration.sol";
import {EnvironmentScript} from "../script/base/EnvironmentScript.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {ManagedToken} from "../src/ManagedToken.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import {
    OfferConfigDisabledError,
    MinimumAmountOutNotMetError,
    ConfigurableVaultNotFoundError,
    InvalidFlowQuoterError,
    InvalidOfferDirectionError
} from "../src/types/OnReAppErrors.sol";
import {
    ConfigurableVaultKind,
    ExecutionAccounting,
    InitializeParams,
    OfferConfig,
    OfferFlow,
    OfferDirection,
    Pricer,
    PricingVector,
    TakeOfferParams,
    PricingDenomination,
    QuoterKind,
    PropAmmConfig
} from "../src/types/OnReTypes.sol";
import {OnReDiamondTestHelper} from "./helpers/OnReDiamondTestHelper.sol";
import {MockUsd} from "./helpers/OnReAppTestBase.sol";

contract OfferScriptHarness is SetupOffers {
    Environment internal environment;
    Configuration internal offerConfig;

    function configure(Environment memory env, Configuration memory config) external {
        environment = env;
        offerConfig = config;
    }

    function _loadEnvironment() internal view override returns (Environment memory) {
        return environment;
    }

    function _loadOfferConfiguration() internal view override returns (Configuration memory) {
        return offerConfig;
    }

    function transactionCount() external view returns (uint256) {
        return _txs.length;
    }

    function transactionData(uint256 index) external view returns (bytes memory) {
        return _txs[index].data;
    }

    function runMatching(OfferFlow flow, OfferDirection direction, QuoterKind kind) external {
        _setupMatchingOffers(flow, direction, kind);
    }
}

contract DepositScriptHarness is DepositLiquidityVault {
    Environment internal environment;
    Configuration internal offerConfig;

    function configure(Environment memory env, Configuration memory config) external {
        environment = env;
        offerConfig = config;
    }

    function _loadEnvironment() internal view override returns (Environment memory) {
        return environment;
    }

    function _loadOfferConfiguration() internal view override returns (Configuration memory) {
        return offerConfig;
    }
}

contract SettlementApprovalHarness is ApproveSettlementTokens {
    Environment internal environment;
    Configuration internal offerConfig;

    function configure(Environment memory env, Configuration memory config) external {
        environment = env;
        offerConfig = config;
    }

    function _loadEnvironment() internal view override returns (Environment memory) {
        return environment;
    }

    function _loadOfferConfiguration() internal view override returns (Configuration memory) {
        return offerConfig;
    }

    function transactionCount() external view returns (uint256) {
        return _txs.length;
    }
}

contract OfferConfigurationHarness is OfferConfiguration {
    function parse(string memory json) external pure returns (Configuration memory) {
        return _parseOfferConfiguration(json);
    }
}

contract OfferScriptsTest is Test, OnReDiamondTestHelper {
    IDiamondProxy internal app;
    ManagedToken internal managed;
    MockUsd internal usdc;
    MockUsd internal usdg;
    OfferScriptHarness internal setupScript;
    EnvironmentScript.Environment internal environment;
    OfferConfiguration.Configuration internal config;
    address internal settlement = makeAddr("settlement");
    address internal user = makeAddr("user");

    function setUp() public {
        vm.warp(1_792_000_000);
        app = _deployDiamondApp(
            InitializeParams(address(this), makeAddr("admin"), makeAddr("worker"), address(this), new address[](0))
        );
        managed = ManagedToken(
            app.deployManagedToken(
                address(new ManagedToken()),
                "ONyc",
                "ONyc",
                9,
                address(this),
                address(this),
                new address[](0),
                new address[](0)
            )
        );
        usdc = new MockUsd();
        usdg = new MockUsd();
        environment = EnvironmentScript.Environment(block.chainid, address(app), address(this), settlement);
        config.pricers
            .push(
                OfferConfiguration.PricerDefinition(
                    "onyc-usd",
                    address(managed),
                    PricingDenomination.Usd,
                    PricingVector(0, 1_789_776_000, 1_146_935_367, 104_555, 86_400),
                    3600
                )
            );
        config.quoters
            .push(
                OfferConfiguration.QuoterDefinition(
                    "nav-permissionless",
                    QuoterKind.NavPermissionless,
                    0,
                    address(0),
                    address(0),
                    PropAmmConfig(0, 0, 0, 0, 0, 0)
                )
            );
        config.vaults.push(OfferConfiguration.VaultDefinition("fees", ConfigurableVaultKind.Fee, 0, address(this), 0));
        config.vaults
            .push(OfferConfiguration.VaultDefinition("proceeds", ConfigurableVaultKind.Proceeds, 0, address(this), 0));
        config.feeConfigs.push(OfferConfiguration.FeeDefinition("buy-fee", 0, 0, 0, "fees"));
        config.offers
            .push(
                OfferConfiguration.OfferDefinition(
                    "usdc-to-onyc",
                    address(managed),
                    address(usdc),
                    OfferDirection.AssetToManaged,
                    OfferFlow.Permissionless,
                    "onyc-usd",
                    "nav-permissionless",
                    "buy-fee",
                    "proceeds",
                    "none",
                    true
                )
            );
        config.offers
            .push(
                OfferConfiguration.OfferDefinition(
                    "usdg-to-onyc",
                    address(managed),
                    address(usdg),
                    OfferDirection.AssetToManaged,
                    OfferFlow.Permissionless,
                    "onyc-usd",
                    "nav-permissionless",
                    "buy-fee",
                    "proceeds",
                    "none",
                    true
                )
            );
        setupScript = new OfferScriptHarness();
        setupScript.configure(environment, config);
    }

    function test_SetupSharesPricerAndVaultsWithNoLiquidity() public {
        setupScript.run();
        OfferConfig memory a = app.getOfferConfig(_offer(address(usdc)));
        OfferConfig memory b = app.getOfferConfig(_offer(address(usdg)));
        assertEq(a.proceedsVaultId, b.proceedsVaultId);
        assertEq(a.feeConfigId, b.feeConfigId);
        assertEq(a.quoterId, b.quoterId);
        assertEq(a.liquidityVaultId, bytes32(0));
        assertEq(b.liquidityVaultId, bytes32(0));
        assertEq(uint8(a.flow), uint8(OfferFlow.Permissionless));
        assertEq(uint8(b.flow), uint8(OfferFlow.Permissionless));
        Pricer memory pricer = app.getPricer(OnReIds._usdPricerId(address(managed)));
        assertEq(pricer.vectorCount, 1);
        assertEq(pricer.vectors[0].baseTime, config.pricers[0].vector.baseTime);
        assertEq(pricer.vectors[0].basePrice, config.pricers[0].vector.basePrice);
        assertEq(pricer.vectors[0].apr, config.pricers[0].vector.apr);
        bytes32 liquidityId = OnReIds._configurableVaultId(ConfigurableVaultKind.Liquidity, 0);
        vm.expectRevert(abi.encodeWithSelector(ConfigurableVaultNotFoundError.selector, liquidityId));
        app.getConfigurableVault(liquidityId);
    }

    function test_TakeBothAssetsSeparatesProceedsAndEnforcesNetMinimum() public {
        config.feeConfigs[0].basisPoints = 20;
        setupScript.configure(environment, config);
        setupScript.run();
        vm.warp(block.timestamp + 3600);
        _approveSettlement();
        uint256 a = _buy(usdc, 1000e6);
        uint256 b = _buy(usdg, 500e6);
        bytes32 proceeds = OnReIds._configurableVaultId(ConfigurableVaultKind.Proceeds, 0);
        bytes32 fees = OnReIds._configurableVaultId(ConfigurableVaultKind.Fee, 0);
        assertEq(app.configurableVaultBalance(proceeds, address(usdc)), 998e6);
        assertEq(app.configurableVaultBalance(proceeds, address(usdg)), 499e6);
        assertEq(app.configurableVaultBalance(fees, address(usdc)), 2e6);
        assertEq(app.configurableVaultBalance(fees, address(usdg)), 1e6);
        assertEq(managed.balanceOf(user), a + b);
        assertEq(managed.balanceOf(settlement), 0);
        assertEq(usdc.balanceOf(settlement), 0);
        assertEq(usdg.balanceOf(settlement), 0);
    }

    function test_RerunCreatesNoAdditionalTransactionsOrVectors() public {
        setupScript.run();
        assertGt(setupScript.transactionCount(), 0);
        setupScript.run();
        assertEq(setupScript.transactionCount(), 0);
        assertEq(app.getPricer(OnReIds._usdPricerId(address(managed))).vectorCount, 1);
    }

    function test_CreateDisabledOffersAndRerunWithoutTransactions() public {
        for (uint256 i; i < config.offers.length; ++i) {
            config.offers[i].enabled = false;
        }
        setupScript.configure(environment, config);
        setupScript.run();
        uint256 count = setupScript.transactionCount();
        for (uint256 i; i < config.offers.length; ++i) {
            bytes32 offerId = _offer(config.offers[i].assetToken);
            assertFalse(app.getOfferConfig(offerId).enabled);
            // Each creation is immediately followed by its disable call in the prepared batch.
            uint256 createIndex = count - 2 * (config.offers.length - i);
            assertEq(bytes4(setupScript.transactionData(createIndex)), IDiamondProxy.makeOfferConfig.selector);
            assertEq(
                setupScript.transactionData(createIndex + 1),
                abi.encodeCall(IDiamondProxy.setOfferConfigEnabled, (offerId, false))
            );
            vm.expectRevert(abi.encodeWithSelector(OfferConfigDisabledError.selector, offerId));
            app.previewExecution(offerId, 1e6);
            TakeOfferParams memory params;
            params.offerConfigId = offerId;
            params.grossInputAmount = 1e6;
            params.deadline = uint64(block.timestamp + 60);
            vm.expectRevert(abi.encodeWithSelector(OfferConfigDisabledError.selector, offerId));
            vm.prank(user);
            app.takeOffer(params);
        }
        setupScript.run();
        assertEq(setupScript.transactionCount(), 0);
    }

    function test_ConfigDisablesExistingOffersAndRerunDoesNothing() public {
        setupScript.run();
        for (uint256 i; i < config.offers.length; ++i) {
            config.offers[i].enabled = false;
        }
        setupScript.configure(environment, config);
        setupScript.run();
        assertEq(setupScript.transactionCount(), 2);
        assertFalse(app.getOfferConfig(_offer(address(usdc))).enabled);
        assertFalse(app.getOfferConfig(_offer(address(usdg))).enabled);
        setupScript.run();
        assertEq(setupScript.transactionCount(), 0);
    }

    function test_ConfigExplicitlyReenablesOnlySelectedOffer() public {
        for (uint256 i; i < config.offers.length; ++i) {
            config.offers[i].enabled = false;
        }
        setupScript.configure(environment, config);
        setupScript.run();
        config.offers[0].enabled = true;
        setupScript.configure(environment, config);
        setupScript.run();
        assertEq(setupScript.transactionCount(), 1);
        assertTrue(app.getOfferConfig(_offer(address(usdc))).enabled);
        assertFalse(app.getOfferConfig(_offer(address(usdg))).enabled);
        vm.warp(block.timestamp + 3600);
        _approveSettlement();
        assertGt(_buy(usdc, 1000e6), 0);
        setupScript.run();
        assertEq(setupScript.transactionCount(), 0);
    }

    function test_DisableBeforeUpdatingReferencesAndKeepDisabled() public {
        setupScript.run();
        config.offers[0].enabled = false;
        config.offers[1].enabled = false;
        config.offers[1].liquidityVault = "liquidity";
        config.vaults
            .push(OfferConfiguration.VaultDefinition("liquidity", ConfigurableVaultKind.Liquidity, 0, address(this), 0));
        setupScript.configure(environment, config);
        setupScript.run();
        assertEq(
            setupScript.transactionData(1),
            abi.encodeCall(IDiamondProxy.setOfferConfigEnabled, (_offer(address(usdc)), false))
        );
        assertEq(
            setupScript.transactionData(2),
            abi.encodeCall(IDiamondProxy.setOfferConfigEnabled, (_offer(address(usdg)), false))
        );
        assertEq(bytes4(setupScript.transactionData(3)), IDiamondProxy.updateOfferConfigReferences.selector);
        assertFalse(app.getOfferConfig(_offer(address(usdg))).enabled);
        // Further reference updates work without temporarily re-enabling the disabled offer.
        config.offers[1].liquidityVault = "none";
        setupScript.configure(environment, config);
        setupScript.run();
        assertEq(setupScript.transactionCount(), 1);
        assertEq(bytes4(setupScript.transactionData(0)), IDiamondProxy.updateOfferConfigReferences.selector);
        assertFalse(app.getOfferConfig(_offer(address(usdg))).enabled);
        assertEq(app.getOfferConfig(_offer(address(usdg))).liquidityVaultId, bytes32(0));
    }

    function test_ExistingPricingMismatchIsNotSilentlyChanged() public {
        setupScript.run();
        config.pricers[0].vector.basePrice += 1;
        setupScript.configure(environment, config);
        vm.expectRevert("Existing pricing vector differs; update pricing explicitly");
        setupScript.run();
        assertEq(app.getPricer(OnReIds._usdPricerId(address(managed))).vectors[0].basePrice, 1_146_935_367);
    }

    function test_ExistingOfferLiquidityReferenceIsRemoved() public {
        setupScript.run();
        bytes32 vault = app.createConfigurableVault(ConfigurableVaultKind.Liquidity, 0, address(this), 1000);
        bytes32 offerId = _offer(address(usdc));
        OfferConfig memory offer = app.getOfferConfig(offerId);
        app.updateOfferConfigReferences(offerId, offer.quoterId, offer.feeConfigId, offer.proceedsVaultId, vault);
        setupScript.run();
        assertEq(app.getOfferConfig(offerId).liquidityVaultId, bytes32(0));
    }

    function test_MissingUsdGSettlementApprovalRollsBackTake() public {
        setupScript.run();
        vm.warp(block.timestamp + 3600);
        _approveSettlement();
        vm.prank(settlement);
        usdg.approve(address(app), 0);
        usdg.mint(user, 1000e6);
        vm.prank(user);
        usdg.approve(address(app), 1000e6);
        TakeOfferParams memory params;
        params.offerConfigId = _offer(address(usdg));
        params.grossInputAmount = 1000e6;
        params.deadline = uint64(block.timestamp + 60);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(app), 0, 1000e6)
        );
        vm.prank(user);
        app.takeOffer(params);
        assertEq(usdg.balanceOf(user), 1000e6);
        assertEq(usdg.balanceOf(address(app)), 0);
        assertEq(managed.totalSupply(), 0);
    }

    function test_DuplicateOfferIdentityIsRejectedBeforeSetup() public {
        config.offers[1].assetToken = address(usdc);
        setupScript.configure(environment, config);
        vm.expectRevert("Duplicate component identity");
        setupScript.run();
    }

    function test_CreatePermissionedAndWorkerOffersFromExplicitDefinitions() public {
        _addNavQuoter();
        config.vaults
            .push(OfferConfiguration.VaultDefinition("liquidity", ConfigurableVaultKind.Liquidity, 0, address(this), 0));
        config.offers
            .push(
                OfferConfiguration.OfferDefinition(
                    "usdc-permissioned",
                    address(managed),
                    address(usdc),
                    OfferDirection.AssetToManaged,
                    OfferFlow.Permissioned,
                    "onyc-usd",
                    "nav",
                    "buy-fee",
                    "proceeds",
                    "none",
                    true
                )
            );
        config.offers
            .push(
                OfferConfiguration.OfferDefinition(
                    "usdg-worker",
                    address(managed),
                    address(usdg),
                    OfferDirection.ManagedToAsset,
                    OfferFlow.Worker,
                    "onyc-usd",
                    "nav",
                    "buy-fee",
                    "proceeds",
                    "liquidity",
                    true
                )
            );
        setupScript.configure(environment, config);
        setupScript.run();
        bytes32 permissioned = OnReIds._offerConfigId(address(usdc), address(managed), OfferFlow.Permissioned);
        bytes32 worker = OnReIds._offerConfigId(address(managed), address(usdg), OfferFlow.Worker);
        assertEq(uint8(app.getOfferConfig(permissioned).flow), uint8(OfferFlow.Permissioned));
        assertEq(uint8(app.getOfferConfig(worker).flow), uint8(OfferFlow.Worker));
        assertEq(app.getOfferConfig(worker).tokenIn, address(managed));
        assertEq(
            app.getOfferConfig(worker).liquidityVaultId,
            OnReIds._configurableVaultId(ConfigurableVaultKind.Liquidity, 0)
        );
        assertTrue(app.getOfferConfig(_offer(address(usdc))).enabled);
    }

    function test_TwoOffersUseIndependentQuotersFeesAndFeeVaults() public {
        config.feeConfigs[0].basisPoints = 20;
        config.quoters
            .push(
                OfferConfiguration.QuoterDefinition(
                    "usdg-nav", QuoterKind.NavPermissionless, 1, address(0), address(0), PropAmmConfig(0, 0, 0, 0, 0, 0)
                )
            );
        config.vaults
            .push(OfferConfiguration.VaultDefinition("usdg-fees", ConfigurableVaultKind.Fee, 1, address(this), 0));
        config.feeConfigs.push(OfferConfiguration.FeeDefinition("usdg-fee", 1, 50, 0, "usdg-fees"));
        config.offers[1].quoter = "usdg-nav";
        config.offers[1].feeConfig = "usdg-fee";
        setupScript.configure(environment, config);
        setupScript.run();
        OfferConfig memory a = app.getOfferConfig(_offer(address(usdc)));
        OfferConfig memory b = app.getOfferConfig(_offer(address(usdg)));
        assertTrue(a.quoterId != b.quoterId);
        assertTrue(a.feeConfigId != b.feeConfigId);
        assertEq(app.getFeeConfig(a.feeConfigId).basisPoints, 20);
        assertEq(app.getFeeConfig(b.feeConfigId).basisPoints, 50);
        vm.warp(block.timestamp + 3600);
        _approveSettlement();
        uint256 outputA = _buy(usdc, 1000e6);
        uint256 outputB = _buy(usdg, 1000e6);
        assertGt(outputA, outputB);
        assertEq(app.configurableVaultBalance(a.proceedsVaultId, address(usdc)), 998e6);
        assertEq(app.configurableVaultBalance(b.proceedsVaultId, address(usdg)), 995e6);
        bytes32 feesA = app.getFeeConfig(a.feeConfigId).feeVaultId;
        bytes32 feesB = app.getFeeConfig(b.feeConfigId).feeVaultId;
        assertTrue(feesA != feesB);
        assertEq(app.configurableVaultBalance(feesA, address(usdc)), 2e6);
        assertEq(app.configurableVaultBalance(feesA, address(usdg)), 0);
        assertEq(app.configurableVaultBalance(feesB, address(usdg)), 5e6);
        assertEq(app.configurableVaultBalance(feesB, address(usdc)), 0);
    }

    function test_RejectPricerForDifferentManagedTokenBeforeSetup() public {
        config.pricers[0].managedToken = address(usdg);
        setupScript.configure(environment, config);
        vm.expectRevert("Offer pricer must be managed token USD pricer");
        setupScript.run();
    }

    function test_RejectUnknownNamedReferenceBeforeSetup() public {
        config.offers[0].quoter = "missing";
        setupScript.configure(environment, config);
        vm.expectRevert("Unknown component reference: missing");
        setupScript.run();
    }

    function test_RejectPermissionedOfferWithWrongQuoter() public {
        config.offers[0].flow = OfferFlow.Permissioned;
        setupScript.configure(environment, config);
        vm.expectRevert(InvalidFlowQuoterError.selector);
        setupScript.run();
    }

    function test_RejectWorkerBuyDirection() public {
        _addNavQuoter();
        config.offers[0].flow = OfferFlow.Worker;
        config.offers[0].quoter = "nav";
        setupScript.configure(environment, config);
        vm.expectRevert(InvalidOfferDirectionError.selector);
        setupScript.run();
    }

    function test_CreateConfiguredPropAmmQuoterAndOffer() public {
        config.quoters
            .push(
                OfferConfiguration.QuoterDefinition(
                    "prop-usdc",
                    QuoterKind.PropAmm,
                    0,
                    address(managed),
                    address(usdc),
                    PropAmmConfig(300, 19000, 20, 2000, 20000, 3650)
                )
            );
        config.offers[0].quoter = "prop-usdc";
        setupScript.configure(environment, config);
        setupScript.run();
        bytes32 quoterId = OnReIds._quoterId(QuoterKind.PropAmm, 0);
        assertEq(app.getOfferConfig(_offer(address(usdc))).quoterId, quoterId);
        assertEq(app.getPropAmmState(quoterId).assetToken, address(usdc));
        assertGt(setupScript.transactionCount(), 0);
        setupScript.run();
        assertEq(setupScript.transactionCount(), 0);
    }

    function test_ParseProductionNamedDefinitions() public {
        OfferConfigurationHarness reader = new OfferConfigurationHarness();
        OfferConfiguration.Configuration memory parsed =
            reader.parse(vm.readFile("script/config/ethereum-mainnet-live.json"));
        assertEq(parsed.pricers.length, 1);
        assertEq(parsed.pricers[0].name, "onyc-usd");
        assertEq(parsed.offers.length, 3);
        uint256 buys;
        uint256 sells;
        for (uint256 i; i < parsed.offers.length; ++i) {
            assertFalse(parsed.offers[i].enabled);
            assertEq(parsed.offers[i].pricer, "onyc-usd");
            assertEq(parsed.offers[i].managedToken, parsed.pricers[0].managedToken);
            assertEq(uint8(parsed.offers[i].flow), uint8(OfferFlow.Permissionless));
            if (parsed.offers[i].direction == OfferDirection.AssetToManaged) {
                assertEq(parsed.offers[i].liquidityVault, "none");
                buys++;
            } else {
                assertEq(parsed.offers[i].name, "onyc-to-usdg-prop");
                assertEq(parsed.offers[i].liquidityVault, "usdg-liquidity");
                assertEq(parsed.offers[i].feeConfig, "usdg-prop-fee");
                assertEq(parsed.offers[i].quoter, "usdg-prop-amm");
                sells++;
            }
        }
        assertEq(buys, 2);
        assertEq(sells, 1);
    }

    function test_DepositUsesNamedOfferAssetAndVault() public {
        _addUsdGLiquidityReference();
        setupScript.configure(environment, config);
        setupScript.run();
        DepositScriptHarness deposit = new DepositScriptHarness();
        deposit.configure(environment, config);
        usdg.mint(address(this), 10e6);
        usdc.mint(address(this), 7e6);
        deposit.run("usdg-to-onyc", 5e6);
        bytes32 vaultId = OnReIds._configurableVaultId(ConfigurableVaultKind.Liquidity, 0);
        assertEq(app.configurableVaultBalance(vaultId, address(usdg)), 5e6);
        assertEq(app.configurableVaultBalance(vaultId, address(usdc)), 0);
        assertEq(usdg.balanceOf(address(this)), 5e6);
        assertEq(usdc.balanceOf(address(this)), 7e6);
    }

    function test_DepositRequiresExistingSafeFunds() public {
        _addUsdGLiquidityReference();
        setupScript.configure(environment, config);
        setupScript.run();
        DepositScriptHarness deposit = new DepositScriptHarness();
        deposit.configure(environment, config);
        vm.expectRevert("Safe asset balance below deposit amount");
        deposit.run("usdg-to-onyc", 5e6);
        assertEq(usdg.totalSupply(), 0);
    }

    function test_CompatibilityScriptSelectionUsesOfferDefinitions() public {
        _addNavQuoter();
        config.offers
            .push(
                OfferConfiguration.OfferDefinition(
                    "usdc-permissioned",
                    address(managed),
                    address(usdc),
                    OfferDirection.AssetToManaged,
                    OfferFlow.Permissioned,
                    "onyc-usd",
                    "nav",
                    "buy-fee",
                    "proceeds",
                    "none",
                    true
                )
            );
        setupScript.configure(environment, config);
        setupScript.runMatching(OfferFlow.Permissioned, OfferDirection.AssetToManaged, QuoterKind.Nav);
        bytes32 permissionedId = OnReIds._offerConfigId(address(usdc), address(managed), OfferFlow.Permissioned);
        assertEq(uint8(app.getOfferConfig(permissionedId).flow), uint8(OfferFlow.Permissioned));
        assertEq(app.getOfferConfig(permissionedId).tokenIn, address(usdc));
        assertEq(app.getPricer(OnReIds._usdPricerId(address(managed))).managedToken, address(managed));
    }

    function _addUsdGLiquidityReference() private {
        config.vaults
            .push(OfferConfiguration.VaultDefinition("liquidity", ConfigurableVaultKind.Liquidity, 0, address(this), 0));
        config.offers[1].liquidityVault = "liquidity";
    }

    function test_ParserRejectsUnknownFlow() public {
        OfferConfigurationHarness reader = new OfferConfigurationHarness();
        vm.expectRevert("Unknown offer flow");
        reader.parse(
            '{"pricers":{},"quoters":{},"vaults":{},"feeConfigs":{},"offers":{"bad":{"managedToken":"0x0000000000000000000000000000000000000001","assetToken":"0x0000000000000000000000000000000000000002","direction":"assetToManaged","flow":"typo"}}}'
        );
    }

    function _addNavQuoter() private {
        config.quoters
            .push(
                OfferConfiguration.QuoterDefinition(
                    "nav", QuoterKind.Nav, 0, address(0), address(0), PropAmmConfig(0, 0, 0, 0, 0, 0)
                )
            );
    }

    function test_SettlementApprovalsResetPartialAllowancesAndSkipDuplicates() public {
        vm.prank(settlement);
        usdc.approve(address(app), 1);
        SettlementApprovalHarness approvals = new SettlementApprovalHarness();
        approvals.configure(environment, config);
        approvals.run();
        assertEq(approvals.transactionCount(), 4); // reset + USDC, ONyc once, USDG
        assertEq(usdc.allowance(settlement, address(app)), type(uint256).max);
        assertEq(usdg.allowance(settlement, address(app)), type(uint256).max);
        assertEq(managed.allowance(settlement, address(app)), type(uint256).max);
        approvals.run();
        assertEq(approvals.transactionCount(), 0);
    }

    function _approveSettlement() private {
        SettlementApprovalHarness approvals = new SettlementApprovalHarness();
        approvals.configure(environment, config);
        approvals.run();
    }

    function _offer(address asset) private view returns (bytes32) {
        return OnReIds._offerConfigId(asset, address(managed), OfferFlow.Permissionless);
    }

    function _buy(MockUsd asset, uint256 input) private returns (uint256 output) {
        asset.mint(user, input);
        vm.prank(user);
        asset.approve(address(app), input);
        ExecutionAccounting memory preview = app.previewExecution(_offer(address(asset)), input);
        TakeOfferParams memory params;
        params.offerConfigId = _offer(address(asset));
        params.grossInputAmount = input;
        params.deadline = uint64(block.timestamp + 60);
        params.minimumAmountOut = preview.amountOut + 1;
        vm.expectRevert(
            abi.encodeWithSelector(MinimumAmountOutNotMetError.selector, preview.amountOut + 1, preview.amountOut)
        );
        vm.prank(user);
        app.takeOffer(params);
        params.minimumAmountOut = preview.amountOut;
        vm.prank(user);
        output = app.takeOffer(params);
        assertEq(output, preview.amountOut);
    }
}
