// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {console} from "forge-std/Script.sol";
import {EnvironmentScript} from "./EnvironmentScript.sol";

/// Records Safe transactions, simulates each one as SAFE when added, and prints them as to/value/data.
abstract contract SafeScript is EnvironmentScript {
    struct SafeTx {
        address to;
        bytes data;
        string name;
    }

    SafeTx[] internal _txs;
    address internal diamond;
    address internal safe;

    function _init(address diamond_, address safe_) internal {
        require(diamond_ != address(0) && safe_ != address(0), "DIAMOND/SAFE not set");
        diamond = diamond_;
        safe = safe_;
    }

    /// Records the tx and simulates it as SAFE. Bubbles the revert data on failure.
    function _call(address to, string memory name, bytes memory data) internal returns (bytes memory ret) {
        _txs.push(SafeTx({to: to, data: data, name: name}));

        bool ok;
        vm.prank(safe);
        (ok, ret) = to.call(data);
        if (!ok) {
            console.log(string.concat(name, " simulation failed"));
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    function _diamondCall(string memory name, bytes memory data) internal returns (bytes memory) {
        return _call(diamond, name, data);
    }

    function _log(string memory label, bytes32 value) internal view {
        console.log(string.concat(label, ": ", vm.toString(value)));
    }

    function _log(string memory label, address value) internal view {
        console.log(string.concat(label, ": ", vm.toString(value)));
    }

    function _log(string memory label, uint256 value) internal view {
        console.log(string.concat(label, ": ", vm.toString(value)));
    }

    function _printTxs() internal view {
        console.log("Safe:", safe);
        for (uint256 i; i < _txs.length; ++i) {
            console.log("");
            console.log(string.concat("Tx ", vm.toString(i + 1), ": ", _txs[i].name));
            console.log("  to:   ", _txs[i].to);
            console.log("  value: 0");
            console.log("  data: ", vm.toString(_txs[i].data));
        }
    }
}
