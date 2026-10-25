// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AMMMath} from "../src/libraries/AMMMath.sol";

contract AMMMathHarness {
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256) {
        return AMMMath.getAmountOut(
            amountIn,
            reserveIn,
            reserveOut
        );
    }
}


contract AMMMathTest is Test {

    AMMMathHarness internal harness;

    function setUp() public {

        harness = new AMMMathHarness();
    }

    function testGetAmount() public view {
        uint256 amountOut =
            harness.getAmountOut(10,1000,2000);
        
        assertEq(amountOut, 19);
    }

    function testGetAmountOutWithLargerReserves() public view {

        uint256 amountOut =
            harness.getAmountOut(1000, 10_000, 20_000);

        assertEq(amountOut, 1813);
    }

    function testRevertWhenInputZero() public {

        vm.expectRevert(AMMMath.ZeroAmount.selector);

        harness.getAmountOut(0, 1000, 2000);
    }

    function testRevertWhenInputReserveIsZero() public {

        vm.expectRevert(AMMMath.InsufficientLiquidity.selector);
        harness.getAmountOut(10, 0, 2000);
    }

    function testRevertWhenOutputReserveIsZero() public {

        vm.expectRevert(AMMMath.InsufficientLiquidity.selector);

        harness.getAmountOut(20, 1000, 0);
    }

    function testRevertWhenOutputRoundsToZero() public {

        vm.expectRevert(
            AMMMath.InsufficientOutputAmount.selector
        );

        harness.getAmountOut(1, 1_000_000, 1);
    }

    function testRevertOnIntermediateMultiplicationOverflow() public {

        vm.expectRevert();
        harness.getAmountOut(type(uint256).max, 1, 2);
    }

}

