// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @notice Marker interface: the OnRe Diamond has no ERC-173 owner.
/// @dev Gemforge's non-overridable `IDiamondProxy` template inherits IERC173
/// from `<paths.lib.diamond>/contracts/interfaces/IERC173.sol`, so the file has
/// to exist. Upgrade authority here is `LibOnReRoles.UPGRADER_ROLE` and the
/// account authority is the two-step boss transfer in `LibOnReAccessControl`,
/// neither of which matches ERC-173's single-owner, single-step semantics.
/// Declaring the interface empty keeps `IDiamondProxy` from advertising an
/// `owner()`/`transferOwnership()` the diamond does not implement.
///
/// To opt into ERC-173 later: declare `owner()` here, implement it on a *core*
/// facet under this folder (a user facet under `src/facets` would collide with
/// the same signature inherited into `IDiamondProxy`), and add its selector to
/// `diamond.coreFacets` and `diamond.protectedMethods` in `gemforge.config.cjs`.
interface IERC173 {}
