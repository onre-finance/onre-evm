// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {ConfigurableVaultKind, MarketMakerConfig, MarketMakerSwapParams} from "../types/OnReTypes.sol";
import {
    ExactAssetDebitRequiredError,
    ExactAssetTransferRequiredError,
    InvalidAmountError,
    KilledError,
    MinimumAmountOutNotMetError,
    NoChangeError,
    TakeOfferDeadlineExpiredError,
    UnauthorizedError,
    ZeroAddressError
} from "../types/OnReAppErrors.sol";
import {
    MarketMakerConfigured,
    MarketMakerExecutorUpdated,
    MarketMakerKillSwitchSet,
    MarketMakerSwapped
} from "../types/OnReAppEvents.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {LibOnReVault} from "./LibOnReVault.sol";
import {LibOnReMarketMakerGuard} from "./LibOnReMarketMakerGuard.sol";

/// @notice Trades against one dedicated MarketMaker-kind configurable vault.
library LibOnReMarketMaker {
    using StateLibrary for IPoolManager;

    error MarketMakerNotConfigured();
    error InvalidMarketMakerPool();
    error InvalidMarketMakerCallback();
    error InvalidMarketMakerSwapDelta();

    /// @custom:storage-location erc7201:onre.storage.MarketMaker
    struct MarketMakerStorage {
        MarketMakerConfig config;
        address executor;
        bool killed;
        bool callbackPending;
        bytes32 callbackHash;
    }

    // keccak256(abi.encode(uint256(keccak256("onre.storage.MarketMaker")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_POSITION = 0xbf4c85711d9ad6c7827a2374579c42020b5506fafa84c9023038b11c09d6d400;

    modifier nonReentrant() {
        LibOnReMarketMakerGuard._enter();
        _;
        LibOnReMarketMakerGuard._exit();
    }

    function _configure(MarketMakerConfig calldata config) internal nonReentrant {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation._requireVaultKind(config.vaultId, ConfigurableVaultKind.MarketMaker);
        LibOnReValidation._requireEnabledManagedToken(config.managedToken);
        if (
            config.poolManager.code.length == 0 || config.assetToken.code.length == 0
                || config.assetToken == config.managedToken || config.poolManager == address(this)
                || config.fee >= 1_000_000 || config.tickSpacing <= 0 || config.tickSpacing > type(int16).max
        ) revert InvalidMarketMakerPool();
        PoolKey memory key = _poolKey(config);
        (uint160 sqrtPriceX96,,,) = IPoolManager(config.poolManager).getSlot0(key.toId());
        if (sqrtPriceX96 == 0) revert InvalidMarketMakerPool();
        _storage().config = config;
        emit MarketMakerConfigured(
            config.poolManager, config.managedToken, config.assetToken, config.fee, config.tickSpacing, config.vaultId
        );
    }

    function _setExecutor(address executor) internal nonReentrant {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (executor == address(0)) revert ZeroAddressError();
        MarketMakerStorage storage s = _storage();
        address previousExecutor = s.executor;
        if (executor == previousExecutor) revert NoChangeError();
        s.executor = executor;
        emit MarketMakerExecutorUpdated(previousExecutor, executor);
    }

    function _setKillSwitch(bool killed) internal nonReentrant {
        if (killed) {
            if (
                !LibOnReAccessControl._hasRole(LibOnReRoles.DEFAULT_ADMIN_ROLE, msg.sender)
                    && !LibOnReAccessControl._hasRole(LibOnReRoles.ADMIN_ROLE, msg.sender)
            ) revert UnauthorizedError(msg.sender);
        } else {
            LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        }
        MarketMakerStorage storage s = _storage();
        if (s.killed == killed) revert NoChangeError();
        s.killed = killed;
        emit MarketMakerKillSwitchSet(killed);
    }

    function _swap(MarketMakerSwapParams calldata params)
        internal
        nonReentrant
        returns (uint256 actualAmountIn, uint256 amountOut)
    {
        MarketMakerStorage storage s = _configuredStorage();
        if (msg.sender != s.executor) revert UnauthorizedError(msg.sender);
        if (s.killed || LibOnReStorage._appStorage().isKilled) revert KilledError();
        LibOnReValidation._requireEnabledManagedToken(s.config.managedToken);
        if (block.timestamp > params.deadline) revert TakeOfferDeadlineExpiredError(params.deadline);
        if (params.amountIn == 0 || params.amountIn > uint128(type(int128).max)) revert InvalidAmountError();
        (address tokenIn, address tokenOut) = _tokens(s.config, params.sellManagedToken);
        // Reserve the maximum input before the callback; refund any unspent input after a price-limit partial fill.
        LibOnReVault._debitMarketMaker(s.config.vaultId, tokenIn, params.amountIn);
        uint256 inputBefore = IERC20(tokenIn).balanceOf(address(this));
        uint256 outputBefore = IERC20(tokenOut).balanceOf(address(this));
        bytes memory data = abi.encode(params);
        s.callbackHash = keccak256(data);
        s.callbackPending = true;
        bytes memory result = IPoolManager(s.config.poolManager).unlock(data);
        if (s.callbackPending) revert InvalidMarketMakerCallback();
        delete s.callbackHash;
        (actualAmountIn, amountOut) = abi.decode(result, (uint256, uint256));
        _requireSwapBalanceDeltas(tokenIn, tokenOut, inputBefore, outputBefore, actualAmountIn, amountOut);
        LibOnReVault._accrue(s.config.vaultId, tokenIn, params.amountIn - actualAmountIn);
        LibOnReVault._accrue(s.config.vaultId, tokenOut, amountOut);
        emit MarketMakerSwapped(s.config.vaultId, tokenIn, tokenOut, params.amountIn, actualAmountIn, amountOut);
    }

    function _unlockCallback(bytes calldata data) internal returns (bytes memory) {
        MarketMakerStorage storage s = _storage();
        if (
            msg.sender != s.config.poolManager || !LibOnReMarketMakerGuard._entered() || !s.callbackPending
                || keccak256(data) != s.callbackHash
        ) {
            revert InvalidMarketMakerCallback();
        }
        // Consume the authorization before calling the pool or either token.
        s.callbackPending = false;
        MarketMakerSwapParams memory params = abi.decode(data, (MarketMakerSwapParams));
        PoolKey memory key = _poolKey(s.config);
        (address tokenIn, address tokenOut) = _tokens(s.config, params.sellManagedToken);
        bool zeroForOne = tokenIn == Currency.unwrap(key.currency0);
        uint160 priceLimit = params.sqrtPriceLimitX96;
        if (priceLimit == 0) {
            priceLimit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        }
        IPoolManager manager = IPoolManager(msg.sender);
        BalanceDelta delta = manager.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(uint256(params.amountIn)),
                sqrtPriceLimitX96: priceLimit
            }),
            bytes("")
        );
        int128 inputDelta = zeroForOne ? delta.amount0() : delta.amount1();
        int128 outputDelta = zeroForOne ? delta.amount1() : delta.amount0();
        if (inputDelta >= 0 || outputDelta <= 0) revert InvalidMarketMakerSwapDelta();
        uint256 actualAmountIn = uint256(-int256(inputDelta));
        uint256 amountOut = uint256(uint128(outputDelta));
        if (actualAmountIn > params.amountIn) revert InvalidMarketMakerSwapDelta();
        if (amountOut < params.minimumAmountOut) {
            revert MinimumAmountOutNotMetError(params.minimumAmountOut, amountOut);
        }
        manager.sync(Currency.wrap(tokenIn));
        LibOnReVault._transferExactTokenAmount(tokenIn, msg.sender, actualAmountIn);
        if (manager.settle() != actualAmountIn) revert InvalidMarketMakerSwapDelta();
        manager.take(Currency.wrap(tokenOut), address(this), amountOut);
        return abi.encode(actualAmountIn, amountOut);
    }

    function _state() internal view returns (MarketMakerConfig memory config, address executor, bool killed) {
        MarketMakerStorage storage s = _storage();
        return (s.config, s.executor, s.killed);
    }

    function _configuredStorage() private view returns (MarketMakerStorage storage s) {
        s = _storage();
        if (s.config.poolManager == address(0)) revert MarketMakerNotConfigured();
    }

    function _poolKey(MarketMakerConfig memory config) private pure returns (PoolKey memory key) {
        (address token0, address token1) = config.managedToken < config.assetToken
            ? (config.managedToken, config.assetToken)
            : (config.assetToken, config.managedToken);
        key = PoolKey(Currency.wrap(token0), Currency.wrap(token1), config.fee, config.tickSpacing, IHooks(address(0)));
    }

    function _tokens(MarketMakerConfig memory config, bool sellManagedToken)
        private
        pure
        returns (address tokenIn, address tokenOut)
    {
        return sellManagedToken ? (config.managedToken, config.assetToken) : (config.assetToken, config.managedToken);
    }

    function _requireSwapBalanceDeltas(
        address tokenIn,
        address tokenOut,
        uint256 inputBefore,
        uint256 outputBefore,
        uint256 actualAmountIn,
        uint256 amountOut
    ) private view {
        uint256 inputAfter = IERC20(tokenIn).balanceOf(address(this));
        uint256 debited = inputAfter <= inputBefore ? inputBefore - inputAfter : 0;
        if (debited != actualAmountIn) revert ExactAssetDebitRequiredError(tokenIn, actualAmountIn, debited);
        uint256 outputAfter = IERC20(tokenOut).balanceOf(address(this));
        uint256 credited = outputAfter >= outputBefore ? outputAfter - outputBefore : 0;
        if (credited != amountOut) revert ExactAssetTransferRequiredError(tokenOut, amountOut, credited);
    }

    function _storage() private pure returns (MarketMakerStorage storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }
}
