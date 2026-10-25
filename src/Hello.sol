pragma solidity ^0.8.30;

contract Hello {
    string public message = "Hello, Web3!";

    function updateMessage(string calldata newMessage) external {
        message = newMessage;
    }
}