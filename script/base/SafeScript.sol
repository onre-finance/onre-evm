// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {StdStyle, console} from "forge-std/Script.sol";
import {EnvironmentScript} from "./EnvironmentScript.sol";

/// Records Safe transactions, simulates each one as SAFE when added, and prints them as to/value/data.
abstract contract SafeScript is EnvironmentScript {
    using StdStyle for *;

    struct SafeTx {
        address to;
        bytes data;
        string name;
    }

    SafeTx[] internal _txs;
    address internal diamond;
    address internal safe;

    function _init(address _diamond, address _safe) internal {
        require(_diamond != address(0) && _safe != address(0), "DIAMOND/SAFE not set");
        delete _txs;
        diamond = _diamond;
        safe = _safe;
    }

    /// Records the tx and simulates it as SAFE. Bubbles the revert data on failure.
    function _call(address to, string memory name, bytes memory data) internal returns (bytes memory ret) {
        _txs.push(SafeTx({to: to, data: data, name: name}));

        bool ok;
        vm.prank(safe);
        (ok, ret) = to.call(data);
        if (!ok) {
            console.log(string.concat(name, " simulation failed").bold().red());
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    function _diamondCall(string memory name, bytes memory data) internal returns (bytes memory) {
        return _call(diamond, name, data);
    }

    function _log(string memory label, bytes32 value) internal pure {
        console.log(string.concat(label, ": ", value.cyanBytes32()));
    }

    function _log(string memory label, address value) internal pure {
        console.log(string.concat(label, ": ", value.cyan()));
    }

    function _log(string memory label, uint256 value) internal pure {
        console.log(string.concat(label, ": ", value.cyan()));
    }

    function _printTxs() internal view {
        console.log("Safe:", safe.cyan());
        for (uint256 i; i < _txs.length; ++i) {
            console.log("");
            console.log(string.concat("Tx ", vm.toString(i + 1), ": ", _txs[i].name).yellow().bold());
            console.log("  to:   ".dim(), _txs[i].to.cyan());
            console.log("  value:".dim(), uint256(0).cyan());
            console.log("  data: ".dim(), _txs[i].data.greenBytes());
        }
    }
}
