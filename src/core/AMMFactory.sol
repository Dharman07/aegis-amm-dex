pragma solidity ^0.8.30;

import {AMMPair} from "./AMMPair.sol";
import {IEmergencyControl} from "../interfaces/IEmergencyControl.sol";
import {IAMMFeeManager} from "../interfaces/IAMMFeeManager.sol";

contract AMMFactory is IAMMFeeManager {

    mapping(address => mapping(address => address)) public getPair;

    address[] public allPairs;

    address public override feeTo;
    address public override feeToSetter;
    IEmergencyControl public immutable emergencyControl;

    error ZeroAddress();
    error IdenticalTokens();
    error InvalidToken();
    error PairAlreadyExists();
    error Unauthorized();
    error InvalidEmergencyControl();

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairCount);

    // event FeeToUpdated(address indexed previousFeeTo, address indexed newFeeTo);

    // event FeeToSetterUpdated(address indexed previousSetter, address indexed newSetter);

    constructor(address emergencyControl_) {
        if (emergencyControl_ == address(0) || emergencyControl_.code.length == 0) {
            revert InvalidEmergencyControl();
        }

        emergencyControl = IEmergencyControl(emergencyControl_);
        feeToSetter = msg.sender;
    }

    modifier onlyFeeToSetter() {
        if (msg.sender != feeToSetter) {
            revert Unauthorized();
        }
        _;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == address(0) || tokenB == address(0)) {
            revert ZeroAddress();
        }

        if (tokenA == tokenB) {
            revert IdenticalTokens();
        }

        if (tokenA.code.length == 0 || tokenB.code.length == 0) {
            revert InvalidToken();
        }

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        if (getPair[token0][token1] != address(0)) {
            revert PairAlreadyExists();
        }

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        pair = address(new AMMPair{salt: salt}(token0, token1, address(emergencyControl)));

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;

        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address newFeeTo) external override onlyFeeToSetter {
        address previousFeeTo = feeTo;

        feeTo = newFeeTo;

        emit FeeToUpdated(previousFeeTo, newFeeTo);
    }

    function setFeeToSetter(address newFeeToSetter) external override onlyFeeToSetter {
        if (newFeeToSetter == address(0)) {
            revert ZeroAddress();
        }

        address previousSetter = feeToSetter;

        feeToSetter = newFeeToSetter;

        emit FeeToSetterUpdated(previousSetter, newFeeToSetter);
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function pairCodeHash() external view returns (bytes32) {
        return keccak256(type(AMMPair).creationCode);
    }
}
