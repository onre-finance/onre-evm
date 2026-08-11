// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ZeroAddressError} from "./types/OnReAppErrors.sol";
import {InitializeParams} from "./types/OnReTypes.sol";
import {IBurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";
import {IGetCCIPAdmin} from "@chainlink/contracts/src/v0.8/shared/interfaces/IGetCCIPAdmin.sol";
import {
    IERC20 as ChainlinkIERC20
} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IOnReToken} from "./IOnReToken.sol";

contract OnReToken is Initializable, IOnReToken, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    EnumerableSet.AddressSet private _minters;
    EnumerableSet.AddressSet private _burners;

    address private _ccipAdmin;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(InitializeParams calldata params) external initializer {
        if (params.admin == address(0) || params.ccipAdmin == address(0)) {
            revert ZeroAddressError();
        }

        __ERC20_init(params.name, params.symbol);
        __AccessControl_init();

        _ccipAdmin = params.ccipAdmin;
        _grantRole(DEFAULT_ADMIN_ROLE, params.admin);
        _grantRole(UPGRADER_ROLE, params.admin);

        uint256 initialMintersLength = params.initialMinters.length;
        for (uint256 i = 0; i < initialMintersLength;) {
            _addMinter(params.initialMinters[i]);
            unchecked {
                ++i;
            }
        }

        uint256 initialBurnersLength = params.initialBurners.length;
        for (uint256 i = 0; i < initialBurnersLength;) {
            _addBurner(params.initialBurners[i]);
            unchecked {
                ++i;
            }
        }
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    function getCCIPAdmin() external view override returns (address) {
        return _ccipAdmin;
    }

    function setCCIPAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) {
            revert ZeroAddressError();
        }

        address previousAdmin = _ccipAdmin;
        _ccipAdmin = newAdmin;
        emit CCIPAdminTransferredEvent(previousAdmin, newAdmin);
    }

    function getMinters() external view returns (address[] memory) {
        return _minters.values();
    }

    function getBurners() external view returns (address[] memory) {
        return _burners.values();
    }

    function minterAt(uint256 index) external view returns (address) {
        return _minters.at(index);
    }

    function minterCount() external view returns (uint256) {
        return _minters.length();
    }

    function burnerAt(uint256 index) external view returns (address) {
        return _burners.at(index);
    }

    function burnerCount() external view returns (uint256) {
        return _burners.length();
    }

    function isMinter(address account) external view returns (bool) {
        return _minters.contains(account);
    }

    function isBurner(address account) external view returns (bool) {
        return _burners.contains(account);
    }

    function grantMintRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _addMinter(account);
    }

    function revokeMintRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeMinter(account);
    }

    function grantBurnRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _addBurner(account);
    }

    function revokeBurnRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeBurner(account);
    }

    function grantMintAndBurnRoles(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addMinter(account);
        _addBurner(account);
    }

    function revokeMintAndBurnRoles(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeMinter(account);
        _removeBurner(account);
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(uint256 amount) public onlyBurner {
        _burn(msg.sender, amount);
    }

    function burn(address account, uint256 amount) public {
        burnFrom(account, amount);
    }

    function burnFrom(address account, uint256 amount) public onlyBurner {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControlUpgradeable) returns (bool) {
        return interfaceId == type(ChainlinkIERC20).interfaceId || interfaceId == type(IBurnMintERC20).interfaceId
            || interfaceId == type(IGetCCIPAdmin).interfaceId || super.supportsInterface(interfaceId);
    }

    modifier onlyMinter() {
        address sender = msg.sender;
        if (!_minters.contains(sender)) {
            revert SenderNotMinterError(sender);
        }
        _;
    }

    modifier onlyBurner() {
        address sender = msg.sender;
        if (!_burners.contains(sender)) {
            revert SenderNotBurnerError(sender);
        }
        _;
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function _addMinter(address account) internal {
        if (account == address(0)) {
            revert ZeroAddressError();
        }
        if (!_minters.add(account)) return;

        emit MintAccessGrantedEvent(account);
    }

    function _removeMinter(address account) internal {
        if (!_minters.remove(account)) return;

        emit MintAccessRevokedEvent(account);
    }

    function _addBurner(address account) internal {
        if (account == address(0)) {
            revert ZeroAddressError();
        }
        if (!_burners.add(account)) return;

        emit BurnAccessGrantedEvent(account);
    }

    function _removeBurner(address account) internal {
        if (!_burners.remove(account)) return;

        emit BurnAccessRevokedEvent(account);
    }
}
