pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EmergencyControl} from "../../src/security/EmergencyControl.sol";

import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {AMMRouter} from "../../src/periphery/AMMRouter.sol";
import {AMMPair} from "../../src/core/AMMPair.sol";
import {LPToken} from "../../src/token/LPToken.sol";

contract LiquidityFlowToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract LiquidityFlowTest is Test {
    AMMFactory internal factory;
    AMMRouter internal router;
    EmergencyControl internal emergencyControl;

    LiquidityFlowToken internal tokenA;
    LiquidityFlowToken internal tokenB;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant ALICE_DEPOSIT = 1_000 ether;
    uint256 internal constant BOB_DEPOSIT = 500 ether;

    function setUp() public {
        emergencyControl = new EmergencyControl(address(this));
        factory = new AMMFactory(address(emergencyControl));
        router = new AMMRouter(address(factory));

        tokenA = new LiquidityFlowToken("Token A", "TKA");
        tokenB = new LiquidityFlowToken("Token B", "TKB");

        tokenA.mint(alice, 5_000 ether);
        tokenB.mint(alice, 5_000 ether);

        tokenA.mint(bob, 5_000 ether);
        tokenB.mint(bob, 5_000 ether);

        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function testCompleteLiquidityLifeCycle() public {
        vm.prank(alice);

        (uint256 aliceAmountA, uint256 aliceAmountB, uint256 aliceLiquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            ALICE_DEPOSIT,
            ALICE_DEPOSIT,
            ALICE_DEPOSIT,
            ALICE_DEPOSIT,
            alice,
            block.timestamp + 1 hours
        );

        assertEq(aliceAmountA, ALICE_DEPOSIT);
        assertEq(aliceAmountB, ALICE_DEPOSIT);
        assertGt(aliceLiquidity, 0);

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));

        AMMPair pair = AMMPair(pairAddress);
        LPToken lpToken = pair.lpToken();

        assertEq(lpToken.balanceOf(alice), ALICE_DEPOSIT - pair.MINIMUM_LIQUIDITY());
        assertEq(lpToken.totalSupply(), aliceLiquidity + pair.MINIMUM_LIQUIDITY());

        assertEq(pair.reserve0(), ALICE_DEPOSIT);
        assertEq(pair.reserve1(), ALICE_DEPOSIT);

        uint256 supplyBeforeBob = lpToken.totalSupply();
        uint256 reserve0BeforeBob = pair.reserve0();

        uint256 expectedBobLiquidity = (BOB_DEPOSIT * supplyBeforeBob) / reserve0BeforeBob;

        vm.prank(bob);

        (uint256 bobAmountA, uint256 bobAmountB, uint256 bobLiquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            BOB_DEPOSIT,
            BOB_DEPOSIT,
            BOB_DEPOSIT,
            BOB_DEPOSIT,
            bob,
            block.timestamp + 1 hours
        );

        assertEq(bobAmountA, BOB_DEPOSIT);
        assertEq(bobAmountB, BOB_DEPOSIT);
        assertEq(bobLiquidity, expectedBobLiquidity);

        assertEq(lpToken.balanceOf(alice), aliceLiquidity);
        assertEq(lpToken.balanceOf(bob), bobLiquidity);

        assertEq(pair.reserve0(), ALICE_DEPOSIT + BOB_DEPOSIT);
        assertEq(pair.reserve1(), ALICE_DEPOSIT + BOB_DEPOSIT);

        uint256 liquidityToRemove = aliceLiquidity / 4;

        uint256 aliceTokenABefore = tokenA.balanceOf(alice);
        uint256 aliceTokenBBefore = tokenB.balanceOf(alice);

        uint256 supplyBeforeRemoval = lpToken.totalSupply();
        uint256 reserve0BeforeRemoval = pair.reserve0();
        uint256 reserve1BeforeRemoval = pair.reserve1();

        uint256 expectedAmount0 = (liquidityToRemove * reserve0BeforeRemoval) / supplyBeforeRemoval;

        uint256 expectedAmount1 = (liquidityToRemove * reserve1BeforeRemoval) / supplyBeforeRemoval;

        vm.startPrank(alice);

        lpToken.approve(address(router), liquidityToRemove);

        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA), address(tokenB), liquidityToRemove, 0, 0, alice, block.timestamp + 1 hours
        );

        vm.stopPrank();

        assertGt(amountA, 0);
        assertGt(amountB, 0);

        assertEq(tokenA.balanceOf(alice), aliceTokenABefore + amountA);

        assertEq(tokenB.balanceOf(alice), aliceTokenBBefore + amountB);

        assertEq(lpToken.balanceOf(alice), aliceLiquidity - liquidityToRemove);

        assertEq(lpToken.totalSupply(), supplyBeforeRemoval - liquidityToRemove);

        if (address(tokenA) == address(pair.token0())) {
            assertEq(pair.reserve0(), reserve0BeforeRemoval - expectedAmount0);
            assertEq(pair.reserve1(), reserve1BeforeRemoval - expectedAmount1);

            assertEq(amountA, expectedAmount0);
            assertEq(amountB, expectedAmount1);
        } else {
            assertEq(pair.reserve0(), reserve0BeforeRemoval - expectedAmount1);
            assertEq(pair.reserve1(), reserve1BeforeRemoval - expectedAmount0);

            assertEq(amountA, expectedAmount0);
            assertEq(amountB, expectedAmount1);
        }
    }
}
