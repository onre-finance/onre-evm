// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

// Gemforge's non-overridable `IDiamondProxy` template imports IERC165 from
// `<paths.lib.diamond>/contracts/interfaces/IERC165.sol`, so a file must exist
// here. Re-exporting the OpenZeppelin declaration keeps a single IERC165 type
// across the build, so `type(IERC165).interfaceId` cannot drift between the
// generated proxy interface and the facets that register it.
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
