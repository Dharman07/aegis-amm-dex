// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IAMMOracle {
    struct Observation {
        uint32 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    event ObservationUpdated(
        address indexed pair, uint32 timestamp, uint256 price0Cumulative, uint256 price1Cumulative
    );

    function update(address pair) external;

    function getLatestObservation(address pair) external view returns (Observation memory);

    function observationExists(address pair) external view returns (bool);
}
