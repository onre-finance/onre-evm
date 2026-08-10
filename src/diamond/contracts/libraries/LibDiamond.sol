// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";

library LibDiamond {
    error EmptyFacetSelectors();
    error FacetHasNoCode(address facet);
    error FacetAddressIsZero();
    error FunctionAlreadyExists(bytes4 selector);
    error FunctionDoesNotExist(bytes4 selector);
    error FunctionIsImmutable(bytes4 selector);
    error FunctionAlreadyUsesFacet(bytes4 selector, address facet);
    error InvalidFacetCutAction(uint8 action);
    error InvalidInitialization(address init, bytes initCalldata);
    error InitializationReverted(address init, bytes initCalldata);
    error PositionOverflow(uint256 position);
    error RemoveFacetAddressMustBeZero(address facet);

    /// @custom:storage-location erc7201:onre.storage.Diamond
    struct DiamondStorage {
        mapping(bytes4 selector => FacetAddressAndPosition data) selectorToFacetAndPosition;
        mapping(address facet => FacetFunctionSelectors data) facetFunctionSelectors;
        address[] facetAddresses;
        mapping(bytes4 interfaceId => bool supported) supportedInterfaces;
    }

    struct FacetAddressAndPosition {
        address facetAddress;
        uint32 functionSelectorPosition;
    }

    struct FacetFunctionSelectors {
        bytes4[] functionSelectors;
        uint32 facetAddressPosition;
    }

    // keccak256(abi.encode(uint256(keccak256("onre.storage.Diamond")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant DIAMOND_STORAGE_LOCATION =
        0xe7a65135aebfc21c80a162a36674f54347f18e2d3a36aad28796c9ad8e262e00;

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 location = DIAMOND_STORAGE_LOCATION;
        assembly ("memory-safe") {
            ds.slot := location
        }
    }

    function diamondCut(IDiamondCut.FacetCut[] memory cut, address init, bytes memory initCalldata) internal {
        uint256 cutLength = cut.length;
        for (uint256 i = 0; i < cutLength;) {
            IDiamondCut.FacetCut memory facetCut = cut[i];
            if (facetCut.action == IDiamondCut.FacetCutAction.Add) {
                _addFunctions(facetCut.facetAddress, facetCut.functionSelectors);
            } else if (facetCut.action == IDiamondCut.FacetCutAction.Replace) {
                _replaceFunctions(facetCut.facetAddress, facetCut.functionSelectors);
            } else if (facetCut.action == IDiamondCut.FacetCutAction.Remove) {
                _removeFunctions(facetCut.facetAddress, facetCut.functionSelectors);
            } else {
                revert InvalidFacetCutAction(uint8(facetCut.action));
            }
            unchecked {
                ++i;
            }
        }

        emit IDiamondCut.DiamondCut(cut, init, initCalldata);
        _initializeDiamondCut(init, initCalldata);
    }

    function _addFunctions(address facet, bytes4[] memory selectors) private {
        if (selectors.length == 0) {
            revert EmptyFacetSelectors();
        }
        if (facet == address(0)) {
            revert FacetAddressIsZero();
        }

        DiamondStorage storage ds = diamondStorage();
        uint256 selectorPosition = ds.facetFunctionSelectors[facet].functionSelectors.length;
        if (selectorPosition == 0) {
            _enforceHasContractCode(facet);
            ds.facetFunctionSelectors[facet].facetAddressPosition = _toUint32(ds.facetAddresses.length);
            ds.facetAddresses.push(facet);
        }

        uint256 selectorLength = selectors.length;
        for (uint256 i = 0; i < selectorLength;) {
            bytes4 selector = selectors[i];
            if (ds.selectorToFacetAndPosition[selector].facetAddress != address(0)) {
                revert FunctionAlreadyExists(selector);
            }
            ds.facetFunctionSelectors[facet].functionSelectors.push(selector);
            ds.selectorToFacetAndPosition[selector] =
                FacetAddressAndPosition({facetAddress: facet, functionSelectorPosition: _toUint32(selectorPosition)});
            unchecked {
                ++selectorPosition;
                ++i;
            }
        }
    }

    function _replaceFunctions(address facet, bytes4[] memory selectors) private {
        if (selectors.length == 0) {
            revert EmptyFacetSelectors();
        }
        if (facet == address(0)) {
            revert FacetAddressIsZero();
        }

        DiamondStorage storage ds = diamondStorage();
        uint256 selectorPosition = ds.facetFunctionSelectors[facet].functionSelectors.length;
        if (selectorPosition == 0) {
            _enforceHasContractCode(facet);
            ds.facetFunctionSelectors[facet].facetAddressPosition = _toUint32(ds.facetAddresses.length);
            ds.facetAddresses.push(facet);
        }

        uint256 selectorLength = selectors.length;
        for (uint256 i = 0; i < selectorLength;) {
            bytes4 selector = selectors[i];
            address oldFacet = ds.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacet == address(0)) {
                revert FunctionDoesNotExist(selector);
            }
            if (oldFacet == facet) {
                revert FunctionAlreadyUsesFacet(selector, facet);
            }
            _removeFunction(oldFacet, selector);
            ds.facetFunctionSelectors[facet].functionSelectors.push(selector);
            ds.selectorToFacetAndPosition[selector] =
                FacetAddressAndPosition({facetAddress: facet, functionSelectorPosition: _toUint32(selectorPosition)});
            unchecked {
                ++selectorPosition;
                ++i;
            }
        }
    }

    function _removeFunctions(address facet, bytes4[] memory selectors) private {
        if (selectors.length == 0) {
            revert EmptyFacetSelectors();
        }
        if (facet != address(0)) {
            revert RemoveFacetAddressMustBeZero(facet);
        }

        DiamondStorage storage ds = diamondStorage();
        uint256 selectorLength = selectors.length;
        for (uint256 i = 0; i < selectorLength;) {
            bytes4 selector = selectors[i];
            if (selector == IDiamondCut.diamondCut.selector) {
                revert FunctionIsImmutable(selector);
            }
            address oldFacet = ds.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacet == address(0)) {
                revert FunctionDoesNotExist(selector);
            }
            _removeFunction(oldFacet, selector);
            unchecked {
                ++i;
            }
        }
    }

    function _removeFunction(address facet, bytes4 selector) private {
        if (facet == address(this)) {
            revert FunctionIsImmutable(selector);
        }

        DiamondStorage storage ds = diamondStorage();
        uint256 selectorPosition = ds.selectorToFacetAndPosition[selector].functionSelectorPosition;
        bytes4[] storage facetSelectors = ds.facetFunctionSelectors[facet].functionSelectors;
        uint256 lastSelectorPosition = facetSelectors.length - 1;
        if (selectorPosition != lastSelectorPosition) {
            bytes4 lastSelector = facetSelectors[lastSelectorPosition];
            facetSelectors[selectorPosition] = lastSelector;
            ds.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = _toUint32(selectorPosition);
        }
        facetSelectors.pop();
        delete ds.selectorToFacetAndPosition[selector];

        if (lastSelectorPosition == 0) {
            uint256 facetPosition = ds.facetFunctionSelectors[facet].facetAddressPosition;
            uint256 lastFacetPosition = ds.facetAddresses.length - 1;
            if (facetPosition != lastFacetPosition) {
                address lastFacet = ds.facetAddresses[lastFacetPosition];
                ds.facetAddresses[facetPosition] = lastFacet;
                ds.facetFunctionSelectors[lastFacet].facetAddressPosition = _toUint32(facetPosition);
            }
            ds.facetAddresses.pop();
            delete ds.facetFunctionSelectors[facet].facetAddressPosition;
        }
    }

    function _initializeDiamondCut(address init, bytes memory initCalldata) private {
        if (init == address(0)) {
            if (initCalldata.length != 0) {
                revert InvalidInitialization(init, initCalldata);
            }
            return;
        }
        if (initCalldata.length == 0) {
            revert InvalidInitialization(init, initCalldata);
        }
        if (init != address(this)) {
            _enforceHasContractCode(init);
        }

        (bool success, bytes memory returndata) = init.delegatecall(initCalldata);
        if (!success) {
            if (returndata.length == 0) {
                revert InitializationReverted(init, initCalldata);
            }
            assembly ("memory-safe") {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }
    }

    function _enforceHasContractCode(address target) private view {
        if (target.code.length == 0) {
            revert FacetHasNoCode(target);
        }
    }

    function _toUint32(uint256 position) private pure returns (uint32 result) {
        if (position > type(uint32).max) {
            revert PositionOverflow(position);
        }
        assembly ("memory-safe") {
            result := position
        }
    }
}
