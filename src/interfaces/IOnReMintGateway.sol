// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

interface IOnReMintGateway {
    error ZeroAddressError();
    error InvalidAmountError();
    error UnauthorizedCallerError(address caller);

    function mint(address onReToken, address to, uint256 amount) external;
}
