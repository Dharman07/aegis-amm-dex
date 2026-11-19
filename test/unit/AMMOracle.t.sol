pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EmergencyControl} from "../../src/security/EmergencyControl.sol";

import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {AMMPair} from "../../src/core/AMMPair.sol";
import {AMMOracle} from "../../src/oracle/AMMOracle.sol";
import {IAMMOracle} from "../../src/interfaces/IAMMOracle.sol";

contract OracleTestToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AMMOracleTest is Test {
    AMMFactory internal factory;
    AMMOracle internal oracle;
    EmergencyControl internal emergencyControl;

    OracleTestToken internal tokenA;
    OracleTestToken internal tokenB;
    OracleTestToken internal tokenC;

    AMMPair internal pair;

    address internal admin = makeAddr("admin");
    address internal updater = makeAddr("updater");
    address internal unauthorized = makeAddr("unauthorized");

    uint256 internal constant INITIAL_AMOUNT = 1_000 ether;
    uint256 internal constant Q112 = 2 ** 112;

    function setUp() public {
        emergencyControl = new EmergencyControl(address(this));
        factory = new AMMFactory(address(emergencyControl));

        oracle = new AMMOracle(admin, updater);

        tokenA = new OracleTestToken("Token A", "TKA");
        tokenB = new OracleTestToken("Token B", "TKB");
        tokenC = new OracleTestToken("Token C", "TKC");

        tokenA.mint(address(this), 5_000 ether);
        tokenB.mint(address(this), 5_000 ether);

        address pairAddress = factory.createPair(address(tokenA), address(tokenB));

        pair = AMMPair(pairAddress);

        tokenA.approve(address(pair), type(uint256).max);
        tokenB.approve(address(pair), type(uint256).max);

        pair.addLiquidity(INITIAL_AMOUNT, INITIAL_AMOUNT, INITIAL_AMOUNT, INITIAL_AMOUNT, address(this));
    }

    // ---------------------------------------------------------
    // Constructor tests
    // ---------------------------------------------------------

    function testConstructorAssignsAdminRole() public view {
        assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), admin));
    }

    function testConstructorAssignsUpdaterRole() public view {
        assertTrue(oracle.hasRole(oracle.UPDATER_ROLE(), updater));
    }

    function testConstructorRevertsForZeroAdmin() public {
        vm.expectRevert(AMMOracle.ZeroAddress.selector);

        new AMMOracle(address(0), updater);
    }

    function testConstructorRevertsForZeroUpdater() public {
        vm.expectRevert(AMMOracle.ZeroAddress.selector);

        new AMMOracle(admin, address(0));
    }

    function testUnauthorizedUpdaterCannotUpdate() public {
        vm.prank(unauthorized);

        vm.expectRevert();

        oracle.update(address(pair));
    }

    function testAdminCanGrantUpdaterRole() public {
        address newUpdater = makeAddr("newUpdater");

        bytes32 updaterRole = oracle.UPDATER_ROLE();

        vm.prank(admin);

        oracle.grantRole(updaterRole, newUpdater);

        assertTrue(oracle.hasRole(updaterRole, newUpdater));
    }

    function testUpdateRevertsForZeroAddress() public {
        vm.prank(updater);

        vm.expectRevert(AMMOracle.InvalidPair.selector);

        oracle.update(address(0));
    }

    function testUpdateRevertsForInvalidPair() public {
        address invalidPair = makeAddr("invalidPair");

        vm.prank(updater);

        vm.expectRevert(AMMOracle.InvalidPair.selector);

        oracle.update(invalidPair);
    }

    function testUpdateRevertsForZeroLiquidity() public {
        address emptyPair = factory.createPair(address(tokenA), address(tokenC));

        vm.prank(updater);

        vm.expectRevert(AMMOracle.InsufficientLiquidity.selector);

        oracle.update(emptyPair);
    }

    function testFirstObservationIsStored() public {
        vm.prank(updater);

        oracle.update(address(pair));

        assertTrue(oracle.observationExists(address(pair)));

        IAMMOracle.Observation memory observation = oracle.getLatestObservation(address(pair));

        assertEq(uint256(observation.timestamp), uint256(uint32(block.timestamp)));
    }

    function testObservationStoresCumulativePrices() public {
        vm.warp(block.timestamp + 1 hours);

        vm.prank(updater);

        oracle.update(address(pair));

        IAMMOracle.Observation memory observation = oracle.getLatestObservation(address(pair));

        assertGt(observation.price0Cumulative, 0);
        assertGt(observation.price1Cumulative, 0);
    }

    function testCounterfactualCumulativePrice() public {
        uint32 pairTimestampBefore = pair.blockTimestampLast();

        uint256 elapsed = 1 hours;

        vm.warp(block.timestamp + elapsed);

        vm.prank(updater);

        oracle.update(address(pair));

        IAMMOracle.Observation memory observation = oracle.getLatestObservation(address(pair));

        uint256 expectedCumulative = Q112 * elapsed;

        assertEq(observation.price0Cumulative, expectedCumulative);

        assertEq(observation.price1Cumulative, expectedCumulative);

        assertEq(uint256(observation.timestamp), uint256(pairTimestampBefore) + elapsed);
    }

    function testObservationCanBeUpdated() public {
        vm.prank(updater);

        oracle.update(address(pair));

        IAMMOracle.Observation memory firstObservation = oracle.getLatestObservation(address(pair));

        vm.warp(block.timestamp + 2 hours);

        vm.prank(updater);

        oracle.update(address(pair));

        IAMMOracle.Observation memory secondObservation = oracle.getLatestObservation(address(pair));

        assertGt(secondObservation.timestamp, firstObservation.timestamp);

        assertGt(secondObservation.price0Cumulative, firstObservation.price0Cumulative);
    }

    function testObservationExistsReturnsFalseInitially() public view {
        assertFalse(oracle.observationExists(address(pair)));
    }

    function testGetLatestObservationRevertsWhenNotInitialized() public {
        vm.expectRevert(AMMOracle.ObservationNotFound.selector);

        oracle.getLatestObservation(address(pair));
    }
}
