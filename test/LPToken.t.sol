pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {LPToken} from "../src/token/LPToken.sol";

contract LPTokenTest is Test {

    LPToken internal lpToken;

    address internal user = address(0x123);
    address internal attacker = address(0xBEEF);

    string internal constant TOKEN_NAME = "Aegis LP Token";
    string internal constant TOKEN_SYMBOL = "AELP";

    uint256 internal constant INITIAL_AMOUNT = 100 ether;

    function setUp() public {
        lpToken = new LPToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(this)
        );
    }

    function testTokenNameAndSymbol() public view {
        assertEq(lpToken.name(), TOKEN_NAME);
        assertEq(lpToken.symbol(), TOKEN_SYMBOL);
    }

    function testPoolAddress() public view {
        assertEq(lpToken.pool(), address(this));
    }

    function testRevertWhenPoolAddressIsZero() public {
        vm.expectRevert(LPToken.ZeroPoolAddress.selector);

        new LPToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            address(0)
        );
    }

    function testPoolCanMint() public {
        lpToken.mint(user, INITIAL_AMOUNT);

        assertEq(lpToken.balanceOf(user), INITIAL_AMOUNT);
        assertEq(lpToken.totalSupply(), INITIAL_AMOUNT);
    }

    function testUnauthorizedMintReverts() public {
        vm.prank(attacker);

        vm.expectRevert(
            abi.encodeWithSelector(
                LPToken.UnauthorizedPool.selector,
                attacker
            )
        );

        lpToken.mint(user, INITIAL_AMOUNT);
    }

    function testPoolCanBurn() public {
        lpToken.mint(user, INITIAL_AMOUNT);
        lpToken.burn(user, 40 ether);

        assertEq(lpToken.balanceOf(user), 60 ether);
        assertEq(lpToken.totalSupply(), 60 ether);
    }

    function testUnauthorizedBurnReverts() public {
        lpToken.mint(user, INITIAL_AMOUNT);

        vm.prank(attacker);

        vm.expectRevert(
            abi.encodeWithSelector(
                LPToken.UnauthorizedPool.selector,
                attacker
            )
        );

        lpToken.burn(user, 40 ether);
    }

    function testUserCanTransferLPToken() public {

        lpToken.mint(user, INITIAL_AMOUNT);

        vm.prank(user);
        lpToken.transfer(attacker, 25 ether);

        assertEq(lpToken.balanceOf(user), 75 ether);
        assertEq(lpToken.balanceOf(attacker), 25 ether);

    }
}