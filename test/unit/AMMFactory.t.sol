pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EmergencyControl} from "../../src/security/EmergencyControl.sol";
import {TokenPolicy} from "../../src/security/TokenPolicy.sol";
import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {AMMPair} from "../../src/core/AMMPair.sol";

contract FactoryMockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}
}

contract AMMFactoryTest is Test {
    AMMFactory internal factory;

    FactoryMockERC20 internal tokenA;
    FactoryMockERC20 internal tokenB;
    EmergencyControl internal emergencyControl;
    TokenPolicy internal tokenPolicy;

    function setUp() public {
        emergencyControl = new EmergencyControl(address(this));
        tokenPolicy = new TokenPolicy(address(this));
        factory = new AMMFactory(
            address(emergencyControl),
            address(tokenPolicy)
        );

        tokenA = new FactoryMockERC20("Token A", "TKA");
        tokenB = new FactoryMockERC20("Token B", "TKB");
        tokenPolicy.approveToken(address(tokenA));
        tokenPolicy.approveToken(address(tokenB));
    }

    function testCreatePair() public {
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));

        assertTrue(pairAddress != address(0));
        assertTrue(pairAddress.code.length > 0);

        assertEq(factory.getPair(address(tokenA), address(tokenB)), pairAddress);

        assertEq(factory.allPairsLength(), 1);

        AMMPair pair = AMMPair(pairAddress);

        address expectedToken0;
        address expectedToken1;

        if (address(tokenA) < address(tokenB)) {
            expectedToken0 = address(tokenA);
            expectedToken1 = address(tokenB);
        } else {
            expectedToken0 = address(tokenB);
            expectedToken1 = address(tokenA);
        }

        assertEq(address(pair.token0()), expectedToken0);
        assertEq(address(pair.token1()), expectedToken1);
    }

    function testReverseTokenOrderingReturnsSamePair() public {
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));

        address reversePairAddress = factory.getPair(address(tokenB), address(tokenA));

        assertEq(reversePairAddress, pairAddress);
        assertEq(factory.allPairsLength(), 1);
    }

    function testDuplicatePairCreationReverts() public {
        factory.createPair(address(tokenA), address(tokenB));

        vm.expectRevert(AMMFactory.PairAlreadyExists.selector);

        factory.createPair(address(tokenB), address(tokenA));
    }

    function testInvariantTokenAddressReverts() public {
        address invalidToken = address(0xBEEF);

        vm.expectRevert(AMMFactory.InvalidToken.selector);

        factory.createPair(address(tokenA), invalidToken);
    }
}
