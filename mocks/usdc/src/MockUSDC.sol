// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.6.12;

import {FiatTokenV2_2} from "../lib/circle/contracts/v2/FiatTokenV2_2.sol";
import {EIP712} from "../lib/circle/contracts/util/EIP712.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

/// @notice Standalone test token based on Circle USDC v2.2, with public minting.
/// @dev No proxy or upgrade entry point. Amounts use six decimal places.
contract MockUSDC is FiatTokenV2_2 {
    using SafeMath for uint256;

    constructor(address admin) public {
        initialize("Mock USD Coin", "USDC", "USD", 6, admin, admin, admin, admin);

        // Complete the v2/v2.1/v2.2 initialization atomically on a fresh token.
        _DEPRECATED_CACHED_DOMAIN_SEPARATOR = EIP712.makeDomainSeparator(name, "2");
        _blacklist(address(this));
        _initializedVersion = 3;
    }

    /// @notice Anyone can mint any positive amount; pause and blacklist rules still apply.
    function mint(address to, uint256 amount)
        external
        override
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(to)
        returns (bool)
    {
        require(to != address(0), "FiatToken: mint to the zero address");
        require(amount > 0, "FiatToken: mint amount not greater than 0");

        totalSupply_ = totalSupply_.add(amount);
        _setBalance(to, _balanceOf(to).add(amount));
        emit Mint(msg.sender, to, amount);
        emit Transfer(address(0), to, amount);
        return true;
    }
}
