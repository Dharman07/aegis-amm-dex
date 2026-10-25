// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library AMMMath {
    uint256 internal constant FEE_NUMERATOR = 997;
    uint256 internal constant FEE_DENOMINATOR = 1000;

    error ZeroAmount();
    error InsufficientLiquidity();
    error InsufficientOutputAmount();

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns(uint256 amountOut) {

        if (amountIn == 0) {
            revert ZeroAmount();
        }

        if (reserveIn == 0 || reserveOut == 0) {
            revert InsufficientLiquidity();
        }

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;

        uint256 numerator = amountInWithFee * reserveOut;

        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
    
        amountOut = numerator / denominator;
    
        if (amountOut == 0) {
            revert InsufficientOutputAmount();
        }

        if (amountOut >= reserveOut) {
            revert InsufficientLiquidity();
        }

    }
}