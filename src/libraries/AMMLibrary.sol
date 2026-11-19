pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IAMMPairReserves {
    function token0() external view returns (address);
    function token1() external view returns (address);

    function reserve0() external view returns (uint256);
    function reserve1() external view returns (uint256);
}

library AMMLibrary {
    uint256 internal constant FEE_NUMERATOR = 997;
    uint256 internal constant FEE_DENOMINATOR = 1000;

    error InsufficientAmount();
    error InsufficientLiquidity();
    error InvalidToken();
    error InvalidPair();
    error MathOverflow();

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        if (amountA == 0) revert InsufficientAmount();

        if (reserveA == 0 || reserveB == 0) {
            revert InsufficientLiquidity();
        }

        amountB = Math.mulDiv(amountA, reserveB, reserveA);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientAmount();

        if (reserveIn == 0 || reserveOut == 0) {
            revert InsufficientLiquidity();
        }

        if (amountIn > type(uint256).max / FEE_NUMERATOR) {
            revert MathOverflow();
        }

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;

        if (reserveIn > type(uint256).max / FEE_DENOMINATOR) {
            revert MathOverflow();
        }

        uint256 reserveInScaled = reserveIn * FEE_DENOMINATOR;

        if (amountInWithFee > type(uint256).max - reserveInScaled) {
            revert MathOverflow();
        }

        uint256 denominator = reserveInScaled + amountInWithFee;

        amountOut = Math.mulDiv(amountInWithFee, reserveOut, denominator);

        if (amountOut == 0) revert InsufficientAmount();

        if (amountOut >= reserveOut) {
            revert InsufficientLiquidity();
        }
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        if (amountOut == 0) revert InsufficientAmount();

        if (reserveIn == 0 || reserveOut == 0) {
            revert InsufficientLiquidity();
        }

        if (amountOut >= reserveOut) {
            revert InsufficientLiquidity();
        }

        uint256 reserveOutRemaining = reserveOut - amountOut;

        if (amountOut > type(uint256).max / FEE_DENOMINATOR) {
            revert MathOverflow();
        }

        if (reserveOutRemaining > type(uint256).max / FEE_NUMERATOR) {
            revert MathOverflow();
        }

        uint256 numeratorFactor = amountOut * FEE_DENOMINATOR;
        uint256 denominator = reserveOutRemaining * FEE_NUMERATOR;

        amountIn = Math.mulDiv(reserveIn, numeratorFactor, denominator, Math.Rounding.Ceil);
    }

    function getReserves(address pair, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        if (pair == address(0) || pair.code.length == 0) {
            revert InvalidPair();
        }

        if (tokenA == address(0) || tokenB == address(0) || tokenA == tokenB) {
            revert InvalidToken();
        }

        IAMMPairReserves pairContract = IAMMPairReserves(pair);

        address token0_ = pairContract.token0();
        address token1_ = pairContract.token1();

        uint256 reserve0_ = pairContract.reserve0();
        uint256 reserve1_ = pairContract.reserve1();

        if (tokenA == token0_ && tokenB == token1_) {
            return (reserve0_, reserve1_);
        }

        if (tokenA == token1_ && tokenB == token0_) {
            return (reserve1_, reserve0_);
        }

        revert InvalidToken();
    }
}
