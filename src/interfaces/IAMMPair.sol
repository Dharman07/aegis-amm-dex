// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILPToken} from "./ILPToken.sol";

interface IAMMPair {
    // Events
    event Sync(uint256 reserve0, uint256 reserve1);

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);

    event Burn(address indexed sender, address indexed recipient, uint256 amount0, uint256 amount1, uint256 liquidity);

    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed recipient
    );

    event ProtocolFeeMinter(address indexed recipient, uint256 liquidity);

    event Skim(address indexed sender, address indexed recipient, uint256 amount0, uint256 amount1);

    function factory() external view returns (address);

    function token0() external view returns (IERC20);

    function token1() external view returns (IERC20);

    function lpToken() external view returns (ILPToken);

    function reserve0() external view returns (uint256);

    function reserve1() external view returns (uint256);

    function kLast() external view returns (uint256);

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function blockTimestampLast() external view returns (uint32);

    function FEE_NUMERATOR() external view returns (uint256);

    function FEE_DENOMINATOR() external view returns (uint256);

    function MINIMUM_LIQUIDITY() external view returns (uint256);

    function MAX_RESERVE() external view returns (uint256);

    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient
    ) external returns (uint256 amount0, uint256 amount1, uint256 liquidity);

    function removeLiquidity(uint256 liquidity, uint256 amount0Min, uint256 amount1Min, address recipient)
        external
        returns (uint256 amount0, uint256 amount1);

    function swap(uint256 amount0Out, uint256 amount1Out, address recipient) external;

    function swap(uint256 amount0Out, uint256 amount1Out, address recipient, bytes calldata data) external;

    function sync() external;

    function skim(address recipient) external;
}
