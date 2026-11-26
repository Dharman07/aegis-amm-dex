pragma solidity ^0.8.30;

interface IAMMFeeManager {
    event FeeToUpdated(address indexed previousFeeTo, address indexed newFeeTo);

    event FeeToSetterUpdated(address indexed previousSetter, address indexed newSetter);

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function setFeeTo(address newFeeTo) external;

    function setFeeToSetter(address newFeeToSetter) external;
}
