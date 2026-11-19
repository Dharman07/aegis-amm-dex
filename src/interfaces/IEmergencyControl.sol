pragma solidity ^0.8.30;

interface IEmergencyControl {
    function isPaused(bytes32 operation) external view returns (bool);
}
