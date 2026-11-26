pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {EmergencyControl} from "../../src/security/EmergencyControl.sol";
import {TokenPolicy} from "../../src/security/TokenPolicy.sol";

contract AMMFactoryFeeTest is Test {
    AMMFactory factory;
    EmergencyControl internal emergencyControl;
    TokenPolicy internal tokenPolicy;
    address admin = address(1);
    address alice = address(2);
    address treasury = address(3);

    function setUp() public {
        emergencyControl = new EmergencyControl(address(this));
        tokenPolicy = new TokenPolicy(address(this));
        vm.prank(admin);
        factory = new AMMFactory(
            address(emergencyControl),
            address(tokenPolicy)
        );
    }

    function testInitialFeeConfiguration() public view {
        assertEq(factory.feeTo(), address(0));
        assertEq(factory.feeToSetter(), admin);
    }

    function testAdminCanSetFeeRecipient() public {
        vm.prank(admin);
        factory.setFeeTo(treasury);
        assertEq(factory.feeTo(), treasury);
    }

    function testAdminCanDisableProtocolFee() public {
        vm.startPrank(admin);

        factory.setFeeTo(treasury);
        factory.setFeeTo(address(0));

        vm.stopPrank();

        assertEq(factory.feeTo(), address(0));
    }

    function testUnauthorizedCannotSetFeeRecipient() public {
        vm.prank(alice);

        vm.expectRevert(AMMFactory.Unauthorized.selector);

        factory.setFeeTo(treasury);
    }

    function testAdminCanTransferFeeSetterRole() public {
        vm.prank(admin);
        factory.setFeeToSetter(alice);
        assertEq(factory.feeToSetter(), alice);
    }

    function testPreviousAdminLosesAuthority() public {
        vm.prank(admin);

        factory.setFeeToSetter(alice);

        vm.prank(admin);

        vm.expectRevert(AMMFactory.Unauthorized.selector);

        factory.setFeeTo(treasury);
    }

    function testCannotSetZeroAddress() public {
        vm.prank(admin);

        vm.expectRevert(AMMFactory.ZeroAddress.selector);

        factory.setFeeToSetter(address(0));
    }
}
