// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IAMMFactory} from "../interfaces/IAMMFactory.sol";
import {IAMMPair} from "../interfaces/IAMMPair.sol";
import {IFlashSwapCallback} from "./interfaces/IFlashSwapCallback.sol";

interface IFlashSwapStrategy {
    function execute(
        address pair,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

contract FlashSwap is IFlashSwapCallback, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IAMMFactory public immutable factory;

    address private activePair;
    address private activeStrategy;
    address private activeInitiator;

    IERC20 private activeToken0;
    IERC20 private activeToken1;

    uint256 private activeAmount0Out;
    uint256 private activeAmount1Out;

    uint256 private activeRepayment0;
    uint256 private activeRepayment1;

    uint256 private initialBalance0;
    uint256 private initialBalance1;

    bytes32 private activeDataHash;

    bool private callbackExecuted;

    error ZeroAddress();
    error InvalidFactory();
    error InvalidPair();
    error InvalidStrategy();
    error InvalidOutputAmount();
    error InvalidRepayment();
    error InvalidCallback();
    error InvalidCallbackData();
    error CallbackAlreadyExecuted();
    error CallbackNotExecuted();
    error InsufficientRepayment();
    error Expired();

    event FlashSwapExecuted(
        address indexed pair,
        address indexed initiator,
        address indexed strategy,
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 repayment0,
        uint256 repayment1,
        uint256 profit0,
        uint256 profit1
    );

    constructor(address factory_) {
        if (factory_ == address(0)) {
            revert ZeroAddress();
        }

        if (factory_.code.length == 0) {
            revert InvalidFactory();
        }

        factory = IAMMFactory(factory_);
    }

    function execute(
        address pair,
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 repayment0,
        uint256 repayment1,
        address strategy,
        bytes calldata data,
        uint256 deadline
    ) external nonReentrant returns (uint256 profit0, uint256 profit1) {
        if (block.timestamp > deadline) {
            revert Expired();
        }

        if (pair == address(0) || pair.code.length == 0) {
            revert InvalidPair();
        }

        if (strategy == address(0) || strategy.code.length == 0) {
            revert InvalidStrategy();
        }

        if (amount0Out == 0 && amount1Out == 0) {
            revert InvalidOutputAmount();
        }

        if (repayment0 == 0 && repayment1 == 0) {
            revert InvalidRepayment();
        }

        IAMMPair ammPair = IAMMPair(pair);

        if (ammPair.factory() != address(factory)) {
            revert InvalidPair();
        }

        IERC20 token0 = ammPair.token0();
        IERC20 token1 = ammPair.token1();

        if (factory.getPair(address(token0), address(token1)) != pair) {
            revert InvalidPair();
        }

        if (activePair != address(0)) {
            revert InvalidCallback();
        }

        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));

        activePair = pair;
        activeStrategy = strategy;
        activeInitiator = msg.sender;

        activeToken0 = token0;
        activeToken1 = token1;

        activeAmount0Out = amount0Out;
        activeAmount1Out = amount1Out;

        activeRepayment0 = repayment0;
        activeRepayment1 = repayment1;

        initialBalance0 = balance0Before;
        initialBalance1 = balance1Before;

        activeDataHash = keccak256(data);

        callbackExecuted = false;

        // abi.encode ensures callback data is non-empty,
        // even when strategy data itself is empty.
        ammPair.swap(amount0Out, amount1Out, address(this), abi.encode(data));

        if (!callbackExecuted) {
            revert CallbackNotExecuted();
        }

        uint256 balance0After = token0.balanceOf(address(this));
        uint256 balance1After = token1.balanceOf(address(this));

        profit0 = balance0After - balance0Before;
        profit1 = balance1After - balance1Before;

        address initiator = activeInitiator;

        _clearActiveOperation();

        if (profit0 > 0) {
            token0.safeTransfer(initiator, profit0);
        }

        if (profit1 > 0) {
            token1.safeTransfer(initiator, profit1);
        }

        emit FlashSwapExecuted(
            pair, initiator, strategy, amount0Out, amount1Out, repayment0, repayment1, profit0, profit1
        );
    }

    function aegisCall(address sender, uint256 amount0, uint256 amount1, bytes calldata callbackData)
        external
        override
    {
        if (msg.sender != activePair || activePair == address(0) || sender != address(this)) {
            revert InvalidCallback();
        }

        if (callbackExecuted) {
            revert CallbackAlreadyExecuted();
        }

        if (amount0 != activeAmount0Out || amount1 != activeAmount1Out) {
            revert InvalidCallback();
        }

        bytes memory strategyData = abi.decode(callbackData, (bytes));

        if (keccak256(strategyData) != activeDataHash) {
            revert InvalidCallbackData();
        }

        callbackExecuted = true;

        if (amount0 > 0) {
            activeToken0.safeTransfer(activeStrategy, amount0);
        }

        if (amount1 > 0) {
            activeToken1.safeTransfer(activeStrategy, amount1);
        }

        IFlashSwapStrategy(activeStrategy)
            .execute(activePair, address(activeToken0), address(activeToken1), amount0, amount1, strategyData);

        uint256 balance0 = activeToken0.balanceOf(address(this));
        uint256 balance1 = activeToken1.balanceOf(address(this));

        if (balance0 < initialBalance0 + activeRepayment0 || balance1 < initialBalance1 + activeRepayment1) {
            revert InsufficientRepayment();
        }

        if (activeRepayment0 > 0) {
            activeToken0.safeTransfer(msg.sender, activeRepayment0);
        }

        if (activeRepayment1 > 0) {
            activeToken1.safeTransfer(msg.sender, activeRepayment1);
        }
    }

    function _clearActiveOperation() internal {
        activePair = address(0);
        activeStrategy = address(0);
        activeInitiator = address(0);

        activeToken0 = IERC20(address(0));
        activeToken1 = IERC20(address(0));

        activeAmount0Out = 0;
        activeAmount1Out = 0;

        activeRepayment0 = 0;
        activeRepayment1 = 0;

        initialBalance0 = 0;
        initialBalance1 = 0;

        activeDataHash = bytes32(0);

        callbackExecuted = false;
    }
}
