// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract TokenPolicy is AccessControl {
    // ROLES

    bytes32 public constant TOKEN_ADMIN_ROLE = keccak256("TOKEN_ADMIN_ROLE");

    bytes32 public constant TOKEN_GUARDIAN_ROLE = keccak256("TOKEN_GUARDIAN_ROLE");

    // ENUM

    enum TokenStatus {
        Unlisted,
        Approved,
        Blocked
    }

    // STATE VARIABLES

    mapping(address => TokenStatus) private _tokenStatus;

    // ERRORS

    error ZeroAddress();
    error InvalidToken();
    error TokenAlreadyApproved();
    error TokenNotApproved();
    error TokenAlreadyBlocked();
    error TokenNotBlocked();

    // EVENTS

    event TokenApproved(address indexed token, address indexed account);

    event TokenRevoked(address indexed token, address indexed account);

    event TokenBlocked(address indexed token, address indexed account);

    event TokenUnblocked(address indexed token, address indexed account);

    // CONSTRUCTOR

    constructor(address admin_) {
        if (admin_ == address(0)) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        _grantRole(TOKEN_ADMIN_ROLE, admin_);

        _grantRole(TOKEN_GUARDIAN_ROLE, admin_);
    }

    // TOKEN APPROVAL

    function approveToken(address token) external onlyRole(TOKEN_ADMIN_ROLE) {
        _validateToken(token);

        if (_tokenStatus[token] == TokenStatus.Approved) {
            revert TokenAlreadyApproved();
        }

        if (_tokenStatus[token] == TokenStatus.Blocked) {
            revert TokenAlreadyBlocked();
        }

        _tokenStatus[token] = TokenStatus.Approved;

        emit TokenApproved(token, msg.sender);
    }

    // TOKEN REVOCATION

    function revokeToken(address token) external onlyRole(TOKEN_ADMIN_ROLE) {
        if (_tokenStatus[token] != TokenStatus.Approved) {
            revert TokenNotApproved();
        }

        _tokenStatus[token] = TokenStatus.Unlisted;

        emit TokenRevoked(token, msg.sender);
    }

    // EMERGENCY BLOCK

    function blockToken(address token) external onlyRole(TOKEN_GUARDIAN_ROLE) {
        if (_tokenStatus[token] != TokenStatus.Approved) {
            revert TokenNotApproved();
        }

        _tokenStatus[token] = TokenStatus.Blocked;

        emit TokenBlocked(token, msg.sender);
    }

    // UNBLOCK TOKEN

    function unblockToken(address token) external onlyRole(TOKEN_ADMIN_ROLE) {
        if (_tokenStatus[token] != TokenStatus.Blocked) {
            revert TokenNotBlocked();
        }

        _tokenStatus[token] = TokenStatus.Approved;

        emit TokenUnblocked(token, msg.sender);
    }

    // TOKEN VALIDATION

    function isTokenAllowed(address token) external view returns (bool) {
        return _tokenStatus[token] == TokenStatus.Approved;
    }

    // TOKEN STATUS

    function getTokenStatus(address token) external view returns (TokenStatus) {
        return _tokenStatus[token];
    }

    // INTERNAL VALIDATION

    function _validateToken(address token) internal view {
        if (token == address(0)) {
            revert ZeroAddress();
        }

        if (token.code.length == 0) {
            revert InvalidToken();
        }
    }
}
