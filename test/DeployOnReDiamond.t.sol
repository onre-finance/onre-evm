// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {DeployOnReDiamond} from "../script/DeployOnReDiamond.s.sol";
import {OnReDiamond} from "../src/OnReDiamond.sol";
import {IDiamondLoupe} from "../src/diamond/interfaces/IDiamondLoupe.sol";
import {IDiamondOwnership} from "../src/diamond/interfaces/IDiamondOwnership.sol";
import {IOnReApp} from "../src/interfaces/IOnReApp.sol";
import {OnReTypes} from "../src/types/OnReTypes.sol";

contract DeployOnReDiamondTest is Test {
    DeployOnReDiamondHarness private harness;

    function setUp() public {
        harness = new DeployOnReDiamondHarness();
        _setRequiredEnvironment();
    }

    function test_ProductionDeploymentAndOptionalApproverAssembly() public {
        vm.setEnv("ONRE_APPROVER_1", vm.toString(address(0)));
        vm.setEnv("ONRE_APPROVER_2", vm.toString(address(0)));
        assertEq(harness.paramsFromEnvironment().approvers.length, 0);

        address approver1 = makeAddr("approver1");
        vm.setEnv("ONRE_APPROVER_1", vm.toString(approver1));
        assertEq(harness.paramsFromEnvironment().approvers.length, 1);

        address approver2 = makeAddr("approver2");
        vm.setEnv("ONRE_APPROVER_2", vm.toString(approver2));
        OnReTypes.InitializeParams memory params = harness.paramsFromEnvironment();
        assertEq(params.approvers.length, 2);
        assertEq(params.approvers[0], approver1);
        assertEq(params.approvers[1], approver2);

        address diamondOwner = makeAddr("diamondOwner");
        OnReDiamond diamond = harness.deploy(diamondOwner, params);
        assertEq(IDiamondLoupe(address(diamond)).facetAddresses().length, 12);
        assertEq(IDiamondOwnership(address(diamond)).owner(), diamondOwner);
        assertTrue(IOnReApp(address(diamond)).hasRole(IOnReApp(address(diamond)).DEFAULT_ADMIN_ROLE(), params.admin));
        assertTrue(IOnReApp(address(diamond)).hasRole(IOnReApp(address(diamond)).WORKER_ROLE(), params.worker));
        (, address configuredApprover1, address configuredApprover2,) = IOnReApp(address(diamond)).appConfig();
        assertEq(configuredApprover1, approver1);
        assertEq(configuredApprover2, approver2);
    }

    function _setRequiredEnvironment() private {
        vm.setEnv("ONRE_ADMIN", vm.toString(makeAddr("admin")));
        vm.setEnv("ONRE_WORKER", vm.toString(makeAddr("worker")));
    }
}

contract DeployOnReDiamondHarness is DeployOnReDiamond {
    function deploy(address diamondOwner, OnReTypes.InitializeParams memory params) external returns (OnReDiamond) {
        return _deploy(diamondOwner, params);
    }

    function paramsFromEnvironment() external view returns (OnReTypes.InitializeParams memory) {
        return _paramsFromEnvironment();
    }
}
