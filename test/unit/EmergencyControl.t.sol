pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {EmergencyControl} from "../../src/security/EmergencyControl.sol";

contract EmergencyControlTest is Test {
    EmergencyControl internal emergencyControl;

    address internal admin = address(this);
    address internal pauser = address(0x1001);
    address internal unpauser = address(0x1002);
    address internal unauthorized = address(0x1003);

    bytes32 internal constant SWAP = keccak256("SWAP");
    bytes32 internal constant ADD_LIQUIDITY = keccak256("ADD_LIQUIDITY");

    function setUp() public {
        emergencyControl = new EmergencyControl(admin);

        emergencyControl.grantRole(emergencyControl.PAUSER_ROLE(), pauser);

        emergencyControl.grantRole(emergencyControl.UNPAUSER_ROLE(), unpauser);
    }

    function testDeployment() public view {
        assertFalse(emergencyControl.isProtocolPaused());

        assertTrue(emergencyControl.hasRole(emergencyControl.DEFAULT_ADMIN_ROLE(), admin));
    }

    function testPauseProtocol() public {
        vm.prank(pauser);
        emergencyControl.pauseProtocol();

        assertTrue(emergencyControl.isProtocolPaused());
    }

    function testUnpauseProtocol() public {
        vm.prank(pauser);
        emergencyControl.pauseProtocol();

        vm.prank(unpauser);
        emergencyControl.unpauseProtocol();

        assertFalse(emergencyControl.isProtocolPaused());
    }

    function testRevertWhenUnauthorizedAccountPausesProtocol() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        emergencyControl.pauseProtocol();
    }

    function testRevertWhenUnauthorizedAccountUnpausesProtocol() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        emergencyControl.unpauseProtocol();
    }

    function testRevertWhenProtocolAlreadyPaused() public {
        vm.prank(pauser);
        emergencyControl.pauseProtocol();

        vm.prank(pauser);
        vm.expectRevert(EmergencyControl.AlreadyPaused.selector);
        emergencyControl.pauseProtocol();
    }

    function testRevertWhenProtocolAlreadyUnpaused() public {
        vm.prank(unpauser);
        vm.expectRevert(EmergencyControl.AlreadyUnpaused.selector);
        emergencyControl.unpauseProtocol();
    }

    function testPauseOperation() public {
        vm.prank(pauser);
        emergencyControl.pauseOperation(SWAP);

        assertTrue(emergencyControl.isOperationPaused(SWAP));
        assertTrue(emergencyControl.isPaused(SWAP));
    }

    function testUnpauseOperation() public {
        vm.prank(pauser);
        emergencyControl.pauseOperation(SWAP);

        vm.prank(unpauser);
        emergencyControl.unpauseOperation(SWAP);

        assertFalse(emergencyControl.isOperationPaused(SWAP));
        assertFalse(emergencyControl.isPaused(SWAP));
    }

    function testOperationPauseIsIndependent() public {
        vm.prank(pauser);
        emergencyControl.pauseOperation(SWAP);

        assertTrue(emergencyControl.isPaused(SWAP));
        assertFalse(emergencyControl.isPaused(ADD_LIQUIDITY));
    }

    function testProtocolPauseAffectsEveryOperation() public {
        vm.prank(pauser);
        emergencyControl.pauseProtocol();

        assertTrue(emergencyControl.isPaused(SWAP));
        assertTrue(emergencyControl.isPaused(ADD_LIQUIDITY));
    }

    function testRevertWhenOperationIsZero() public {
        vm.prank(pauser);
        vm.expectRevert(EmergencyControl.InvalidOperation.selector);
        emergencyControl.pauseOperation(bytes32(0));
    }

    function testRevertWhenOperationAlreadyPaused() public {
        vm.prank(pauser);
        emergencyControl.pauseOperation(SWAP);

        vm.prank(pauser);
        vm.expectRevert(EmergencyControl.AlreadyPaused.selector);
        emergencyControl.pauseOperation(SWAP);
    }

    function testRevertWhenOperationAlreadyUnpaused() public {
        vm.prank(unpauser);
        vm.expectRevert(EmergencyControl.AlreadyUnpaused.selector);
        emergencyControl.unpauseOperation(SWAP);
    }

    function testPauserCannotUnpauseWithoutUnpauserRole() public {
        vm.prank(pauser);
        emergencyControl.pauseProtocol();

        vm.prank(pauser);
        vm.expectRevert();
        emergencyControl.unpauseProtocol();
    }

    function testUnpauserCannotPauseWithoutPauserRole() public {
        vm.prank(unpauser);
        vm.expectRevert();
        emergencyControl.pauseProtocol();
    }

    function testRevertWhenAdminIsZero() public {
        vm.expectRevert(EmergencyControl.ZeroAdminAddress.selector);
        new EmergencyControl(address(0));
    }
}
