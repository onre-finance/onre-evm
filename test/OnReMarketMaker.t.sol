// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {ConfigurableVaultKind, MarketMakerConfig, MarketMakerSwapParams} from "../src/types/OnReTypes.sol";
import {LibOnReMarketMaker} from "../src/libraries/LibOnReMarketMaker.sol";
import {LibOnReMarketMakerGuard} from "../src/libraries/LibOnReMarketMakerGuard.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {
    ExactAssetDebitRequiredError,
    ExactAssetTransferRequiredError,
    InsufficientBalanceError,
    InvalidAmountError,
    InvalidConfigurableVaultKindError,
    InvalidTokenError,
    KilledError,
    MinimumAmountOutNotMetError,
    NoChangeError,
    TakeOfferDeadlineExpiredError,
    UnauthorizedError,
    ZeroAddressError
} from "../src/types/OnReAppErrors.sol";
import {OnReAppTestBase, MockSenderPaysFeeToken, MockRecipientPaysFeeToken} from "./helpers/OnReAppTestBase.sol";

contract OnReMarketMakerTest is OnReAppTestBase {
    using StateLibrary for IPoolManager;

    IPoolManager internal manager;
    PoolKey internal key;
    MarketMakerConfig internal config;
    bytes32 internal mmVaultId;
    address internal executor = makeAddr("mmExecutor");

    function setUp() public override {
        super.setUp();
        manager = IPoolManager(deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(address(this))));
        mmVaultId = app.createConfigurableVault(ConfigurableVaultKind.MarketMaker, 0, vaultDestination, 0);
        config = MarketMakerConfig(address(manager), address(managedToken), address(usd), 500, 10, mmVaultId);
        key = _key(config);
        manager.initialize(
            key, TickMath.getSqrtPriceAtTick(address(managedToken) < address(usd) ? int24(-69081) : int24(69081))
        );

        PoolModifyLiquidityTest liquidityRouter = new PoolModifyLiquidityTest(manager);
        managedToken.mint(address(this), 1_000_000e9);
        usd.mint(address(this), 1_000_000e6);
        managedToken.approve(address(liquidityRouter), type(uint256).max);
        usd.approve(address(liquidityRouter), type(uint256).max);
        liquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -887270, tickUpper: 887270, liquidityDelta: 1e12, salt: bytes32(0)
            }),
            bytes("")
        );

        app.configureMarketMaker(config);
        app.setMarketMakerExecutor(executor);
        managedToken.approve(address(app), type(uint256).max);
        usd.approve(address(app), type(uint256).max);
        app.depositConfigurableVault(mmVaultId, address(managedToken), 1_000e9);
        app.depositConfigurableVault(mmVaultId, address(usd), 1_000e6);
        _depositLiquidity(500e6);
    }

    function test_SwapBothDirectionsUsesOnlyMarketMakerInventory() public {
        uint256 foreignLiquidity = app.configurableVaultBalance(liquidityVaultId, address(usd));
        uint256 inputBefore = usd.balanceOf(address(app));
        uint256 outputBefore = managedToken.balanceOf(address(app));
        vm.prank(executor);
        (uint256 spent, uint256 received) = app.swapUniswapV4(_params(false, 10e6));
        assertEq(spent, 10e6);
        assertGt(received, 0);
        assertEq(inputBefore - usd.balanceOf(address(app)), spent);
        assertEq(managedToken.balanceOf(address(app)) - outputBefore, received);
        assertEq(app.configurableVaultBalance(mmVaultId, address(usd)), 1_000e6 - spent);
        assertEq(app.configurableVaultBalance(mmVaultId, address(managedToken)), 1_000e9 + received);

        vm.prank(executor);
        (uint256 sold, uint256 bought) = app.swapUniswapV4(_params(true, uint128(received)));
        assertEq(sold, received);
        assertGt(bought, 0);
        assertEq(app.configurableVaultBalance(mmVaultId, address(managedToken)), 1_000e9);
        assertEq(app.configurableVaultBalance(mmVaultId, address(usd)), 1_000e6 - spent + bought);
        assertEq(app.configurableVaultBalance(liquidityVaultId, address(usd)), foreignLiquidity);
        assertEq(usd.balanceOf(executor), 0);
        assertEq(managedToken.balanceOf(executor), 0);
        assertEq(usd.allowance(address(app), address(manager)), 0);
        assertEq(managedToken.allowance(address(app), address(manager)), 0);
    }

    function test_PriceLimitPartialFillDebitsOnlyActualInput() public {
        (uint160 beforePrice, int24 tick,,) = manager.getSlot0(key.toId());
        bool zeroForOne = address(usd) == Currency.unwrap(key.currency0);
        MarketMakerSwapParams memory params = _params(false, 1_000e6);
        params.sqrtPriceLimitX96 = TickMath.getSqrtPriceAtTick(zeroForOne ? tick - 1 : tick + 1);
        vm.prank(executor);
        (uint256 spent, uint256 received) = app.swapUniswapV4(params);
        assertGt(spent, 0);
        assertLt(spent, params.amountIn);
        assertGt(received, 0);
        assertEq(app.configurableVaultBalance(mmVaultId, address(usd)), 1_000e6 - spent);
        (uint160 afterPrice,,,) = manager.getSlot0(key.toId());
        assertEq(afterPrice, params.sqrtPriceLimitX96);
        assertTrue(zeroForOne ? afterPrice < beforePrice : afterPrice > beforePrice);
    }

    function test_MinimumOutputFailureRollsBackPoolAndInventory() public {
        (uint160 beforePrice,,,) = manager.getSlot0(key.toId());
        uint256 beforeBalance = usd.balanceOf(address(app));
        MarketMakerSwapParams memory params = _params(false, 10e6);
        params.minimumAmountOut = type(uint128).max;
        vm.expectPartialRevert(MinimumAmountOutNotMetError.selector);
        vm.prank(executor);
        app.swapUniswapV4(params);
        assertEq(app.configurableVaultBalance(mmVaultId, address(usd)), 1_000e6);
        assertEq(app.configurableVaultBalance(mmVaultId, address(managedToken)), 1_000e9);
        assertEq(usd.balanceOf(address(app)), beforeBalance);
        (uint160 afterPrice,,,) = manager.getSlot0(key.toId());
        assertEq(afterPrice, beforePrice);
        // Reverting clears both reentrancy and callback state.
        vm.prank(executor);
        app.swapUniswapV4(_params(false, 10e6));
    }

    function test_CannotSpendOtherVaultsOrUnaccountedDonations() public {
        usd.mint(address(app), 5_000e6);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceError.selector, 1_000e6, 1_001e6));
        vm.prank(executor);
        app.swapUniswapV4(_params(false, 1_001e6));
        assertEq(app.configurableVaultBalance(liquidityVaultId, address(usd)), 500e6);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceError.selector, 1_000e6, 1_001e6));
        app.withdrawConfigurableVault(mmVaultId, address(usd), 1_001e6);
    }

    function test_DepositsAreOpenAndWithdrawalsUseConfiguredDestinationAfterBossTransfer() public {
        _fundAndApproveUsd(user, 5e6);
        vm.prank(user);
        app.depositConfigurableVault(mmVaultId, address(usd), 5e6);
        assertEq(app.configurableVaultBalance(mmVaultId, address(usd)), 1_005e6);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        vm.prank(executor);
        app.withdrawConfigurableVault(mmVaultId, address(usd), 1e6);

        address newBoss = makeAddr("newBoss");
        app.beginBossTransfer(newBoss);
        vm.prank(newBoss);
        app.acceptBossTransfer();
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        app.withdrawConfigurableVault(mmVaultId, address(usd), 1e6);
        vm.prank(newBoss);
        app.withdrawConfigurableVault(mmVaultId, address(usd), 5e6);
        assertEq(usd.balanceOf(newBoss), 0);
        assertEq(usd.balanceOf(vaultDestination), 5e6);
        assertEq(app.configurableVaultBalance(mmVaultId, address(usd)), 1_000e6);
        vm.prank(newBoss);
        app.updateConfigurableVault(mmVaultId, newBoss, 0);
        vm.prank(newBoss);
        app.withdrawConfigurableVault(mmVaultId, address(usd), 1e6);
        assertEq(usd.balanceOf(newBoss), 1e6);
        vm.prank(newBoss);
        app.setMarketMakerExecutor(user);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedError.selector, executor));
        vm.prank(executor);
        app.swapUniswapV4(_params(false, 1e6));
        vm.prank(user);
        app.swapUniswapV4(_params(false, 1e6));
    }

    function test_BossAndAdminKillSwitchRulesMatchSolana() public {
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedError.selector, executor));
        vm.prank(executor);
        app.setMarketMakerKillSwitch(true);
        vm.prank(admin);
        app.setMarketMakerKillSwitch(true);
        vm.expectRevert(KilledError.selector);
        vm.prank(executor);
        app.swapUniswapV4(_params(false, 1e6));
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        vm.prank(admin);
        app.setMarketMakerKillSwitch(false);
        // Pausing swaps does not lock boss withdrawals or prevent inventory funding.
        app.withdrawConfigurableVault(mmVaultId, address(usd), 1e6);
        usd.approve(address(app), 1e6);
        app.depositConfigurableVault(mmVaultId, address(usd), 1e6);
        app.setMarketMakerKillSwitch(false);
        vm.prank(executor);
        app.swapUniswapV4(_params(false, 1e6));
    }

    function test_GlobalKillAndDisabledManagedTokenAlsoBlockSwaps() public {
        app.setKillSwitch(true);
        vm.expectRevert(KilledError.selector);
        vm.prank(executor);
        app.swapUniswapV4(_params(false, 1e6));
        vm.expectRevert(KilledError.selector);
        app.withdrawConfigurableVault(mmVaultId, address(usd), 1e6);
        app.setKillSwitch(false);
        app.setManagedTokenEnabled(address(managedToken), false);
        vm.expectRevert(InvalidTokenError.selector);
        vm.prank(executor);
        app.swapUniswapV4(_params(false, 1e6));
    }

    function test_OnlyExecutorCanSwapAndOnlyBossCanConfigure() public {
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedError.selector, user));
        vm.prank(user);
        app.swapUniswapV4(_params(false, 1e6));
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        vm.prank(executor);
        app.configureMarketMaker(config);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        vm.prank(admin);
        app.setMarketMakerExecutor(user);
        vm.expectRevert(ZeroAddressError.selector);
        app.setMarketMakerExecutor(address(0));
        vm.expectRevert(NoChangeError.selector);
        app.setMarketMakerExecutor(executor);
    }

    function test_RejectsExpiredZeroAndOversizedInput() public {
        MarketMakerSwapParams memory params = _params(false, 1e6);
        params.deadline = 0;
        vm.expectRevert(abi.encodeWithSelector(TakeOfferDeadlineExpiredError.selector, 0));
        vm.prank(executor);
        app.swapUniswapV4(params);
        params = _params(false, 0);
        vm.expectRevert(InvalidAmountError.selector);
        vm.prank(executor);
        app.swapUniswapV4(params);
        params.amountIn = type(uint128).max;
        vm.expectRevert(InvalidAmountError.selector);
        vm.prank(executor);
        app.swapUniswapV4(params);
    }

    function test_RejectsZeroDepositsAndZeroWithdrawals() public {
        vm.expectRevert(InvalidAmountError.selector);
        app.depositConfigurableVault(mmVaultId, address(usd), 0);
        vm.expectRevert(InvalidAmountError.selector);
        app.withdrawConfigurableVault(mmVaultId, address(usd), 0);
    }

    function test_RejectsUninitializedInvalidAndDynamicFeePools() public {
        MarketMakerConfig memory invalid = config;
        invalid.fee = 3000;
        vm.expectRevert(LibOnReMarketMaker.InvalidMarketMakerPool.selector);
        app.configureMarketMaker(invalid);
        invalid.fee = 0x800000;
        vm.expectRevert(LibOnReMarketMaker.InvalidMarketMakerPool.selector);
        app.configureMarketMaker(invalid);
        invalid = config;
        invalid.tickSpacing = 0;
        vm.expectRevert(LibOnReMarketMaker.InvalidMarketMakerPool.selector);
        app.configureMarketMaker(invalid);
        invalid = config;
        invalid.assetToken = address(managedToken);
        vm.expectRevert(LibOnReMarketMaker.InvalidMarketMakerPool.selector);
        app.configureMarketMaker(invalid);
        invalid = config;
        invalid.assetToken = address(0);
        vm.expectRevert(LibOnReMarketMaker.InvalidMarketMakerPool.selector);
        app.configureMarketMaker(invalid);
        invalid = config;
        invalid.poolManager = user;
        vm.expectRevert(LibOnReMarketMaker.InvalidMarketMakerPool.selector);
        app.configureMarketMaker(invalid);
    }

    function test_RejectsNonMarketMakerVaultConfiguration() public {
        MarketMakerConfig memory invalid = config;
        invalid.vaultId = liquidityVaultId;
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidConfigurableVaultKindError.selector,
                liquidityVaultId,
                uint8(ConfigurableVaultKind.MarketMaker),
                uint8(ConfigurableVaultKind.Liquidity)
            )
        );
        app.configureMarketMaker(invalid);
    }

    function test_ConfigAndInventorySurvivePoolReconfiguration() public {
        (MarketMakerConfig memory stored, address storedExecutor, bool killed) = app.marketMakerState();
        assertEq(stored.poolManager, address(manager));
        assertEq(stored.managedToken, address(managedToken));
        assertEq(stored.assetToken, address(usd));
        assertEq(stored.fee, 500);
        assertEq(stored.tickSpacing, 10);
        assertEq(stored.vaultId, mmVaultId);
        assertEq(storedExecutor, executor);
        assertFalse(killed);
        MockRecipientPaysFeeToken other = new MockRecipientPaysFeeToken(user);
        _configureAsset(address(other));
        assertEq(app.configurableVaultBalance(mmVaultId, address(usd)), 1_000e6);
        uint256 beforeBalance = usd.balanceOf(vaultDestination);
        app.withdrawConfigurableVault(mmVaultId, address(usd), 1_000e6);
        assertEq(usd.balanceOf(vaultDestination) - beforeBalance, 1_000e6);
    }

    function test_RejectsUnauthorizedOrUnsolicitedCallbacks() public {
        bytes memory data = abi.encode(_params(false, 1e6));
        vm.expectRevert(LibOnReMarketMaker.InvalidMarketMakerCallback.selector);
        app.unlockCallback(data);
        vm.expectRevert(LibOnReMarketMaker.InvalidMarketMakerCallback.selector);
        vm.prank(address(manager));
        app.unlockCallback(data);
        vm.expectRevert(LibOnReMarketMaker.InvalidMarketMakerCallback.selector);
        vm.prank(address(app));
        manager.unlock(bytes("unsolicited"));
    }

    function test_ManagerMustActuallyCallBack() public {
        vm.mockCall(address(manager), abi.encodeWithSelector(IPoolManager.unlock.selector), abi.encode(bytes("")));
        vm.expectRevert(LibOnReMarketMaker.InvalidMarketMakerCallback.selector);
        vm.prank(executor);
        app.swapUniswapV4(_params(false, 1e6));
        assertEq(app.configurableVaultBalance(mmVaultId, address(usd)), 1_000e6);
    }

    function test_RejectsChangedCallbackDataAndRepeatedCallbacks() public {
        for (uint256 i; i < 2; ++i) {
            MarketMakerCallbackProbe probe = new MarketMakerCallbackProbe(i == 1);
            MarketMakerConfig memory replacement = config;
            replacement.poolManager = address(probe);
            app.configureMarketMaker(replacement);
            vm.expectRevert(LibOnReMarketMaker.InvalidMarketMakerCallback.selector);
            vm.prank(executor);
            app.swapUniswapV4(_params(false, 1e6));
            assertEq(app.configurableVaultBalance(mmVaultId, address(usd)), 1_000e6);
            assertEq(app.configurableVaultBalance(mmVaultId, address(managedToken)), 1_000e9);
        }
    }

    function test_RejectsInvalidSwapDeltaBeforePaying() public {
        vm.mockCall(
            address(manager), abi.encodeWithSelector(IPoolManager.swap.selector), abi.encode(toBalanceDelta(1, 1))
        );
        vm.expectRevert(LibOnReMarketMaker.InvalidMarketMakerSwapDelta.selector);
        vm.prank(executor);
        app.swapUniswapV4(_params(false, 1e6));
        assertEq(app.configurableVaultBalance(mmVaultId, address(usd)), 1_000e6);
    }

    function test_ExactDepositsRejectTransferTaxes() public {
        MockSenderPaysFeeToken senderTax = new MockSenderPaysFeeToken(user);
        _configureAsset(address(senderTax));
        senderTax.mint(user, 101);
        vm.prank(user);
        senderTax.approve(address(app), 100);
        vm.expectRevert(abi.encodeWithSelector(ExactAssetDebitRequiredError.selector, address(senderTax), 100, 101));
        vm.prank(user);
        app.depositConfigurableVault(mmVaultId, address(senderTax), 100);
        assertEq(app.configurableVaultBalance(mmVaultId, address(senderTax)), 0);

        MockRecipientPaysFeeToken recipientTax = new MockRecipientPaysFeeToken(address(app));
        _configureAsset(address(recipientTax));
        recipientTax.mint(address(this), 100);
        recipientTax.approve(address(app), 100);
        vm.expectRevert(
            abi.encodeWithSelector(ExactAssetTransferRequiredError.selector, address(recipientTax), 100, 99)
        );
        app.depositConfigurableVault(mmVaultId, address(recipientTax), 100);
        assertEq(app.configurableVaultBalance(mmVaultId, address(recipientTax)), 0);
    }

    function test_ExactWithdrawalsRejectExcessDebit() public {
        MockSenderPaysFeeToken senderTax = new MockSenderPaysFeeToken(address(app));
        _configureAsset(address(senderTax));
        senderTax.mint(address(this), 100);
        senderTax.approve(address(app), 100);
        app.depositConfigurableVault(mmVaultId, address(senderTax), 100);
        senderTax.mint(address(app), 1);
        vm.expectRevert(abi.encodeWithSelector(ExactAssetDebitRequiredError.selector, address(senderTax), 50, 51));
        app.withdrawConfigurableVault(mmVaultId, address(senderTax), 50);
        assertEq(app.configurableVaultBalance(mmVaultId, address(senderTax)), 100);
    }

    function test_DepositRejectsTokenReentrancy() public {
        ReentrantMarketMakerToken token = new ReentrantMarketMakerToken(app, mmVaultId);
        _configureAsset(address(token));
        token.mint(address(this), 100);
        token.approve(address(app), 100);
        vm.expectRevert(LibOnReMarketMakerGuard.MarketMakerReentrantCall.selector);
        app.depositConfigurableVault(mmVaultId, address(token), 100);
        assertEq(token.balanceOf(address(this)), 100);
        assertEq(app.configurableVaultBalance(mmVaultId, address(token)), 0);
    }

    function test_SwapRejectsTaxedOutputAndRestoresInventory() public {
        MockRecipientPaysFeeToken token = new MockRecipientPaysFeeToken(address(app));
        _configureAsset(address(token));
        MarketMakerConfig memory replacement = config;
        replacement.assetToken = address(token);
        PoolModifyLiquidityTest router = new PoolModifyLiquidityTest(manager);
        token.mint(address(this), 1e15);
        token.approve(address(router), type(uint256).max);
        managedToken.approve(address(router), type(uint256).max);
        router.modifyLiquidity(
            _key(replacement),
            IPoolManager.ModifyLiquidityParams({
                tickLower: -887270, tickUpper: 887270, liquidityDelta: 1e12, salt: bytes32(0)
            }),
            bytes("")
        );
        vm.expectPartialRevert(ExactAssetTransferRequiredError.selector);
        vm.prank(executor);
        app.swapUniswapV4(_params(true, 10e9));
        assertEq(app.configurableVaultBalance(mmVaultId, address(managedToken)), 1_000e9);
        assertEq(app.configurableVaultBalance(mmVaultId, address(token)), 0);
        assertEq(app.configurableVaultBalance(liquidityVaultId, address(usd)), 500e6);
    }

    function testFuzz_SwapsPreserveForeignLiquidityAndMatchPhysicalBalances(uint128 input, bool sell) public {
        uint128 amount = uint128(bound(input, sell ? 1e6 : 1e3, sell ? 100e9 : 100e6));
        uint256 beforeUsd = usd.balanceOf(address(app));
        uint256 beforeManaged = managedToken.balanceOf(address(app));
        vm.prank(executor);
        (uint256 spent, uint256 received) = app.swapUniswapV4(_params(sell, amount));
        assertEq(spent, amount);
        assertGt(received, 0);
        assertEq(usd.balanceOf(address(app)), sell ? beforeUsd + received : beforeUsd - spent);
        assertEq(managedToken.balanceOf(address(app)), sell ? beforeManaged - spent : beforeManaged + received);
        assertEq(usd.balanceOf(address(app)), app.configurableVaultBalance(mmVaultId, address(usd)) + 500e6);
        assertEq(managedToken.balanceOf(address(app)), app.configurableVaultBalance(mmVaultId, address(managedToken)));
        assertEq(app.configurableVaultBalance(liquidityVaultId, address(usd)), 500e6);
    }

    function _configureAsset(address token) internal {
        MarketMakerConfig memory replacement = config;
        replacement.assetToken = token;
        manager.initialize(_key(replacement), uint160(1 << 96));
        app.configureMarketMaker(replacement);
    }

    function _key(MarketMakerConfig memory value) internal pure returns (PoolKey memory) {
        (address token0, address token1) = value.managedToken < value.assetToken
            ? (value.managedToken, value.assetToken)
            : (value.assetToken, value.managedToken);
        return PoolKey(Currency.wrap(token0), Currency.wrap(token1), value.fee, value.tickSpacing, IHooks(address(0)));
    }

    function _params(bool sell, uint128 amount) internal view returns (MarketMakerSwapParams memory) {
        return MarketMakerSwapParams(sell, amount, 1, 0, uint64(block.timestamp + 1 minutes));
    }
}

contract ReentrantMarketMakerToken is ERC20 {
    IDiamondProxy private immutable app;

    bytes32 private immutable mmVaultId;

    constructor(IDiamondProxy app_, bytes32 mmVaultId_) ERC20("Reentrant", "REENT") {
        app = app_;
        mmVaultId = mmVaultId_;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) app.depositConfigurableVault(mmVaultId, address(this), 1);
        super._update(from, to, amount);
    }
}

/// @dev Exercises callback authentication while a real MM request is active.
contract MarketMakerCallbackProbe {
    bool private immutable repeatCallback;
    bytes private activeData;

    constructor(bool repeatCallback_) {
        repeatCallback = repeatCallback_;
    }

    function extsload(bytes32) external pure returns (bytes32) {
        return bytes32(uint256(1 << 96));
    }

    function unlock(bytes calldata data) external returns (bytes memory) {
        activeData = data;
        return IDiamondProxy(msg.sender).unlockCallback(repeatCallback ? data : abi.encodePacked(data, bytes1(0)));
    }

    function swap(PoolKey memory, IPoolManager.SwapParams memory, bytes calldata) external returns (BalanceDelta) {
        IDiamondProxy(msg.sender).unlockCallback(activeData);
        revert("Repeated callback must fail");
    }
}
