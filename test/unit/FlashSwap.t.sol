pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EmergencyControl} from "../../src/security/EmergencyControl.sol";

import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {AMMPair} from "../../src/core/AMMPair.sol";

import {FlashSwap} from "../../src/flash/FlashSwap.sol";
import {IFlashSwapCallback} from "../../src/flash/interfaces/IFlashSwapCallback.sol";

import {IAMMPair} from "../../src/interfaces/IAMMPair.sol";

interface IFlashSwapStrategy {
    function execute(
        address pair,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

contract FlashSwapMockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockFlashSwapStrategy is IFlashSwapStrategy {
    uint256 public returnAmount0;
    uint256 public returnAmount1;

    uint256 public receivedAmount0;
    uint256 public receivedAmount1;

    function setReturnAmounts(uint256 amount0, uint256 amount1) external {
        returnAmount0 = amount0;
        returnAmount1 = amount1;
    }

    function execute(address, address token0, address token1, uint256 amount0, uint256 amount1, bytes calldata)
        external
        override
    {
        receivedAmount0 = amount0;
        receivedAmount1 = amount1;

        if (returnAmount0 > 0) {
            require(IERC20(token0).transfer(msg.sender, returnAmount0), "TOKEN0_TRANSFER_FAILED");
        }

        if (returnAmount1 > 0) {
            require(IERC20(token1).transfer(msg.sender, returnAmount1), "TOKEN1_TRANSFER_FAILED");
        }
    }
}

contract FlashSwapTest is Test {
    FlashSwapMockERC20 internal token0;
    FlashSwapMockERC20 internal token1;
    EmergencyControl internal emergencyControl;

    AMMFactory internal factory;
    AMMPair internal pair;

    FlashSwap internal flashSwap;
    MockFlashSwapStrategy internal strategy;

    uint256 internal constant INITIAL_LIQUIDITY = 100 ether;

    uint256 internal constant BORROW_AMOUNT = 1 ether;

    uint256 internal constant REPAYMENT_AMOUNT = 2 ether;

    uint256 internal constant PROFIT_AMOUNT = 0.1 ether;

    function setUp() public {
        token0 = new FlashSwapMockERC20("Token 0", "TK0");

        token1 = new FlashSwapMockERC20("Token 1", "TK1");

        emergencyControl = new EmergencyControl(address(this));
        factory = new AMMFactory(address(emergencyControl));

        address pairAddress = factory.createPair(address(token0), address(token1));

        pair = AMMPair(pairAddress);

        token0 = FlashSwapMockERC20(address(pair.token0()));
        token1 = FlashSwapMockERC20(address(pair.token1()));

        flashSwap = new FlashSwap(address(factory));

        strategy = new MockFlashSwapStrategy();

        token0.mint(address(this), 1000 ether);
        token1.mint(address(this), 1000 ether);
        token0.approve(address(pair), INITIAL_LIQUIDITY);
        token1.approve(address(pair), INITIAL_LIQUIDITY);

        pair.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, address(this));
    }

    function testRevertWhenFactoryIsZero() public {
        vm.expectRevert(FlashSwap.ZeroAddress.selector);

        new FlashSwap(address(0));
    }

    function testRevertWhenFactoryHasNoCode() public {
        vm.expectRevert(FlashSwap.InvalidFactory.selector);

        new FlashSwap(address(0xBEEF));
    }

    function testRevertWhenPairIsInvalid() public {
        vm.expectRevert(FlashSwap.InvalidPair.selector);

        flashSwap.execute(
            address(0xBEEF),
            BORROW_AMOUNT,
            0,
            0,
            REPAYMENT_AMOUNT,
            address(strategy),
            bytes(""),
            block.timestamp + 1 hours
        );
    }

    function testRevertWhenPairIsNotRegisteredInFactory() public {
        AMMPair unregisteredPair = new AMMPair(address(token0), address(token1), address(emergencyControl));

        vm.expectRevert(FlashSwap.InvalidPair.selector);

        flashSwap.execute(
            address(unregisteredPair),
            BORROW_AMOUNT,
            0,
            0,
            REPAYMENT_AMOUNT,
            address(strategy),
            bytes(""),
            block.timestamp + 1 hours
        );
    }

    function testRevertWhenStrategyIsInvalid() public {
        vm.expectRevert(FlashSwap.InvalidStrategy.selector);

        flashSwap.execute(
            address(pair), BORROW_AMOUNT, 0, 0, REPAYMENT_AMOUNT, address(0xBEEF), bytes(""), block.timestamp + 1 hours
        );
    }

    function testRevertWhenOutputAmountIsZero() public {
        vm.expectRevert(FlashSwap.InvalidOutputAmount.selector);

        flashSwap.execute(
            address(pair), 0, 0, 0, REPAYMENT_AMOUNT, address(strategy), bytes(""), block.timestamp + 1 hours
        );
    }

    function testRevertWhenRepaymentIsZero() public {
        vm.expectRevert(FlashSwap.InvalidRepayment.selector);

        flashSwap.execute(
            address(pair), BORROW_AMOUNT, 0, 0, 0, address(strategy), bytes(""), block.timestamp + 1 hours
        );
    }

    function testRevertWhenDeadlineExpired() public {
        vm.warp(1000);

        vm.expectRevert(FlashSwap.Expired.selector);

        flashSwap.execute(address(pair), BORROW_AMOUNT, 0, 0, REPAYMENT_AMOUNT, address(strategy), bytes(""), 999);
    }

    function testUnauthorizedCallbackReverts() public {
        vm.expectRevert(FlashSwap.InvalidCallback.selector);

        flashSwap.aegisCall(address(this), BORROW_AMOUNT, 0, bytes(""));
    }

    function testSuccessfulFlashSwap() public {
        strategy.setReturnAmounts(PROFIT_AMOUNT, REPAYMENT_AMOUNT);

        token0.mint(address(strategy), PROFIT_AMOUNT);

        token1.mint(address(strategy), REPAYMENT_AMOUNT);

        uint256 userBalanceBefore = token0.balanceOf(address(this));

        (uint256 profit0, uint256 profit1) = flashSwap.execute(
            address(pair),
            BORROW_AMOUNT,
            0,
            0,
            REPAYMENT_AMOUNT,
            address(strategy),
            bytes("strategy-data"),
            block.timestamp + 1 hours
        );

        assertEq(profit0, PROFIT_AMOUNT);

        assertEq(profit1, 0);

        assertEq(token0.balanceOf(address(this)), userBalanceBefore + PROFIT_AMOUNT);

        assertEq(strategy.receivedAmount0(), BORROW_AMOUNT);

        assertEq(strategy.receivedAmount1(), 0);

        assertEq(token1.balanceOf(address(pair)), INITIAL_LIQUIDITY + REPAYMENT_AMOUNT);
    }

    function testInsufficientRepaymentReverts() public {
        strategy.setReturnAmounts(0, 1 ether);

        token1.mint(address(strategy), 1 ether);

        vm.expectRevert(FlashSwap.InsufficientRepayment.selector);

        flashSwap.execute(
            address(pair),
            BORROW_AMOUNT,
            0,
            0,
            REPAYMENT_AMOUNT,
            address(strategy),
            bytes(""),
            block.timestamp + 1 hours
        );
    }

    function testPairKInvariantIsEnforced() public {
        uint256 insufficientRepayment = 0.5 ether;

        strategy.setReturnAmounts(0, insufficientRepayment);

        token1.mint(address(strategy), insufficientRepayment);

        vm.expectRevert(AMMPair.KInvariant.selector);

        flashSwap.execute(
            address(pair),
            BORROW_AMOUNT,
            0,
            0,
            insufficientRepayment,
            address(strategy),
            bytes(""),
            block.timestamp + 1 hours
        );
    }

    function testExistingExecutorBalancesArePreserved() public {
        uint256 existingToken0 = 5 ether;
        uint256 existingToken1 = 7 ether;

        token0.mint(address(flashSwap), existingToken0);

        token1.mint(address(flashSwap), existingToken1);

        strategy.setReturnAmounts(0, REPAYMENT_AMOUNT);

        token1.mint(address(strategy), REPAYMENT_AMOUNT);

        flashSwap.execute(
            address(pair),
            BORROW_AMOUNT,
            0,
            0,
            REPAYMENT_AMOUNT,
            address(strategy),
            bytes(""),
            block.timestamp + 1 hours
        );

        assertEq(token0.balanceOf(address(flashSwap)), existingToken0);

        assertEq(token1.balanceOf(address(flashSwap)), existingToken1);
    }

    // --------------------------------------------------
    // Callback Replay Attempt
    // --------------------------------------------------

    function testStrategyCannotReplayCallback() public {
        strategy.setReturnAmounts(0, REPAYMENT_AMOUNT);

        token1.mint(address(strategy), REPAYMENT_AMOUNT);

        // The strategy cannot impersonate the pair.
        // Direct callback invocation is unauthorized.

        flashSwap.execute(
            address(pair),
            BORROW_AMOUNT,
            0,
            0,
            REPAYMENT_AMOUNT,
            address(strategy),
            bytes(""),
            block.timestamp + 1 hours
        );

        vm.expectRevert(FlashSwap.InvalidCallback.selector);

        flashSwap.aegisCall(address(this), BORROW_AMOUNT, 0, bytes(""));
    }
}
