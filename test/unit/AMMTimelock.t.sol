pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AMMTimelock} from "../../src/governance/AMMTimelock.sol";

contract TimelockTarget {
    uint256 public value;

    function setValue(uint256 newValue) external {
        value = newValue;
    }
}

contract AMMTimelockTest is Test {
    AMMTimelock internal timelock;
    TimelockTarget internal target;

    address internal admin = address(this);
    address internal proposer = address(0x1001);
    address internal executor = address(0x1002);
    address internal unauthorized = address(0x1003);

    uint256 internal constant MIN_DELAY = 1 days;

    function setUp() public {
        timelock = new AMMTimelock(MIN_DELAY, admin);
        target = new TimelockTarget();

        timelock.grantRole(timelock.PROPOSER_ROLE(), proposer);
        timelock.grantRole(timelock.CANCELLER_ROLE(), proposer);
        timelock.grantRole(timelock.EXECUTOR_ROLE(), executor);
    }

    function testDeployment() public view {
        assertEq(timelock.getMinDelay(), MIN_DELAY);
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), admin));
    }

    function testRevertWhenMinimumDelayIsZero() public {
        vm.expectRevert(AMMTimelock.ZeroMinDelay.selector);
        new AMMTimelock(0, admin);
    }

    function testRevertWhenAdminIsZero() public {
        vm.expectRevert(AMMTimelock.ZeroAdminAddress.selector);
        new AMMTimelock(MIN_DELAY, address(0));
    }

    function testRevertWhenUnauthorizedAccountSchedulesOperation() public {
        bytes memory data = abi.encodeCall(target.setValue, (100));

        vm.prank(unauthorized);
        vm.expectRevert();
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32("operation-1"), MIN_DELAY);
    }

    function testScheduleAndExecuteOperation() public {
        bytes memory data = abi.encodeCall(target.setValue, (100));
        bytes32 salt = bytes32("operation-2");

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), salt, MIN_DELAY);

        bytes32 operationId = timelock.hashOperation(address(target), 0, data, bytes32(0), salt);

        assertTrue(timelock.isOperationPending(operationId));

        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(target), 0, data, bytes32(0), salt);

        vm.warp(block.timestamp + MIN_DELAY);

        vm.prank(executor);
        timelock.execute(address(target), 0, data, bytes32(0), salt);

        assertEq(target.value(), 100);
        assertTrue(timelock.isOperationDone(operationId));
    }

    function testCancelScheduledOperation() public {
        bytes memory data = abi.encodeCall(target.setValue, (200));
        bytes32 salt = bytes32("operation-3");

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), salt, MIN_DELAY);

        bytes32 operationId = timelock.hashOperation(address(target), 0, data, bytes32(0), salt);

        vm.prank(proposer);
        timelock.cancel(operationId);

        assertFalse(timelock.isOperationPending(operationId));
    }

    function testRevertWhenUnauthorizedAccountCancelsOperation() public {
        bytes memory data = abi.encodeCall(target.setValue, (300));
        bytes32 salt = bytes32("operation-4");

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), salt, MIN_DELAY);

        bytes32 operationId = timelock.hashOperation(address(target), 0, data, bytes32(0), salt);

        vm.prank(unauthorized);
        vm.expectRevert();
        timelock.cancel(operationId);
    }

    function testOnlyTimelockCanUpdateDelay() public {
        vm.expectRevert();
        timelock.updateDelay(2 days);
    }
}
