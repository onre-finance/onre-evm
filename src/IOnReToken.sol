// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IGetCCIPAdmin} from "@chainlink/contracts/src/v0.8/shared/interfaces/IGetCCIPAdmin.sol";

interface IOnReToken is IGetCCIPAdmin {
    struct InitializeParams {
        string name;
        string symbol;
        address admin;
        address ccipAdmin;
        address[] initialMinters;
        address[] initialBurners;
    }

    event MintAccessGrantedEvent(address indexed minter);
    event BurnAccessGrantedEvent(address indexed burner);
    event MintAccessRevokedEvent(address indexed minter);
    event BurnAccessRevokedEvent(address indexed burner);
    event CCIPAdminTransferredEvent(address indexed previousAdmin, address indexed newAdmin);
    event BufferControllerSet(address indexed oldController, address indexed newController);

    error SenderNotMinterError(address sender);
    error SenderNotBurnerError(address sender);
    error SenderNotBufferControllerError(address sender);
    error BufferControllerHasNoCodeError(address controller);

    function burn(uint256 amount) external;

    function mintBuffer(uint256 amount) external;

    function bufferController() external view returns (address);

    function setBufferController(address newController) external;
}
