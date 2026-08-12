// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibDiamond} from "./libraries/LibDiamond.sol";

/// @notice EIP-2535 Diamond base: selector dispatch only.
/// @dev Deployment wiring (core facet cuts, ERC-165 registration, bootstrap
/// upgrader) lives in the Gemforge-generated `DiamondProxy`, which is rendered
/// from `templates/DiamondProxy.sol`. Keeping this contract free of
/// constructor logic is what lets Gemforge own the deployment entrypoint while
/// the dispatch and storage semantics stay first-party.
contract Diamond {
    error FunctionNotFound(bytes4 selector);

    fallback() external payable {
        address facet = LibDiamond.diamondStorage().selectorToFacetAndPosition[msg.sig].facetAddress;
        if (facet == address(0)) {
            revert FunctionNotFound(msg.sig);
        }

        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
