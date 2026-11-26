// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAMMFeeManager} from "./IAMMFeeManager.sol";

interface IAMMFactory is IAMMFeeManager {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairCount);

    // event FeeToUpdated(address indexed previousSetter, address indexed newFeeTo);

    // event FeeToSetterUpdated(address indexed previousSetter, address indexed newSetter);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function allPairs(uint256 index) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function pairCodeHash() external view returns (bytes32);

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function setFeeTo(address newFeeTo) external;

    function setFeeToSetter(address newFeeToSetter) external;
}
