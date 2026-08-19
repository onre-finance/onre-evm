// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {IDiamondProxy} from "../../src/generated/IDiamondProxy.sol";
import {IOnReToken} from "../../src/IOnReToken.sol";
import {OnReToken} from "../../src/OnReToken.sol";
import {LibOnRePropRfqMath} from "../../src/libraries/LibOnRePropRfqMath.sol";
import {
    ApprovalMessage,
    ConfigurableVaultKind,
    InitializeParams,
    MakeOfferConfigParams,
    OfferFlow,
    PricingDenomination,
    PricingVector,
    PropRfqConfig,
    QuoterKind,
    TakeOfferParams
} from "../../src/types/OnReTypes.sol";
import {OnReDiamondTestHelper} from "./OnReDiamondTestHelper.sol";

abstract contract OnReAppTestBase is Test, OnReDiamondTestHelper {
    bytes32 internal constant APPROVAL_TYPEHASH = keccak256("ApprovalMessage(address user,uint64 expiry)");
    bytes32 internal constant APP_STORAGE_LOCATION = 0x31164558df59313d3ca3903acf513b2eda293f9424839a72cebf9d8c78813700;
    uint256 internal constant APPROVER_KEY = 0xA11CE;

    IDiamondProxy internal app;
    OnReToken internal onReToken;
    MockUsd internal usd;

    address internal worker = makeAddr("worker");
    address internal admin = makeAddr("admin");
    address internal user = makeAddr("user");
    address internal permissionlessSettlementAccount = makeAddr("permissionlessSettlementAccount");
    address internal vaultDestination = makeAddr("vaultDestination");
    address internal approver;

    bytes32 internal pricerId;
    bytes32 internal navQuoterId;
    bytes32 internal navPermissionlessQuoterId;
    bytes32 internal feeVaultId;
    bytes32 internal proceedsVaultId;
    bytes32 internal liquidityVaultId;
    bytes32 internal feeConfigId;
    bytes32 internal permissionedOfferId;
    bytes32 internal permissionlessOfferId;
    bytes32 internal workerOfferId;

    function setUp() public {
        vm.warp(1);
        approver = vm.addr(APPROVER_KEY);

        address[] memory approvers = new address[](1);
        approvers[0] = approver;
        app = _deployDiamondApp(
            InitializeParams({
                boss: address(this), admin: admin, worker: worker, upgrader: makeAddr("upgrader"), approvers: approvers
            })
        );

        onReToken = _deployToken(address(app));
        usd = new MockUsd();

        app.setPermissionlessSettlementAccount(permissionlessSettlementAccount);
        _approvePermissionlessSettlementToken(address(usd));
        _approvePermissionlessSettlementToken(address(onReToken));
        app.registerOnReToken(address(onReToken));

        pricerId = app.createPricer(address(onReToken), PricingDenomination.Usd);
        app.addPricingVector(
            pricerId, PricingVector({startTime: 1, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days})
        );

        navQuoterId = app.createQuoter(QuoterKind.Nav, 0);
        navPermissionlessQuoterId = app.createQuoter(QuoterKind.NavPermissionless, 0);

        feeVaultId = app.createConfigurableVault(ConfigurableVaultKind.Fee, 0, vaultDestination, 0);
        proceedsVaultId = app.createConfigurableVault(ConfigurableVaultKind.Proceeds, 0, vaultDestination, 0);
        liquidityVaultId = app.createConfigurableVault(ConfigurableVaultKind.Liquidity, 0, vaultDestination, 0);
        feeConfigId = app.createFeeConfig(0, 100, 0, feeVaultId);

        permissionedOfferId = _makeOffer(
            address(usd), address(onReToken), OfferFlow.Permissioned, navQuoterId, feeConfigId, liquidityVaultId
        );
        permissionlessOfferId = _makeOffer(
            address(usd),
            address(onReToken),
            OfferFlow.Permissionless,
            navPermissionlessQuoterId,
            feeConfigId,
            liquidityVaultId
        );
        workerOfferId =
            _makeOffer(address(onReToken), address(usd), OfferFlow.Worker, navQuoterId, feeConfigId, liquidityVaultId);
    }

    function _makeOffer(
        address tokenIn,
        address tokenOut,
        OfferFlow flow,
        bytes32 quoter,
        bytes32 feeConfig,
        bytes32 liquidityVault
    ) internal returns (bytes32) {
        return app.makeOfferConfig(
            MakeOfferConfigParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                flow: flow,
                quoterId: quoter,
                feeConfigId: feeConfig,
                proceedsVaultId: proceedsVaultId,
                liquidityVaultId: liquidityVault
            })
        );
    }

    function _createConfiguredPropRfq(uint64 instanceId, PropRfqConfig memory config)
        internal
        returns (bytes32 quoterId)
    {
        quoterId = app.createQuoter(QuoterKind.PropRfq, instanceId);
        app.configurePropRfq(quoterId, address(usd), address(onReToken), config);
    }

    function _fundAndApproveUsd(address account, uint256 amount) internal {
        usd.mint(account, amount);
        vm.prank(account);
        usd.approve(address(app), amount);
    }

    function _approvePermissionlessSettlementToken(address token) internal {
        vm.prank(permissionlessSettlementAccount);
        IERC20(token).approve(address(app), type(uint256).max);
    }

    function _basePropRfqTestConfig() internal pure returns (PropRfqConfig memory) {
        return PropRfqConfig({
            curvePegHaircutBps: 700,
            curveExponentScaled: 25_000,
            cadenceThreshold: 20,
            cadenceWaveScaled: 10_000,
            epochDurationSeconds: 86_400,
            wallSensitivityScaled: 20_000
        });
    }

    function _depositLiquidity(uint256 amount) internal {
        usd.mint(address(this), amount);
        usd.approve(address(app), amount);
        app.depositConfigurableVault(liquidityVaultId, address(usd), amount);
    }

    function _takeOfferParams(bytes32 offerConfigId, uint256 grossInputAmount)
        internal
        view
        returns (TakeOfferParams memory params)
    {
        params.offerConfigId = offerConfigId;
        params.grossInputAmount = grossInputAmount;
        params.deadline = uint64(block.timestamp + 1 days);
    }

    function _permissionedTakeOfferParams(
        bytes32 offerConfigId,
        uint256 grossInputAmount,
        ApprovalMessage memory approval,
        bytes memory signature
    ) internal view returns (TakeOfferParams memory params) {
        params = _takeOfferParams(offerConfigId, grossInputAmount);
        params.approval = approval;
        params.signature = signature;
    }

    function _signApproval(ApprovalMessage memory approval) internal view returns (bytes memory) {
        return _signApprovalWithKey(approval, APPROVER_KEY);
    }

    function _signApprovalWithKey(ApprovalMessage memory approval, uint256 key) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, _approvalDigest(approval));
        return abi.encodePacked(r, s, v);
    }

    function _approvalDigest(ApprovalMessage memory approval) internal view returns (bytes32) {
        bytes32 domainTypehash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator =
            keccak256(abi.encode(domainTypehash, keccak256("OnReApp"), keccak256("1"), block.chainid, address(app)));
        bytes32 structHash = keccak256(abi.encode(APPROVAL_TYPEHASH, approval.user, approval.expiry));
        return keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));
    }

    function _deployToken(address burner) internal returns (OnReToken token) {
        OnReToken implementation = new OnReToken();
        address[] memory initialMinters = new address[](2);
        initialMinters[0] = address(this);
        initialMinters[1] = burner;
        address[] memory initialBurners = new address[](1);
        initialBurners[0] = burner;
        IOnReToken.InitializeParams memory params = IOnReToken.InitializeParams({
            name: "OnRe USD",
            symbol: "ONusd",
            admin: address(this),
            ccipAdmin: address(this),
            initialMinters: initialMinters,
            initialBurners: initialBurners
        });
        token = OnReToken(
            address(new ERC1967Proxy(address(implementation), abi.encodeCall(OnReToken.initialize, (params))))
        );
    }
}

contract PropRfqMathHarness {
    uint256 private constant HARD_WALL_SCALE = 1_000_000_000_000;

    function baseCurveOutput(uint256 rawAmount, uint256 effectiveLiquidity, uint16 pegBps, uint32 exponent)
        external
        pure
        returns (uint256)
    {
        uint256 utilization = rawAmount * HARD_WALL_SCALE / effectiveLiquidity;
        uint256 haircut = LibOnRePropRfqMath._redemptionHaircutScaled(utilization, pegBps, exponent);
        return rawAmount * (HARD_WALL_SCALE - haircut) / HARD_WALL_SCALE;
    }

    function cadenceTarget(uint256 utilization, uint256 waveYScaled) external pure returns (uint256) {
        return LibOnRePropRfqMath._cadenceWaveTargetHaircutScaled(utilization, waveYScaled);
    }

    function utilizationPower(uint256 utilization, uint32 exponentScaled) external pure returns (uint256) {
        return LibOnRePropRfqMath._utilizationPowerScaled(utilization, exponentScaled);
    }
}

contract MockUsd is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockHighDecimals is ERC20 {
    constructor() ERC20("High Decimals", "HIGH") {}

    function decimals() public pure override returns (uint8) {
        return 19;
    }
}

contract MockSenderPaysFeeToken is ERC20 {
    address private immutable feeSource;

    constructor(address feeSource_) ERC20("Sender Pays Fee", "SPF") {
        feeSource = feeSource_;
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        if (from == feeSource && to != address(0)) {
            _burn(from, 1);
        }
    }
}

contract MockRecipientPaysFeeToken is ERC20 {
    address private immutable feeRecipient;

    constructor(address feeRecipient_) ERC20("Recipient Pays Fee", "RPF") {
        feeRecipient = feeRecipient_;
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        if (to == feeRecipient && from != address(0)) {
            _burn(to, 1);
        }
    }
}
