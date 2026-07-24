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

    error ZeroAddressError();
    error SenderNotMinterError(address sender);
    error SenderNotBurnerError(address sender);

    function burn(uint256 amount) external;
}
