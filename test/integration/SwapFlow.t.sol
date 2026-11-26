// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EmergencyControl} from "../../src/security/EmergencyControl.sol";
import {TokenPolicy} from "../../src/security/TokenPolicy.sol";
import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {AMMPair} from "../../src/core/AMMPair.sol";
import {AMMRouter} from "../../src/periphery/AMMRouter.sol";

contract SwapFlowToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract SwapFlowTest is Test {
    AMMFactory internal factory;
    AMMRouter internal router;
    EmergencyControl internal emergencyControl;
    TokenPolicy internal tokenPolicy;
    SwapFlowToken internal tokenA;
    SwapFlowToken internal tokenB;
    SwapFlowToken internal tokenC;

    address internal alice = makeAddr("alice");
    address internal trader = makeAddr("trader");

    uint256 internal constant INITIAL_LIQUIDITY = 1_000 ether;
    uint256 internal constant SWAP_AMOUNT = 10 ether;

    function setUp() public {
        emergencyControl = new EmergencyControl(address(this));
        tokenPolicy = new TokenPolicy(address(this));
        factory = new AMMFactory(
            address(emergencyControl),
            address(tokenPolicy)
        );
        router = new AMMRouter(address(factory));

        tokenA = new SwapFlowToken("Token A", "TKA");
        tokenB = new SwapFlowToken("Token B", "TKB");
        tokenC = new SwapFlowToken("Token C", "TKC");

        tokenPolicy.approveToken(address(tokenA));
        tokenPolicy.approveToken(address(tokenB));
        tokenPolicy.approveToken(address(tokenC));

        tokenA.mint(alice, 10_000 ether);
        tokenB.mint(alice, 10_000 ether);
        tokenC.mint(alice, 10_000 ether);

        tokenA.mint(trader, 1_000 ether);
        tokenB.mint(trader, 1_000 ether);

        // Alice approves Router.
        vm.startPrank(alice);

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenC.approve(address(router), type(uint256).max);

        vm.stopPrank();

        // Trader approves Router.
        vm.startPrank(trader);

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        vm.stopPrank();

        // Create A-B liquidity pool.
        vm.startPrank(alice);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            alice,
            block.timestamp + 1 hours
        );

        // Create B-C liquidity pool.
        router.addLiquidity(
            address(tokenB),
            address(tokenC),
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            alice,
            block.timestamp + 1 hours
        );

        vm.stopPrank();
    }

    function testExactInputSingleHopSwap() public {
        address[] memory path = new address[](2);

        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory expectedAmounts = router.getAmountsOut(SWAP_AMOUNT, path);

        uint256 inputBalanceBefore = tokenA.balanceOf(trader);
        uint256 outputBalanceBefore = tokenB.balanceOf(trader);

        vm.prank(trader);

        uint256[] memory amounts =
            router.swapExactTokensForTokens(SWAP_AMOUNT, expectedAmounts[1], path, trader, block.timestamp + 1 hours);

        assertEq(amounts[0], SWAP_AMOUNT);
        assertEq(amounts[1], expectedAmounts[1]);

        assertEq(tokenA.balanceOf(trader), inputBalanceBefore - SWAP_AMOUNT);

        assertEq(tokenB.balanceOf(trader), outputBalanceBefore + expectedAmounts[1]);

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));

        _assertPairBalancesSynced(AMMPair(pairAddress));
    }

    function testExactOutputSingleHopSwap() public {
        address[] memory path = new address[](2);

        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 exactOutput = 20 ether;

        uint256[] memory expectedAmounts = router.getAmountsIn(exactOutput, path);

        uint256 inputBalanceBefore = tokenA.balanceOf(trader);
        uint256 outputBalanceBefore = tokenB.balanceOf(trader);

        vm.prank(trader);

        uint256[] memory amounts =
            router.swapTokensForExactTokens(exactOutput, expectedAmounts[0], path, trader, block.timestamp + 1 hours);

        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], exactOutput);

        assertEq(tokenA.balanceOf(trader), inputBalanceBefore - expectedAmounts[0]);

        assertEq(tokenB.balanceOf(trader), outputBalanceBefore + exactOutput);

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));

        _assertPairBalancesSynced(AMMPair(pairAddress));
    }

    function testMultiHopSwap() public {
        address[] memory path = new address[](3);

        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256[] memory expectedAmounts = router.getAmountsOut(SWAP_AMOUNT, path);

        uint256 inputBalanceBefore = tokenA.balanceOf(trader);
        uint256 outputBalanceBefore = tokenC.balanceOf(trader);

        vm.prank(trader);

        uint256[] memory amounts =
            router.swapExactTokensForTokens(SWAP_AMOUNT, expectedAmounts[2], path, trader, block.timestamp + 1 hours);

        assertEq(amounts.length, 3);
        assertEq(amounts[0], SWAP_AMOUNT);
        assertEq(amounts[1], expectedAmounts[1]);
        assertEq(amounts[2], expectedAmounts[2]);

        assertEq(tokenA.balanceOf(trader), inputBalanceBefore - SWAP_AMOUNT);

        assertEq(tokenC.balanceOf(trader), outputBalanceBefore + expectedAmounts[2]);

        address pairAB = factory.getPair(address(tokenA), address(tokenB));

        address pairBC = factory.getPair(address(tokenB), address(tokenC));

        _assertPairBalancesSynced(AMMPair(pairAB));
        _assertPairBalancesSynced(AMMPair(pairBC));
    }

    function _assertPairBalancesSynced(AMMPair pair) internal view {
        uint256 actualBalance0 = IERC20(address(pair.token0())).balanceOf(address(pair));

        uint256 actualBalance1 = IERC20(address(pair.token1())).balanceOf(address(pair));

        assertEq(pair.reserve0(), actualBalance0);
        assertEq(pair.reserve1(), actualBalance1);
    }
}
