pragma solidity ^0.8.30;

interface ITokenPolicy {

    function isTokenAllowed(
        address token
    ) external view returns (bool);

    function getTokenStatus(
        address token
    ) external view returns (uint8);
}
