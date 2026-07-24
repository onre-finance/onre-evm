// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReConfig} from "../libraries/LibOnReConfig.sol";

contract OnReConfigFacet {
    function registerOnReToken(address onReToken, uint256 maxSupply, uint256 maxMintAmount) external {
        LibOnReConfig.registerOnReToken(onReToken, maxSupply, maxMintAmount);
    }

    function setOnReTokenEnabled(address onReToken, bool enabled) external {
        LibOnReConfig.setOnReTokenEnabled(onReToken, enabled);
    }

    function setOnReTokenLimits(address onReToken, uint256 maxSupply, uint256 maxMintAmount) external {
        LibOnReConfig.setOnReTokenLimits(onReToken, maxSupply, maxMintAmount);
    }

    function addExcludedSupplyAddress(address onReToken, address account) external {
        LibOnReConfig.addExcludedSupplyAddress(onReToken, account);
    }

    function removeExcludedSupplyAddress(address onReToken, address account) external {
        LibOnReConfig.removeExcludedSupplyAddress(onReToken, account);
    }

    function setMintGateway(address newMintGateway) external {
        LibOnReConfig.setMintGateway(newMintGateway);
    }

    function addApprover(address approver) external {
        LibOnReConfig.addApprover(approver);
    }

    function removeApprover(address approver) external {
        LibOnReConfig.removeApprover(approver);
    }

    function setKillSwitch(bool killed) external {
        LibOnReConfig.setKillSwitch(killed);
    }
}
