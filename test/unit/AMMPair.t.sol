pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AMMPair} from "../../src/core/AMMPair.sol";
import {LPToken} from "../../src/token/LPToken.sol";
import {AMMLibrary} from "../../src/libraries/AMMLibrary.sol";
import {EmergencyControl} from "../../src/security/EmergencyControl.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AMMLibraryHarness {
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256) {
        return AMMLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return AMMLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return AMMLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getReserves(address pair, address tokenA, address tokenB) external view returns (uint256, uint256) {
        return AMMLibrary.getReserves(pair, tokenA, tokenB);
    }
}

contract AMMPairLiquidityHarness is AMMPair {
    constructor(address token0_, address token1_, address emergencyControl_)
        AMMPair(token0_, token1_, emergencyControl_)
    {}

    function calculateLiquidityAmounts(uint256 amount0Desired, uint256 amount1Desired)
        external
        view
        returns (uint256 amount0, uint256 amount1)
    {
        return _calculateLiquidityAmounts(amount0Desired, amount1Desired);
    }
}

contract AMMPairTest is Test {
    MockERC20 internal token0;
    MockERC20 internal token1;

    AMMPair internal pair;
    LPToken internal lpToken;
    EmergencyControl internal emergencyControl;
    AMMLibraryHarness internal libraryHarness;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant INITIAL_AMOUNT0 = 10 ether;
    uint256 internal constant INITIAL_AMOUNT1 = 20 ether;

    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    address internal constant DEAD_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    function setUp() public {
        token0 = new MockERC20("Mock Token 0", "MTK0");

        token1 = new MockERC20("Mock Token 1", "MTK1");

        emergencyControl = new EmergencyControl(address(this));

        pair = new AMMPair(address(token0), address(token1), address(emergencyControl));

        lpToken = pair.lpToken();

        libraryHarness = new AMMLibraryHarness();

        token0.mint(alice, 1000 ether);

        token1.mint(alice, 1000 ether);

        token0.mint(bob, 1000 ether);

        token1.mint(bob, 1000 ether);
    }

    function testInitialLiquidity() public {
        vm.startPrank(alice);

        token0.approve(address(pair), INITIAL_AMOUNT0);

        token1.approve(address(pair), INITIAL_AMOUNT1);

        (uint256 amount0, uint256 amount1, uint256 liquidity) =
            pair.addLiquidity(INITIAL_AMOUNT0, INITIAL_AMOUNT1, INITIAL_AMOUNT0, INITIAL_AMOUNT1, alice);

        vm.stopPrank();

        uint256 expectedLiquidity = _sqrt(INITIAL_AMOUNT0 * INITIAL_AMOUNT1) - MINIMUM_LIQUIDITY;

        assertEq(amount0, INITIAL_AMOUNT0);
        assertEq(amount1, INITIAL_AMOUNT1);
        assertEq(liquidity, expectedLiquidity);

        assertEq(lpToken.balanceOf(alice), expectedLiquidity);

        assertEq(lpToken.balanceOf(DEAD_ADDRESS), MINIMUM_LIQUIDITY);

        assertEq(lpToken.totalSupply(), expectedLiquidity + MINIMUM_LIQUIDITY);
    }

    function testInitialReservesAreUpdated() public {
        _addInitialLiquidity();

        assertEq(pair.reserve0(), INITIAL_AMOUNT0);

        assertEq(pair.reserve1(), INITIAL_AMOUNT1);

        assertEq(token0.balanceOf(address(pair)), INITIAL_AMOUNT0);

        assertEq(token1.balanceOf(address(pair)), INITIAL_AMOUNT1);
    }

    function testSecondProviderReceivesProportionalLiquidity() public {
        // 1. First provider adds initial liquidity
        _addInitialLiquidity();

        // 2. Bob's deposit amounts
        uint256 amount0 = 5 ether;
        uint256 amount1 = 10 ether;

        // 3. Snapshot pool state BEFORE Bob adds liquidity
        uint256 supplyBefore = lpToken.totalSupply();
        uint256 reserve0Before = pair.reserve0();

        // 4. Calculate expected LP tokens using previous pool state
        uint256 expectedLiquidity = (amount0 * supplyBefore) / reserve0Before;

        // 5. Bob approves tokens
        vm.startPrank(bob);

        token0.approve(address(pair), amount0);
        token1.approve(address(pair), amount1);

        // 6. Bob adds liquidity
        (,, uint256 liquidity) = pair.addLiquidity(amount0, amount1, amount0, amount1, bob);

        vm.stopPrank();

        // 7. Verify LP tokens received
        assertEq(liquidity, expectedLiquidity);

        assertEq(lpToken.balanceOf(bob), expectedLiquidity);

        // 8. Verify updated reserves
        assertEq(pair.reserve0(), INITIAL_AMOUNT0 + amount0);

        assertEq(pair.reserve1(), INITIAL_AMOUNT1 + amount1);
    }

    function testOptimalAmountUsesPoolRatio() public {
        _addInitialLiquidity();

        uint256 amount0Desired = 2 ether;
        uint256 amount1Desired = 6 ether;

        vm.startPrank(bob);

        token0.approve(address(pair), amount0Desired);

        token1.approve(address(pair), amount1Desired);

        (uint256 amount0,, uint256 liquidity) =
            pair.addLiquidity(amount0Desired, amount1Desired, amount0Desired, 4 ether, bob);

        vm.stopPrank();

        assertEq(amount0, 2 ether);

        assertEq(pair.reserve0(), INITIAL_AMOUNT0 + 2 ether);

        assertEq(pair.reserve1(), INITIAL_AMOUNT1 + 4 ether);
    }

    function testReverWhenRecipientIsZero() public {
        vm.expectRevert(AMMPair.InvalidRecipient.selector);

        pair.addLiquidity(1 ether, 2 ether, 1 ether, 2 ether, address(0));
    }

    function testRevertWhenDesiredAmountIsZero() public {
        vm.expectRevert(AMMPair.InsufficientAmount.selector);

        pair.addLiquidity(0, 1 ether, 0, 1 ether, alice);
    }

    function testRevertWhenSlippageMinimumIsNotMet() public {
        _addInitialLiquidity();

        vm.startPrank(bob);

        token0.approve(address(pair), 2 ether);

        token1.approve(address(pair), 6 ether);

        vm.expectRevert(AMMPair.InsufficientAmountReceived.selector);

        pair.addLiquidity(2 ether, 6 ether, 2 ether, 5 ether, bob);

        vm.stopPrank();
    }

    function testRevertWhenInitialSupplyLiquidityIsZero() public {
        vm.startPrank(alice);

        token0.approve(address(pair), 1000);

        token1.approve(address(pair), 1000);

        vm.expectRevert(AMMPair.InsufficientLiquidityMinted.selector);

        pair.addLiquidity(1000, 1000, 1000, 1000, alice);

        vm.stopPrank();
    }

    function testRemoveLiquidity() public {
        _addInitialLiquidity();

        uint256 liquidity = lpToken.balanceOf(alice) / 2;

        uint256 supplyBefore = lpToken.totalSupply();
        uint256 reserve0Before = pair.reserve0();
        uint256 reserve1Before = pair.reserve1();

        uint256 expectedAmount0 = (liquidity * reserve0Before) / supplyBefore;

        uint256 expectedAmount1 = (liquidity * reserve1Before) / supplyBefore;

        uint256 aliceToken0Before = token0.balanceOf(alice);
        uint256 aliceToken1Before = token1.balanceOf(alice);

        vm.prank(alice);

        (uint256 amount0, uint256 amount1) = pair.removeLiquidity(liquidity, expectedAmount0, expectedAmount1, alice);

        assertEq(amount0, expectedAmount0);
        assertEq(amount1, expectedAmount1);

        assertEq(token0.balanceOf(alice), aliceToken0Before + amount0);

        assertEq(token1.balanceOf(alice), aliceToken1Before + amount1);
    }

    function testRemoveLiquidityUpdateReserves() public {
        _addInitialLiquidity();

        uint256 liquidity = lpToken.balanceOf(alice) / 2;

        uint256 supplyBefore = lpToken.totalSupply();

        uint256 expectedAmount0 = (liquidity * pair.reserve0()) / supplyBefore;

        uint256 expectedAmount1 = (liquidity * pair.reserve1()) / supplyBefore;

        vm.prank(alice);

        pair.removeLiquidity(liquidity, 0, 0, alice);

        assertEq(pair.reserve0(), INITIAL_AMOUNT0 - expectedAmount0);

        assertEq(pair.reserve1(), INITIAL_AMOUNT1 - expectedAmount1);
    }

    function testRemoveLiquidityBurnsLPTokens() public {
        _addInitialLiquidity();

        uint256 liquidity = lpToken.balanceOf(alice) / 2;

        uint256 aliceLPBefore = lpToken.balanceOf(alice);
        uint256 totalSupplyBefore = lpToken.totalSupply();

        vm.prank(alice);

        pair.removeLiquidity(liquidity, 0, 0, alice);

        assertEq(lpToken.balanceOf(alice), aliceLPBefore - liquidity);

        assertEq(lpToken.totalSupply(), totalSupplyBefore - liquidity);
    }

    function testRemoveLiquidityRevertsForZeroLiquidity() public {
        vm.expectRevert(AMMPair.InsufficientAmount.selector);

        pair.removeLiquidity(0, 0, 0, alice);
    }

    function testRemoveLiquidityRevertForZeroRecipient() public {
        _addInitialLiquidity();

        uint256 liquidity = lpToken.balanceOf(alice) / 2;

        vm.expectRevert(AMMPair.InvalidRecipient.selector);

        vm.prank(alice);

        pair.removeLiquidity(liquidity, 0, 0, address(0));
    }

    function testRemoveLiquidityRevertsWhenSlippageMinimumNotMet() public {
        _addInitialLiquidity();

        uint256 liquidity = lpToken.balanceOf(alice) / 2;

        uint256 supplyBefore = lpToken.totalSupply();

        uint256 expectedAmount0 = (liquidity * pair.reserve0()) / supplyBefore;

        uint256 expectedAmount1 = (liquidity * pair.reserve1()) / supplyBefore;

        vm.expectRevert(AMMPair.InsufficientAmountReceived.selector);

        vm.prank(alice);

        pair.removeLiquidity(liquidity, expectedAmount0 + 1, expectedAmount1, alice);
    }

    function _addInitialLiquidity() public {
        vm.startPrank(alice);

        token0.approve(address(pair), INITIAL_AMOUNT0);

        token1.approve(address(pair), INITIAL_AMOUNT1);

        pair.addLiquidity(INITIAL_AMOUNT0, INITIAL_AMOUNT1, INITIAL_AMOUNT0, INITIAL_AMOUNT1, alice);

        vm.stopPrank();
    }

    function testSwapToken0ForToken1() public {
        _addInitialLiquidity();

        uint256 amountIn = 1 ether;

        token0.mint(alice, amountIn);

        uint256 reserve0Before = pair.reserve0();
        uint256 reserve1Before = pair.reserve1();

        uint256 aliceToken1Before = token1.balanceOf(alice);

        uint256 amountInWithFee = amountIn * 997;

        uint256 expectedAmountOut = (amountInWithFee * reserve1Before) / ((reserve0Before * 1000) + amountInWithFee);

        vm.startPrank(alice);

        token0.transfer(address(pair), amountIn);

        pair.swap(0, expectedAmountOut, alice);

        vm.stopPrank();

        assertEq(token1.balanceOf(alice) - aliceToken1Before, expectedAmountOut);

        assertEq(pair.reserve0(), reserve0Before + amountIn);

        assertEq(pair.reserve1(), reserve1Before - expectedAmountOut);
    }

    function testSwapToken1ForToken0() public {
        _addInitialLiquidity();

        uint256 amountIn = 2 ether;

        token1.mint(alice, amountIn);

        uint256 reserve0Before = pair.reserve0();
        uint256 reserve1Before = pair.reserve1();

        uint256 aliceToken0Before = token0.balanceOf(alice);

        uint256 amountInWithFee = amountIn * 997;

        uint256 expectedAmountOut = (amountInWithFee * reserve0Before) / ((reserve1Before * 1000) + amountInWithFee);

        vm.startPrank(alice);

        token1.transfer(address(pair), amountIn);

        pair.swap(expectedAmountOut, 0, alice);

        vm.stopPrank();

        assertEq(token0.balanceOf(alice) - aliceToken0Before, expectedAmountOut);

        assertEq(pair.reserve0(), reserve0Before - expectedAmountOut);

        assertEq(pair.reserve1(), reserve1Before + amountIn);
    }

    function testSwapUpdatesReserves() public {
        _addInitialLiquidity();

        uint256 amountIn = 1 ether;

        token0.mint(alice, amountIn);

        uint256 reserve0Before = pair.reserve0();
        uint256 reserve1Before = pair.reserve1();

        uint256 amountInWithFee = amountIn * 997;

        uint256 expectedAmountOut = (amountInWithFee * reserve1Before) / ((reserve0Before * 1000) + amountInWithFee);

        vm.startPrank(alice);

        token0.transfer(address(pair), amountIn);

        pair.swap(0, expectedAmountOut, alice);

        vm.stopPrank();

        assertEq(pair.reserve0(), reserve0Before + amountIn);

        assertEq(pair.reserve1(), reserve1Before - expectedAmountOut);

        assertGt(pair.reserve0() * pair.reserve1(), reserve0Before * reserve1Before);
    }

    function testSwapRevertsForZeroOutput() public {
        _addInitialLiquidity();

        vm.expectRevert(AMMPair.InsufficientOutputAmount.selector);

        pair.swap(0, 0, alice);
    }

    function testSwapRevertsForInsufficientLiquidity() public {
        _addInitialLiquidity();

        vm.expectRevert(AMMPair.InsufficientLiquidity.selector);

        pair.swap(10 ether, 0, alice);
    }

    function testSwapRevertsForInsufficientInput() public {
        _addInitialLiquidity();

        vm.expectRevert(AMMPair.InsufficientInputAmount.selector);

        pair.swap(0, 1 ether, alice);
    }

    function testSwapRevertsForInvalidRecipient() public {
        _addInitialLiquidity();

        vm.expectRevert(AMMPair.InvalidRecipient.selector);

        pair.swap(0, 1 ether, address(0));
    }

    function testSwapRevertsWhenKInvariantBreaks() public {
        _addInitialLiquidity();

        uint256 amount0In = 1 ether;
        uint256 InvalidAmount1Out = 3 ether;

        token0.mint(alice, amount0In);

        vm.startPrank(alice);

        token0.transfer(address(pair), amount0In);

        vm.expectRevert(AMMPair.KInvariant.selector);

        pair.swap(0, InvalidAmount1Out, alice);

        vm.stopPrank();
    }

    function testFuzzSwapToken0ForToken1(uint256 amountIn) public {
        _addInitialLiquidity();

        amountIn = bound(amountIn, 1, 5 ether);

        token0.mint(alice, amountIn);

        uint256 reserve0Before = pair.reserve0();
        uint256 reserve1Before = pair.reserve1();

        uint256 amountInWithFee = amountIn * 997;

        uint256 expectedAmountOut = (amountInWithFee * reserve1Before) / ((reserve0Before * 1000) + amountInWithFee);

        vm.startPrank(alice);

        token0.transfer(address(pair), amountIn);

        pair.swap(0, expectedAmountOut, alice);

        vm.stopPrank();

        assertEq(pair.reserve0(), reserve0Before + amountIn);

        assertEq(pair.reserve1(), reserve1Before - expectedAmountOut);

        assertGe(pair.reserve0() * pair.reserve1(), reserve0Before * reserve1Before);
    }

    function testFuzzSwapToken1ForToken0(uint256 amountIn) public {
        _addInitialLiquidity();

        amountIn = bound(amountIn, 1, 10 ether);

        token1.mint(alice, amountIn);

        uint256 reserve0Before = pair.reserve0();
        uint256 reserve1Before = pair.reserve1();

        uint256 amountInWithFee = amountIn * 997;

        uint256 expectedAmountOut = (amountInWithFee * reserve0Before) / ((reserve1Before * 1000) + amountInWithFee);

        vm.assume(expectedAmountOut > 0);

        vm.startPrank(alice);

        token1.transfer(address(pair), amountIn);

        pair.swap(expectedAmountOut, 0, alice);

        vm.stopPrank();

        assertEq(pair.reserve0(), reserve0Before - expectedAmountOut);

        assertEq(pair.reserve1(), reserve1Before + amountIn);

        assertGe(pair.reserve0() * pair.reserve1(), reserve0Before * reserve1Before);
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y == 0) {
            return 0;
        }
        if (y <= 3) {
            return 1;
        }

        z = y;

        uint256 x = (y / 2) + 1;

        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
    }

    function testSyncUpdatesReserves() public {
        _addInitialLiquidity();

        uint256 donation0 = 2 ether;
        uint256 donation1 = 3 ether;

        token0.mint(address(pair), donation0);
        token1.mint(address(pair), donation1);

        pair.sync();

        assertEq(pair.reserve0(), INITIAL_AMOUNT0 + donation0);

        assertEq(pair.reserve1(), INITIAL_AMOUNT1 + donation1);
    }

    function testSyncDoesNotTransferTokens() public {
        _addInitialLiquidity();

        uint256 balance0Before = token0.balanceOf(address(pair));
        uint256 balance1Before = token1.balanceOf(address(pair));

        pair.sync();

        assertEq(token0.balanceOf(address(pair)), balance0Before);

        assertEq(token1.balanceOf(address(pair)), balance1Before);
    }

    function testSkimTransfersExceesTokens() public {
        _addInitialLiquidity();

        uint256 donation0 = 2 ether;
        uint256 donation1 = 3 ether;

        token0.mint(address(pair), donation0);
        token1.mint(address(pair), donation1);

        uint256 aliceBalance0Before = token0.balanceOf(alice);
        uint256 aliceBalance1Before = token1.balanceOf(alice);

        vm.prank(bob);
        pair.skim(alice);

        assertEq(token0.balanceOf(alice), aliceBalance0Before + donation0);

        assertEq(token1.balanceOf(alice), aliceBalance1Before + donation1);

        assertEq(pair.reserve0(), INITIAL_AMOUNT0);
        assertEq(pair.reserve1(), INITIAL_AMOUNT1);
    }

    function testSkimDoesNotChangeReserves() public {
        _addInitialLiquidity();

        token0.mint(address(pair), 2 ether);
        token1.mint(address(pair), 3 ether);

        uint256 reserve0Before = pair.reserve0();
        uint256 reserve1Before = pair.reserve1();

        pair.skim(bob);

        assertEq(pair.reserve0(), reserve0Before);
        assertEq(pair.reserve1(), reserve1Before);

        assertEq(token0.balanceOf(address(pair)), reserve0Before);
        assertEq(token1.balanceOf(address(pair)), reserve1Before);
    }

    function testLibraryQuote() public {
        uint256 amountB = libraryHarness.quote(1 ether, 10 ether, 20 ether);

        assertEq(amountB, 2 ether);
    }

    function testLibraryGetAmount() public {
        uint256 amountOut = libraryHarness.getAmountOut(1 ether, 10 ether, 20 ether);

        assertGt(amountOut, 0);
        assertLt(amountOut, 2 ether);
    }

    function testLibraryGetAmountIn() public {
        uint256 desiredOutput = 1 ether;

        uint256 amountIn = libraryHarness.getAmountIn(desiredOutput, 10 ether, 20 ether);

        uint256 actualOutput = libraryHarness.getAmountOut(amountIn, 10 ether, 20 ether);

        assertGe(actualOutput, desiredOutput);

        if (amountIn > 0) {
            uint256 previousOutput = libraryHarness.getAmountOut(amountIn - 1, 10 ether, 20 ether);

            assertLt(previousOutput, desiredOutput);
        }
    }

    function testLibraryGetReserves() public {
        _addInitialLiquidity();

        (uint256 reserveA, uint256 reserveB) =
            libraryHarness.getReserves(address(pair), address(token1), address(token0));

        assertEq(reserveA, INITIAL_AMOUNT1);
        assertEq(reserveB, INITIAL_AMOUNT0);
    }

    function testRevertWhenReserveExceedsUint112() public {
        uint256 excessiveAmount = uint256(type(uint112).max) + 1;

        token0.mint(address(pair), excessiveAmount);

        vm.expectRevert(AMMPair.ReserveOverflow.selector);

        pair.sync();
    }

    function testMaximumReserveIsAccepted() public {
        uint256 maxReserve = type(uint112).max;

        token0.mint(address(pair), maxReserve);
        token1.mint(address(pair), maxReserve);

        pair.sync();

        assertEq(pair.reserve0(), maxReserve);
        assertEq(pair.reserve1(), maxReserve);
    }

    function testSwapRevertsWhenBalanceExceedsMaxReserve() public {
        _addInitialLiquidity();

        uint256 reserve0Before = pair.reserve0();
        uint256 reserve1Before = pair.reserve1();

        uint256 excessiveAmount = pair.MAX_RESERVE() - reserve0Before + 1;

        token0.mint(address(pair), excessiveAmount);

        vm.expectRevert(AMMPair.ReserveOverflow.selector);

        pair.swap(0, 1 ether, alice);

        assertEq(pair.reserve0(), reserve0Before);
        assertEq(pair.reserve1(), reserve1Before);
    }

    function testAddLiquidityRevertsWhenBalanceExceedsMaxReserve() public {
        _addInitialLiquidity();

        uint256 reserve0Before = pair.reserve0();
        uint256 reserve1Before = pair.reserve1();

        uint256 excessiveAmount = pair.MAX_RESERVE() - reserve0Before + 1;

        token0.mint(address(pair), excessiveAmount);

        vm.startPrank(bob);

        token0.approve(address(pair), 1 ether);
        token1.approve(address(pair), 2 ether);

        vm.expectRevert(AMMPair.ReserveOverflow.selector);

        pair.addLiquidity(1 ether, 2 ether, 1 ether, 2 ether, bob);

        vm.stopPrank();

        assertEq(pair.reserve0(), reserve0Before);
        assertEq(pair.reserve1(), reserve1Before);
    }

    function testOptimalLiquidityCalculationHandlesLargeValues() public {
        AMMPairLiquidityHarness testPair =
            new AMMPairLiquidityHarness(address(token0), address(token1), address(emergencyControl));

        uint256 reserve = uint256(1) << 100;

        token0.mint(address(testPair), reserve);
        token1.mint(address(testPair), reserve);

        testPair.sync();

        uint256 desiredAmount = uint256(1) << 200;

        (uint256 amount0, uint256 amount1) = testPair.calculateLiquidityAmounts(desiredAmount, desiredAmount);

        assertEq(amount0, desiredAmount);
        assertEq(amount1, desiredAmount);
    }

    function testRemoveLiquidityAtMaximumReserveBoundary() public {
        uint256 maxReserve = pair.MAX_RESERVE();

        token0.mint(alice, maxReserve);
        token1.mint(alice, maxReserve);

        vm.startPrank(alice);

        token0.approve(address(pair), maxReserve);
        token1.approve(address(pair), maxReserve);

        pair.addLiquidity(maxReserve, maxReserve, maxReserve, maxReserve, alice);

        uint256 liquidity = lpToken.balanceOf(alice) / 2;

        uint256 totalSupplyBefore = lpToken.totalSupply();

        uint256 expectedAmount0 = (liquidity * pair.reserve0()) / totalSupplyBefore;

        uint256 expectedAmount1 = (liquidity * pair.reserve1()) / totalSupplyBefore;

        (uint256 amount0, uint256 amount1) = pair.removeLiquidity(liquidity, expectedAmount0, expectedAmount1, alice);

        vm.stopPrank();

        assertEq(amount0, expectedAmount0);
        assertEq(amount1, expectedAmount1);

        assertEq(pair.reserve0(), maxReserve - amount0);
        assertEq(pair.reserve1(), maxReserve - amount1);
    }

    function testProtocolPauseBlocksAddLiquidity() public {
        emergencyControl.pauseProtocol();

        vm.expectRevert(abi.encodeWithSelector(AMMPair.OperationPaused.selector, pair.ADD_LIQUIDITY_OPERATION()));

        pair.addLiquidity(1 ether, 2 ether, 1 ether, 2 ether, alice);
    }

    function testProtocolPauseBlocksSwap() public {
        _addInitialLiquidity();

        uint256 amountIn = 1 ether;
        token0.mint(alice, amountIn);

        vm.prank(alice);
        token0.transfer(address(pair), amountIn);

        emergencyControl.pauseProtocol();

        vm.expectRevert(abi.encodeWithSelector(AMMPair.OperationPaused.selector, pair.SWAP_OPERATION()));

        pair.swap(0, 1 ether, alice);
    }

    function testAddLiquidityPauseDoesNotBlockSwap() public {
        _addInitialLiquidity();

        emergencyControl.pauseOperation(pair.ADD_LIQUIDITY_OPERATION());

        vm.startPrank(bob);

        token0.approve(address(pair), 1 ether);
        token1.approve(address(pair), 2 ether);

        vm.expectRevert(abi.encodeWithSelector(AMMPair.OperationPaused.selector, pair.ADD_LIQUIDITY_OPERATION()));

        pair.addLiquidity(1 ether, 2 ether, 1 ether, 2 ether, bob);

        vm.stopPrank();

        // Swap should remain operational.
        uint256 amountIn = 1 ether;
        token0.mint(alice, amountIn);

        uint256 reserve0 = pair.reserve0();
        uint256 reserve1 = pair.reserve1();

        uint256 amountInWithFee = amountIn * 997;

        uint256 amountOut = (amountInWithFee * reserve1) / (reserve0 * 1000 + amountInWithFee);

        vm.startPrank(alice);

        token0.transfer(address(pair), amountIn);
        pair.swap(0, amountOut, alice);

        vm.stopPrank();

        assertEq(pair.reserve0(), reserve0 + amountIn);
        assertEq(pair.reserve1(), reserve1 - amountOut);
    }

    function testSwapPauseBlocksNormalSwap() public {
        _addInitialLiquidity();

        emergencyControl.pauseOperation(pair.SWAP_OPERATION());

        vm.expectRevert(abi.encodeWithSelector(AMMPair.OperationPaused.selector, pair.SWAP_OPERATION()));

        pair.swap(0, 1 ether, alice);
    }

    function testSwapPauseBlocksFlashSwap() public {
        _addInitialLiquidity();

        emergencyControl.pauseOperation(pair.SWAP_OPERATION());

        vm.expectRevert(abi.encodeWithSelector(AMMPair.OperationPaused.selector, pair.SWAP_OPERATION()));

        pair.swap(0, 1 ether, alice, hex"01");
    }

    function testRemoveLiquidityAllowedDuringProtocolPause() public {
        _addInitialLiquidity();

        uint256 liquidity = lpToken.balanceOf(alice) / 2;

        emergencyControl.pauseProtocol();

        vm.prank(alice);

        (uint256 amount0, uint256 amount1) = pair.removeLiquidity(liquidity, 0, 0, alice);

        assertGt(amount0, 0);
        assertGt(amount1, 0);

        assertEq(lpToken.balanceOf(alice), liquidity);
    }

    function testSyncAndSkimAllowedDuringProtocolPause() public {
        _addInitialLiquidity();

        emergencyControl.pauseProtocol();

        token0.mint(address(pair), 2 ether);
        token1.mint(address(pair), 3 ether);

        uint256 aliceBalance0Before = token0.balanceOf(alice);
        uint256 aliceBalance1Before = token1.balanceOf(alice);

        pair.skim(alice);

        assertEq(token0.balanceOf(alice), aliceBalance0Before + 2 ether);

        assertEq(token1.balanceOf(alice), aliceBalance1Before + 3 ether);

        token0.mint(address(pair), 4 ether);
        token1.mint(address(pair), 5 ether);

        pair.sync();

        assertEq(pair.reserve0(), INITIAL_AMOUNT0 + 4 ether);
        assertEq(pair.reserve1(), INITIAL_AMOUNT1 + 5 ether);
    }

    function testUnpauseRestoresAddLiquidity() public {
        emergencyControl.pauseOperation(pair.ADD_LIQUIDITY_OPERATION());

        emergencyControl.unpauseOperation(pair.ADD_LIQUIDITY_OPERATION());

        vm.startPrank(alice);

        token0.approve(address(pair), INITIAL_AMOUNT0);
        token1.approve(address(pair), INITIAL_AMOUNT1);

        (,, uint256 liquidity) =
            pair.addLiquidity(INITIAL_AMOUNT0, INITIAL_AMOUNT1, INITIAL_AMOUNT0, INITIAL_AMOUNT1, alice);

        vm.stopPrank();

        assertGt(liquidity, 0);
    }
}
