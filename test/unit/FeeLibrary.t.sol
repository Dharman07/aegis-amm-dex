pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {FeeLibrary} from "../../src/fees/FeeLibrary.sol";

contract FeeLibraryTest is Test {
    function testReturnsZeroWhenKLastIsZero() public pure {
        uint256 liquidity = FeeLibrary.calculateProtocolFeeLiquidity(1000, 1200, 1200, 0);

        assertEq(liquidity, 0);
    }

    function testReturnsZeroWhenTotalSupplyIsZero() public pure {
        uint256 liquidity = FeeLibrary.calculateProtocolFeeLiquidity(0, 1200, 1200, 1_000_000);

        assertEq(liquidity, 0);
    }

    function testReturnsZeroWhenKIsUnchanged() public pure {
        uint256 liquidity = FeeLibrary.calculateProtocolFeeLiquidity(1000, 1000, 1000, 1_000_000);

        assertEq(liquidity, 0);
    }

    function testReturnsZeroWhenKDecreases() public pure {
        uint256 liquidity = FeeLibrary.calculateProtocolFeeLiquidity(1000, 900, 900, 1_000_000);

        assertEq(liquidity, 0);
    }

    function testCalculatesProtocolFeeCorrectly() public pure {
        uint256 liquidity = FeeLibrary.calculateProtocolFeeLiquidity(1000, 1200, 1200, 1_000_000);

        assertEq(liquidity, 28);
    }

    function testReturnsZeroWhenFeeRoundsDownToZero() public pure {
        uint256 liquidity = FeeLibrary.calculateProtocolFeeLiquidity(1, 1200, 1200, 1_000_000);

        assertEq(liquidity, 0);
    }

    function testCalculatesFeeWithDifferentReserves() public pure {
        uint256 liquidity = FeeLibrary.calculateProtocolFeeLiquidity(10_000, 1500, 1500, 1_000_000);

        assertEq(liquidity, 588);
    }
}
