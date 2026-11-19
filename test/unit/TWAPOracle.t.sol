// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EmergencyControl} from "../../src/security/EmergencyControl.sol";

import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {AMMPair} from "../../src/core/AMMPair.sol";
import {AMMOracle} from "../../src/oracle/AMMOracle.sol";
import {TWAPOracle} from "../../src/oracle/TWAPOracle.sol";

contract TWAPTestToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TWAPOracleTest is Test {
    AMMFactory internal factory;
    AMMOracle internal ammOracle;
    TWAPOracle internal twapOracle;
    EmergencyControl internal emergencyControl;

    TWAPTestToken internal tokenA;
    TWAPTestToken internal tokenB;
    TWAPTestToken internal tokenC;

    AMMPair internal pair;

    uint32 internal constant MINIMUM_PERIOD = 1800;

    uint256 internal constant INITIAL_AMOUNT = 1_000 ether;
    uint256 internal constant Q112 = 2 ** 112;

    function setUp() public {
        emergencyControl = new EmergencyControl(address(this));
        factory = new AMMFactory(address(emergencyControl));

        ammOracle = new AMMOracle(address(this), address(this));

        twapOracle = new TWAPOracle(address(ammOracle), MINIMUM_PERIOD);

        tokenA = new TWAPTestToken("Token A", "TKA");
        tokenB = new TWAPTestToken("Token B", "TKB");
        tokenC = new TWAPTestToken("Token C", "TKC");

        tokenA.mint(address(this), 5_000 ether);
        tokenB.mint(address(this), 5_000 ether);

        address pairAddress = factory.createPair(address(tokenA), address(tokenB));

        pair = AMMPair(pairAddress);

        tokenA.approve(address(pair), type(uint256).max);
        tokenB.approve(address(pair), type(uint256).max);

        pair.addLiquidity(INITIAL_AMOUNT, INITIAL_AMOUNT, INITIAL_AMOUNT, INITIAL_AMOUNT, address(this));
    }

    function testConstructorInitializesConfiguration() public view {
        assertEq(address(twapOracle.ammOracle()), address(ammOracle));

        assertEq(twapOracle.minimumPeriod(), MINIMUM_PERIOD);
    }

    function testConstructorRevertsForZeroOracle() public {
        vm.expectRevert(TWAPOracle.ZeroAddress.selector);

        new TWAPOracle(address(0), MINIMUM_PERIOD);
    }

    function testConstructorRevertsForInvalidOracle() public {
        vm.expectRevert(TWAPOracle.InvalidPair.selector);

        new TWAPOracle(address(0xBEEF), MINIMUM_PERIOD);
    }

    function testConstructorRevertsForZeroMinimumPeriod() public {
        vm.expectRevert(TWAPOracle.InvalidMinimumPeriod.selector);

        new TWAPOracle(address(ammOracle), 0);
    }

    function testFirstUpdateInitializesObservation() public {
        ammOracle.update(address(pair));

        twapOracle.update(address(pair));

        assertTrue(twapOracle.isInitialized(address(pair)) == false);

        TWAPOracle.Observation memory observation = twapOracle.getPreviousObservation(address(pair));

        assertEq(uint256(observation.timestamp), uint256(uint32(block.timestamp)));
    }

    function testUpdateRevertsWhenAMMObservationMissing() public {
        vm.expectRevert(AMMOracle.ObservationNotFound.selector);

        twapOracle.update(address(pair));
    }

    function testCalculatesTWAPAfterMinimumPeriod() public {
        ammOracle.update(address(pair));

        twapOracle.update(address(pair));

        vm.warp(block.timestamp + MINIMUM_PERIOD);

        ammOracle.update(address(pair));

        twapOracle.update(address(pair));

        assertTrue(twapOracle.isInitialized(address(pair)));

        TWAPOracle.TWAPData memory data = twapOracle.getTWAP(address(pair));

        assertEq(data.price0Average, Q112);
        assertEq(data.price1Average, Q112);
    }

    function testUpdateRevertsWhenMinimumPeriodNotReached() public {
        ammOracle.update(address(pair));

        twapOracle.update(address(pair));

        vm.warp(block.timestamp + MINIMUM_PERIOD - 1);

        ammOracle.update(address(pair));

        vm.expectRevert(TWAPOracle.ObservationIntervalTooShort.selector);

        twapOracle.update(address(pair));
    }

    function testTWAPUpdatesAfterSecondInterval() public {
        ammOracle.update(address(pair));

        twapOracle.update(address(pair));

        vm.warp(block.timestamp + MINIMUM_PERIOD);

        ammOracle.update(address(pair));

        twapOracle.update(address(pair));

        TWAPOracle.TWAPData memory firstTWAP = twapOracle.getTWAP(address(pair));

        vm.warp(block.timestamp + MINIMUM_PERIOD);

        ammOracle.update(address(pair));

        twapOracle.update(address(pair));

        TWAPOracle.TWAPData memory secondTWAP = twapOracle.getTWAP(address(pair));

        assertGt(secondTWAP.timestamp, firstTWAP.timestamp);
    }

    function testConsultToken0ToToken1() public {
        _initializeTWAP();

        uint256 amountIn = 10 ether;

        uint256 amountOut = twapOracle.consult(address(pair), address(pair.token0()), amountIn);

        assertEq(amountOut, amountIn);
    }

    function testConsultToken1ToToken0() public {
        _initializeTWAP();

        uint256 amountIn = 10 ether;

        uint256 amountOut = twapOracle.consult(address(pair), address(pair.token1()), amountIn);

        assertEq(amountOut, amountIn);
    }

    function testConsultRevertsForInvalidPair() public {
        vm.expectRevert(TWAPOracle.InvalidPair.selector);

        twapOracle.consult(address(0), address(tokenA), 1 ether);
    }

    function testConsultRevertsForZeroAmount() public {
        _initializeTWAP();

        address token0 = address(pair.token0());

        vm.expectRevert(TWAPOracle.ZeroAmount.selector);

        twapOracle.consult(address(pair), token0, 0);
    }

    function testConsultRevertsForUninitializedTWAP() public {
        address token0 = address(pair.token0());

        vm.expectRevert(TWAPOracle.TWAPNotInitialized.selector);

        twapOracle.consult(address(pair), token0, 1 ether);
    }

    function testConsultRevertsForInvalidToken() public {
        _initializeTWAP();

        vm.expectRevert(TWAPOracle.InvalidToken.selector);

        twapOracle.consult(address(pair), address(tokenC), 1 ether);
    }

    function testGetTWAPRevertsBeforeInitialization() public {
        vm.expectRevert(TWAPOracle.TWAPNotInitialized.selector);

        twapOracle.getTWAP(address(pair));
    }

    function testGetPreviousObservationRevertsInitially() public {
        vm.expectRevert(TWAPOracle.ObservationNotInitialized.selector);

        twapOracle.getPreviousObservation(address(pair));
    }

    function testIsInitializedReturnsFalseInitially() public view {
        assertFalse(twapOracle.isInitialized(address(pair)));
    }

    function _initializeTWAP() internal {
        ammOracle.update(address(pair));

        twapOracle.update(address(pair));

        vm.warp(block.timestamp + MINIMUM_PERIOD);

        ammOracle.update(address(pair));

        twapOracle.update(address(pair));
    }
}
