// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAMMOracle} from "../interfaces/IAMMOracle.sol";
import {IAMMPair} from "../interfaces/IAMMPair.sol";

contract TWAPOracle {
    uint256 private constant Q112 = 2 ** 112;

    IAMMOracle public immutable ammOracle;

    uint32 public immutable minimumPeriod;

    struct Observation {
        uint32 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    struct TWAPData {
        uint32 timestamp;
        uint256 price0Average;
        uint256 price1Average;
    }

    mapping(address pair => Observation) private observations;

    mapping(address pair => TWAPData) private twapData;

    mapping(address pair => bool) private observationInitialized;

    mapping(address pair => bool) private twapInitialized;

    error ZeroAddress();
    error InvalidMinimumPeriod();
    error InvalidPair();
    error ObservationNotInitialized();
    error ObservationIntervalTooShort();
    error TWAPNotInitialized();
    error InvalidToken();
    error ZeroAmount();

    event ObservationInitialized(address indexed pair, uint32 timestamp);

    event TWAPUpdated(address indexed pair, uint32 timestamp, uint256 price0Average, uint256 price1Average);

    constructor(address ammOracle_, uint32 minimumPeriod_) {
        if (ammOracle_ == address(0)) {
            revert ZeroAddress();
        }

        if (ammOracle_.code.length == 0) {
            revert InvalidPair();
        }

        if (minimumPeriod_ == 0) {
            revert InvalidMinimumPeriod();
        }

        ammOracle = IAMMOracle(ammOracle_);
        minimumPeriod = minimumPeriod_;
    }

    function update(address pair) external {
        if (pair == address(0) || pair.code.length == 0) {
            revert InvalidPair();
        }

        IAMMOracle.Observation memory current = ammOracle.getLatestObservation(pair);

        if (!observationInitialized[pair]) {
            observations[pair] = Observation({
                timestamp: current.timestamp,
                price0Cumulative: current.price0Cumulative,
                price1Cumulative: current.price1Cumulative
            });

            observationInitialized[pair] = true;

            emit ObservationInitialized(pair, current.timestamp);

            return;
        }

        Observation memory previous = observations[pair];

        uint32 timeElapsed;

        unchecked {
            timeElapsed = current.timestamp - previous.timestamp;
        }

        if (timeElapsed < minimumPeriod) {
            revert ObservationIntervalTooShort();
        }

        uint256 price0CumulativeDelta;
        uint256 price1CumulativeDelta;

        unchecked {
            price0CumulativeDelta = current.price0Cumulative - previous.price0Cumulative;

            price1CumulativeDelta = current.price1Cumulative - previous.price1Cumulative;
        }

        uint256 price0Average = price0CumulativeDelta / timeElapsed;

        uint256 price1Average = price1CumulativeDelta / timeElapsed;

        twapData[pair] =
            TWAPData({timestamp: current.timestamp, price0Average: price0Average, price1Average: price1Average});

        twapInitialized[pair] = true;

        observations[pair] = Observation({
            timestamp: current.timestamp,
            price0Cumulative: current.price0Cumulative,
            price1Cumulative: current.price1Cumulative
        });

        emit TWAPUpdated(pair, current.timestamp, price0Average, price1Average);
    }

    function consult(address pair, address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        if (pair == address(0) || pair.code.length == 0) {
            revert InvalidPair();
        }

        if (amountIn == 0) {
            revert ZeroAmount();
        }

        if (!twapInitialized[pair]) {
            revert TWAPNotInitialized();
        }

        IAMMPair ammPair = IAMMPair(pair);

        address token0 = address(ammPair.token0());
        address token1 = address(ammPair.token1());

        TWAPData memory data = twapData[pair];

        if (tokenIn == token0) {
            amountOut = Math.mulDiv(amountIn, data.price0Average, Q112);
        } else if (tokenIn == token1) {
            amountOut = Math.mulDiv(amountIn, data.price1Average, Q112);
        } else {
            revert InvalidToken();
        }
    }

    function getTWAP(address pair) external view returns (TWAPData memory) {
        if (!twapInitialized[pair]) {
            revert TWAPNotInitialized();
        }

        return twapData[pair];
    }

    function getPreviousObservation(address pair) external view returns (Observation memory) {
        if (!observationInitialized[pair]) {
            revert ObservationNotInitialized();
        }

        return observations[pair];
    }

    function isInitialized(address pair) external view returns (bool) {
        return twapInitialized[pair];
    }
}
