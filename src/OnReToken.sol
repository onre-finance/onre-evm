// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IBurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";
import {IGetCCIPAdmin} from "@chainlink/contracts/src/v0.8/shared/interfaces/IGetCCIPAdmin.sol";
import {
    IERC20 as ChainlinkIERC20
} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IOnReToken} from "./interfaces/IOnReToken.sol";

contract OnReToken is Initializable, IOnReToken, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    address[] private _minters;
    mapping(address account => bool allowed) public isMinter;
    mapping(address account => uint256 indexPlusOne) private _minterIndexPlusOne;

    address[] private _burners;
    mapping(address account => bool allowed) public isBurner;
    mapping(address account => uint256 indexPlusOne) private _burnerIndexPlusOne;

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

        for (uint256 i = 0; i < params.initialMinters.length; ++i) {
            _addMinter(params.initialMinters[i]);
        }
        for (uint256 i = 0; i < params.initialBurners.length; ++i) {
            _addBurner(params.initialBurners[i]);
        }
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    function getCCIPAdmin() external view override returns (address) {
        return _ccipAdmin;
    }

    function setCCIPAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address previousAdmin = _ccipAdmin;
        _ccipAdmin = newAdmin;
        emit CCIPAdminTransferredEvent(previousAdmin, newAdmin);
    }

    function getMinters() external view returns (address[] memory) {
        return _minters;
    }

    function getBurners() external view returns (address[] memory) {
        return _burners;
    }

    function minterAt(uint256 index) external view returns (address) {
        return _minters[index];
    }

    function minterCount() external view returns (uint256) {
        return _minters.length;
    }

    function burnerAt(uint256 index) external view returns (address) {
        return _burners[index];
    }

    function burnerCount() external view returns (uint256) {
        return _burners.length;
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
        _burn(_msgSender(), amount);
    }

    function burn(address account, uint256 amount) public {
        burnFrom(account, amount);
    }

    function burnFrom(address account, uint256 amount) public onlyBurner {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControlUpgradeable) returns (bool) {
        return interfaceId == type(ChainlinkIERC20).interfaceId || interfaceId == type(IBurnMintERC20).interfaceId
            || interfaceId == type(IGetCCIPAdmin).interfaceId || super.supportsInterface(interfaceId);
    }

    modifier onlyMinter() {
        address sender = _msgSender();
        if (!isMinter[sender]) {
            revert SenderNotMinterError(sender);
        }
        _;
    }

    modifier onlyBurner() {
        address sender = _msgSender();
        if (!isBurner[sender]) {
            revert SenderNotBurnerError(sender);
        }
        _;
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function _addMinter(address account) internal {
        if (account == address(0)) {
            revert ZeroAddressError();
        }
        if (isMinter[account]) {
            return;
        }

        isMinter[account] = true;
        _minterIndexPlusOne[account] = _minters.length + 1;
        _minters.push(account);

        emit MintAccessGrantedEvent(account);
    }

    function _removeMinter(address account) internal {
        if (!isMinter[account]) {
            return;
        }

        uint256 index = _minterIndexPlusOne[account] - 1;
        uint256 lastIndex = _minters.length - 1;

        if (index != lastIndex) {
            address lastMinter = _minters[lastIndex];
            _minters[index] = lastMinter;
            _minterIndexPlusOne[lastMinter] = index + 1;
        }

        _minters.pop();
        delete _minterIndexPlusOne[account];
        isMinter[account] = false;

        emit MintAccessRevokedEvent(account);
    }

    function _addBurner(address account) internal {
        if (account == address(0)) {
            revert ZeroAddressError();
        }
        if (isBurner[account]) {
            return;
        }

        isBurner[account] = true;
        _burnerIndexPlusOne[account] = _burners.length + 1;
        _burners.push(account);

        emit BurnAccessGrantedEvent(account);
    }

    function _removeBurner(address account) internal {
        if (!isBurner[account]) {
            return;
        }

        uint256 index = _burnerIndexPlusOne[account] - 1;
        uint256 lastIndex = _burners.length - 1;

        if (index != lastIndex) {
            address lastBurner = _burners[lastIndex];
            _burners[index] = lastBurner;
            _burnerIndexPlusOne[lastBurner] = index + 1;
        }

        _burners.pop();
        delete _burnerIndexPlusOne[account];
        isBurner[account] = false;

        emit BurnAccessRevokedEvent(account);
    }
}
