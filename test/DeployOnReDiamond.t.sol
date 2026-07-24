// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {DeployOnReDiamond} from "../script/DeployOnReDiamond.s.sol";
import {OnReDiamond} from "../src/OnReDiamond.sol";
import {IDiamondLoupe} from "../src/diamond/interfaces/IDiamondLoupe.sol";
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

        OnReDiamond diamond = harness.deploy(params);
        assertEq(IDiamondLoupe(address(diamond)).facetAddresses().length, 11);
        assertTrue(IOnReApp(address(diamond)).hasRole(IOnReApp(address(diamond)).DEFAULT_ADMIN_ROLE(), params.boss));
        assertTrue(IOnReApp(address(diamond)).hasRole(IOnReApp(address(diamond)).ADMIN_ROLE(), params.admin));
        assertTrue(IOnReApp(address(diamond)).hasRole(IOnReApp(address(diamond)).WORKER_ROLE(), params.worker));
        assertTrue(IOnReApp(address(diamond)).hasRole(IOnReApp(address(diamond)).UPGRADER_ROLE(), params.upgrader));
        assertFalse(IOnReApp(address(diamond)).hasRole(IOnReApp(address(diamond)).UPGRADER_ROLE(), params.boss));
        (, address configuredApprover1, address configuredApprover2) = IOnReApp(address(diamond)).appConfig();
        assertEq(configuredApprover1, approver1);
        assertEq(configuredApprover2, approver2);
    }

    function _setRequiredEnvironment() private {
        vm.setEnv("ONRE_BOSS", vm.toString(makeAddr("boss")));
        vm.setEnv("ONRE_ADMIN", vm.toString(makeAddr("admin")));
        vm.setEnv("ONRE_WORKER", vm.toString(makeAddr("worker")));
        vm.setEnv("ONRE_UPGRADER", vm.toString(makeAddr("upgrader")));
    }
}

contract DeployOnReDiamondHarness is DeployOnReDiamond {
    function deploy(OnReTypes.InitializeParams memory params) external returns (OnReDiamond) {
        return _deploy(params);
    }

    function paramsFromEnvironment() external view returns (OnReTypes.InitializeParams memory) {
        return _paramsFromEnvironment();
    }
}
