// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IOnReMintGateway} from "./interfaces/IOnReMintGateway.sol";

interface IOnReMintableToken {
    function mint(address to, uint256 amount) external;
}

contract OnReMintGateway is IOnReMintGateway {
    address private immutable _onReApp;

    constructor(address onReApp_) {
        if (onReApp_ == address(0)) {
            revert ZeroAddressError();
        }

        _onReApp = onReApp_;
    }

    function mint(address onReToken, address to, uint256 amount) external {
        if (msg.sender != _onReApp) {
            revert UnauthorizedCallerError(msg.sender);
        }
        if (onReToken == address(0) || to == address(0)) {
            revert ZeroAddressError();
        }
        if (amount == 0) {
            revert InvalidAmountError();
        }

        IOnReMintableToken(onReToken).mint(to, amount);
    }
}
