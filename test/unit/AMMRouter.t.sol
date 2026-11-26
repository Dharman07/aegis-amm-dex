pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {AMMRouter} from "../../src/periphery/AMMRouter.sol";
import {AMMPair} from "../../src/core/AMMPair.sol";
import {EmergencyControl} from "../../src/security/EmergencyControl.sol";
import {TokenPolicy} from "../../src/security/TokenPolicy.sol";

contract MockRouterToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AMMRouterTest is Test {
    AMMFactory public factory;
    AMMRouter public router;
    EmergencyControl internal emergencyControl;
    TokenPolicy internal tokenPolicy;
    MockRouterToken public tokenA;
    MockRouterToken public tokenB;
    MockRouterToken public tokenC;

    address public user = address(0x1234);
    address public recipient = address(0x5678);

    uint256 constant INITIAL_AMOUNT = 10_000 ether;
    uint256 constant LIQUIDITY_AMOUNT = 1_000 ether;

    function setUp() public {
        emergencyControl = new EmergencyControl(address(this));
        tokenPolicy = new TokenPolicy(address(this));
        factory = new AMMFactory(
            address(emergencyControl),
            address(tokenPolicy)
        );
        router = new AMMRouter(address(factory));

        tokenA = new MockRouterToken("Token A", "TKA");
        tokenB = new MockRouterToken("Token B", "TKB");
        tokenC = new MockRouterToken("Token C", "TKC");

        tokenPolicy.approveToken(address(tokenA));
        tokenPolicy.approveToken(address(tokenB));
        tokenPolicy.approveToken(address(tokenC));

        tokenA.mint(user, INITIAL_AMOUNT);
        tokenB.mint(user, INITIAL_AMOUNT);
        tokenC.mint(user, INITIAL_AMOUNT);

        vm.startPrank(user);

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenC.approve(address(router), type(uint256).max);

        vm.stopPrank();
    }

    function _addLiquidity(address token0_, address token1_, uint256 amount0_, uint256 amount1_) internal {
        vm.startPrank(user);

        router.addLiquidity(token0_, token1_, amount0_, amount1_, 0, 0, user, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function testAddLiquidity() public {
        vm.startPrank(user);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            address(tokenA), address(tokenB), LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, 0, 0, user, block.timestamp + 1 hours
        );

        vm.stopPrank();

        assertEq(amountA, LIQUIDITY_AMOUNT);
        assertEq(amountB, LIQUIDITY_AMOUNT);
        assertGt(liquidity, 0);

        address pair = factory.getPair(address(tokenA), address(tokenB));

        assertTrue(pair != address(0));
        assertGt(ERC20(address(AMMPair(pair).lpToken())).balanceOf(user), 0);
    }

    function testRemoveLiquidity() public {
        _addLiquidity(address(tokenA), address(tokenB), LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        address pair = factory.getPair(address(tokenA), address(tokenB));

        uint256 liquidity = ERC20(address(AMMPair(pair).lpToken())).balanceOf(user);

        uint256 balanceABefore = tokenA.balanceOf(user);
        uint256 balanceBBefore = tokenB.balanceOf(user);

        vm.startPrank(user);

        ERC20(address(AMMPair(pair).lpToken())).approve(address(router), liquidity);

        (uint256 amountA, uint256 amountB) =
            router.removeLiquidity(address(tokenA), address(tokenB), liquidity, 0, 0, user, block.timestamp + 1 hours);

        vm.stopPrank();

        assertGt(amountA, 0);
        assertGt(amountB, 0);

        assertEq(tokenA.balanceOf(user), balanceABefore + amountA);

        assertEq(tokenB.balanceOf(user), balanceBBefore + amountB);
    }

    function testSwapExactTokensForTokens() public {
        _addLiquidity(address(tokenA), address(tokenB), LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 amountIn = 10 ether;

        uint256 balanceBefore = tokenB.balanceOf(recipient);

        vm.prank(user);

        uint256[] memory amounts =
            router.swapExactTokensForTokens(amountIn, 0, path, recipient, block.timestamp + 1 hours);

        uint256 balanceAfter = tokenB.balanceOf(recipient);

        assertEq(amounts[0], amountIn);
        assertGt(amounts[1], 0);
        assertEq(balanceAfter - balanceBefore, amounts[1]);
    }

    function testSwapTokensForExactTokens() public {
        _addLiquidity(address(tokenA), address(tokenB), LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 amountOut = 10 ether;
        uint256 amountInMax = 20 ether;

        uint256 balanceBefore = tokenB.balanceOf(recipient);

        vm.prank(user);

        uint256[] memory amounts =
            router.swapTokensForExactTokens(amountOut, amountInMax, path, recipient, block.timestamp + 1 hours);

        uint256 balanceAfter = tokenB.balanceOf(recipient);

        assertGt(amounts[0], 0);
        assertLe(amounts[0], amountInMax);
        assertEq(amounts[1], amountOut);
        assertEq(balanceAfter - balanceBefore, amountOut);
    }

    function testMultiHopSwap() public {
        _addLiquidity(address(tokenA), address(tokenB), LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        _addLiquidity(address(tokenB), address(tokenC), LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256 amountIn = 10 ether;

        uint256 balanceBefore = tokenC.balanceOf(recipient);

        vm.prank(user);

        uint256[] memory amounts =
            router.swapExactTokensForTokens(amountIn, 0, path, recipient, block.timestamp + 1 hours);

        uint256 balanceAfter = tokenC.balanceOf(recipient);

        assertEq(amounts.length, 3);
        assertEq(amounts[0], amountIn);
        assertGt(amounts[1], 0);
        assertGt(amounts[2], 0);

        assertEq(balanceAfter - balanceBefore, amounts[2]);
    }

    function testExpiredDeadlineReverts() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.warp(1000);

        vm.startPrank(user);

        vm.expectRevert();

        router.swapExactTokensForTokens(10 ether, 0, path, recipient, 999);

        vm.stopPrank();
    }

    function testRouterAddLiquidityBlockedDuringPause() public {
        _addLiquidity(address(tokenA), address(tokenB), LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        address pair = factory.getPair(address(tokenA), address(tokenB));

        bytes32 operation = AMMPair(pair).ADD_LIQUIDITY_OPERATION();

        emergencyControl.pauseOperation(operation);

        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(AMMPair.OperationPaused.selector, operation));

        router.addLiquidity(
            address(tokenA), address(tokenB), 100 ether, 100 ether, 0, 0, user, block.timestamp + 1 hours
        );

        vm.stopPrank();
    }

    function testRouterExactInputSwapBlockedDuringPause() public {
        _addLiquidity(address(tokenA), address(tokenB), LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        address pair = factory.getPair(address(tokenA), address(tokenB));

        bytes32 operation = AMMPair(pair).SWAP_OPERATION();

        emergencyControl.pauseOperation(operation);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(AMMPair.OperationPaused.selector, operation));

        router.swapExactTokensForTokens(10 ether, 0, path, recipient, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function testRouterExactOutputSwapBlockedDuringPause() public {
        _addLiquidity(address(tokenA), address(tokenB), LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        address pair = factory.getPair(address(tokenA), address(tokenB));

        bytes32 operation = AMMPair(pair).SWAP_OPERATION();

        emergencyControl.pauseOperation(operation);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(AMMPair.OperationPaused.selector, operation));

        router.swapTokensForExactTokens(10 ether, 20 ether, path, recipient, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function testRouterRemoveLiquidityAllowedDuringProtocolPause() public {
        _addLiquidity(address(tokenA), address(tokenB), LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

        address pair = factory.getPair(address(tokenA), address(tokenB));

        AMMPair ammPair = AMMPair(pair);

        uint256 liquidity = ammPair.lpToken().balanceOf(user);

        emergencyControl.pauseProtocol();

        vm.startPrank(user);

        ammPair.lpToken().approve(address(router), liquidity);

        (uint256 amountA, uint256 amountB) =
            router.removeLiquidity(address(tokenA), address(tokenB), liquidity, 0, 0, user, block.timestamp + 1 hours);

        vm.stopPrank();

        assertGt(amountA, 0);
        assertGt(amountB, 0);
        assertEq(ammPair.lpToken().balanceOf(user), 0);
    }
}
