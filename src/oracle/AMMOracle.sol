// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IAMMOracle} from "../interfaces/IAMMOracle.sol";
import {IAMMPair} from "../interfaces/IAMMPair.sol";
import {IAMMFactory} from "../interfaces/IAMMFactory.sol";

contract AMMOracle is IAMMOracle, AccessControl {
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    uint256 private constant Q112 = 2 ** 112;

    IAMMFactory public immutable factory;

    mapping(address pair => Observation) private observations;

    mapping(address pair => bool) private observationInitialized;

    error ZeroAddress();
    error InvalidPair();
    error InsufficientLiquidity();
    error ObservationNotFound();
    error InvalidFactory();

    constructor(address admin, address updater, address factory_) {
        if (admin == address(0) || updater == address(0) || factory_ == address(0)) {
            revert ZeroAddress();
        }

        if (factory_.code.length == 0) {
            revert InvalidFactory();
        }

        factory = IAMMFactory(factory_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPDATER_ROLE, updater);
    }

    function update(address pair) external onlyRole(UPDATER_ROLE) {
        if (pair == address(0) || pair.code.length == 0) {
            revert InvalidPair();
        }

        IAMMPair ammPair = IAMMPair(pair);

        uint256 reserve0 = ammPair.reserve0();
        uint256 reserve1 = ammPair.reserve1();

        if (reserve0 == 0 || reserve1 == 0) {
            revert InsufficientLiquidity();
        }

        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 timestamp) = _currentCumulativePrices(ammPair);

        observations[pair] =
            Observation({timestamp: timestamp, price0Cumulative: price0Cumulative, price1Cumulative: price1Cumulative});

        observationInitialized[pair] = true;

        emit ObservationUpdated(pair, timestamp, price0Cumulative, price1Cumulative);
    }

    function getLatestObservation(address pair) external view returns (Observation memory observation) {
        if (!observationInitialized[pair]) {
            revert ObservationNotFound();
        }

        return observations[pair];
    }

    function observationExists(address pair) external view returns (bool) {
        return observationInitialized[pair];
    }

    function _currentCumulativePrices(IAMMPair pair)
        internal
        view
        returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 timestamp)
    {
        price0Cumulative = pair.price0CumulativeLast();
        price1Cumulative = pair.price1CumulativeLast();

        uint256 reserve0 = pair.reserve0();
        uint256 reserve1 = pair.reserve1();

        timestamp = uint32(block.timestamp);

        uint32 timeElapsed;

        unchecked {
            timeElapsed = timestamp - pair.blockTimestampLast();
        }

        if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            uint256 price0 = (reserve1 << 112) / reserve0;
            uint256 price1 = (reserve0 << 112) / reserve1;

            unchecked {
                price0Cumulative += price0 * timeElapsed;
                price1Cumulative += price1 * timeElapsed;
            }
        }
    }
}
