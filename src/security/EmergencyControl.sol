pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract EmergencyControl is AccessControl {
    error ZeroAdminAddress();
    error AlreadyPaused();
    error AlreadyUnpaused();
    error InvalidOperation();

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    bool private _protocolPaused;

    mapping(bytes32 operation => bool paused) private _pausedOperations;

    event ProtocolPaused(address indexed account);
    event ProtocolUnpaused(address indexed account);

    event OperationPaused(bytes32 indexed operation, address indexed account);

    event OperationUnpaused(bytes32 indexed operation, address indexed account);

    constructor(address admin_) {
        if (admin_ == address(0)) {
            revert ZeroAdminAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        _grantRole(UNPAUSER_ROLE, admin_);
    }

    function pauseProtocol() external onlyRole(PAUSER_ROLE) {
        if (_protocolPaused) {
            revert AlreadyPaused();
        }

        _protocolPaused = true;

        emit ProtocolPaused(msg.sender);
    }

    function unpauseProtocol() external onlyRole(UNPAUSER_ROLE) {
        if (!_protocolPaused) {
            revert AlreadyUnpaused();
        }

        _protocolPaused = false;

        emit ProtocolUnpaused(msg.sender);
    }

    function pauseOperation(bytes32 operation) external onlyRole(PAUSER_ROLE) {
        if (operation == bytes32(0)) {
            revert InvalidOperation();
        }

        if (_pausedOperations[operation]) {
            revert AlreadyPaused();
        }

        _pausedOperations[operation] = true;

        emit OperationPaused(operation, msg.sender);
    }

    function unpauseOperation(bytes32 operation) external onlyRole(UNPAUSER_ROLE) {
        if (operation == bytes32(0)) {
            revert InvalidOperation();
        }

        if (!_pausedOperations[operation]) {
            revert AlreadyUnpaused();
        }

        _pausedOperations[operation] = false;

        emit OperationUnpaused(operation, msg.sender);
    }

    function isProtocolPaused() external view returns (bool) {
        return _protocolPaused;
    }

    function isOperationPaused(bytes32 operation) external view returns (bool) {
        return _pausedOperations[operation];
    }

    function isPaused(bytes32 operation) external view returns (bool) {
        return _protocolPaused || _pausedOperations[operation];
    }
}
