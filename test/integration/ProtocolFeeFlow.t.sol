pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {EmergencyControl} from "../../src/security/EmergencyControl.sol";
import {TokenPolicy} from "../../src/security/TokenPolicy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {AMMPair} from "../../src/core/AMMPair.sol";
import {AMMRouter} from "../../src/periphery/AMMRouter.sol";
import {LPToken} from "../../src/token/LPToken.sol";

contract ProtocolFeeToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ProtocolFeeFlowTest is Test {
    AMMFactory internal factory;
    AMMRouter internal router;
    EmergencyControl internal emergencyControl;
    TokenPolicy internal tokenPolicy;

    ProtocolFeeToken internal tokenA;
    ProtocolFeeToken internal tokenB;

    AMMPair internal pair;
    LPToken internal lpToken;

    address internal alice = makeAddr("alice");
    address internal trader = makeAddr("trader");
    address internal feeRecipient = makeAddr("feeRecipient");

    uint256 internal constant INITIAL_LIQUIDITY = 1_000 ether;
    uint256 internal constant SWAP_AMOUNT = 100 ether;
    uint256 internal constant ADDITIONAL_LIQUIDITY = 100 ether;

    function setUp() public {
        emergencyControl = new EmergencyControl(address(this));
        tokenPolicy = new TokenPolicy(address(this));
        factory = new AMMFactory(
            address(emergencyControl),
            address(tokenPolicy)
        );
        router = new AMMRouter(address(factory));

        tokenA = new ProtocolFeeToken("Token A", "TKA");
        tokenB = new ProtocolFeeToken("Token B", "TKB");
        tokenPolicy.approveToken(address(tokenA));
        tokenPolicy.approveToken(address(tokenB));
        tokenA.mint(alice, 5_000 ether);
        tokenB.mint(alice, 5_000 ether);

        tokenA.mint(trader, 1_000 ether);

        factory.setFeeTo(feeRecipient);

        vm.startPrank(alice);

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        vm.stopPrank();

        vm.prank(trader);
        tokenA.approve(address(router), type(uint256).max);

        // Create initial liquidity.
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

        vm.stopPrank();

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));

        pair = AMMPair(pairAddress);
        lpToken = pair.lpToken();
    }

    function testProtocolFeeMintedAfterLiquidityOperation() public {
        uint256 initialKLast = pair.kLast();

        assertGt(initialKLast, 0);
        assertEq(lpToken.balanceOf(feeRecipient), 0);

        address[] memory path = new address[](2);

        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = router.getAmountsOut(SWAP_AMOUNT, path);

        vm.prank(trader);

        router.swapExactTokensForTokens(SWAP_AMOUNT, amounts[1], path, trader, block.timestamp + 1 hours);

        assertEq(lpToken.balanceOf(feeRecipient), 0);

        uint256 reserve0Before = pair.reserve0();
        uint256 reserve1Before = pair.reserve1();

        uint256 rootK = Math.sqrt(reserve0Before * reserve1Before);
        uint256 rootKLast = Math.sqrt(initialKLast);

        assertGt(rootK, rootKLast);

        uint256 supplyBefore = lpToken.totalSupply();

        uint256 expectedFeeLiquidity = Math.mulDiv(supplyBefore, rootK - rootKLast, (rootK * 5) + rootKLast);

        assertGt(expectedFeeLiquidity, 0);

        vm.prank(alice);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            ADDITIONAL_LIQUIDITY,
            ADDITIONAL_LIQUIDITY,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );

        assertEq(lpToken.balanceOf(feeRecipient), expectedFeeLiquidity);

        assertGt(lpToken.totalSupply(), supplyBefore);

        assertEq(pair.kLast(), pair.reserve0() * pair.reserve1());
    }

    function testDisablingProtocolFeeClearsKLast() public {
        assertGt(pair.kLast(), 0);

        factory.setFeeTo(address(0));

        vm.prank(alice);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            ADDITIONAL_LIQUIDITY,
            ADDITIONAL_LIQUIDITY,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );

        assertEq(pair.kLast(), 0);

        assertEq(lpToken.balanceOf(feeRecipient), 0);
    }
}
