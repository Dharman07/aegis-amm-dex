pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Hello} from "../src/Hello.sol";

contract HelloTest is Test {
    Hello hello;

    function setUp() public {
        hello = new Hello();
    }

    function testInitialMessage() public {
        assertEq(hello.message(), "Hello, Web3!");
    }

    function testUpdateMessage() public {
        hello.updateMessage("Amm protocol");
        assertEq(hello.message(), "Amm protocol");
    }
}