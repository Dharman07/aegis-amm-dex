// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {AMMFactory} from "../core/AMMFactory.sol";
import {AMMPair} from "../core/AMMPair.sol";
import {AMMLibrary} from "../libraries/AMMLibrary.sol";
import {LPToken} from "../token/LPToken.sol";

contract AMMRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    AMMFactory public immutable factory;

    error ZeroAddress();
    error IdenticalTokens();
    error InvalidRecipient();
    error InvalidPath();
    error PairNotFound();
    error Expired();
    error InsufficientAAmount();
    error InsufficientBAmount();
    error InsufficientOutputAmount();
    error ExcessiveInputAmount();

    event LiquidityAdded(
        address indexed sender,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity,
        address recipient
    );

    event LiquidityRemoved(
        address indexed sender,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity,
        address recipient
    );

    event TokensSwapped(
        address indexed sender,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) {
            revert Expired();
        }
        _;
    }

    constructor(address factory_) {
        if (factory_ == address(0) || factory_.code.length == 0) {
            revert ZeroAddress();
        }

        factory = AMMFactory(factory_);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address recipient,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        _validateTokens(tokenA, tokenB);
        _validateRecipient(recipient);

        if (amountADesired == 0 || amountBDesired == 0) {
            revert InsufficientAAmount();
        }

        address pair = _getOrCreatePair(tokenA, tokenB);

        (uint256 reserveA, uint256 reserveB) = AMMLibrary.getReserves(pair, tokenA, tokenB);

        (amountA, amountB) = _calculateLiquidityAmounts(amountADesired, amountBDesired, reserveA, reserveB);

        if (amountA < amountAMin) {
            revert InsufficientAAmount();
        }

        if (amountB < amountBMin) {
            revert InsufficientBAmount();
        }

        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountADesired);

        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountBDesired);

        (uint256 amount0, uint256 amount1) = _sortAmounts(pair, tokenA, amountA, amountB);

        IERC20 token0 = AMMPair(pair).token0();
        IERC20 token1 = AMMPair(pair).token1();

        token0.forceApprove(pair, amount0);
        token1.forceApprove(pair, amount1);

        uint256 actual0;
        uint256 actual1;

        (actual0, actual1, liquidity) = AMMPair(pair)
            .addLiquidity(
                amount0,
                amount1,
                _sortMinimum(pair, tokenA, amountAMin, amountBMin),
                _sortMinimum(pair, tokenA, amountBMin, amountAMin),
                recipient
            );

        token0.forceApprove(pair, 0);
        token1.forceApprove(pair, 0);

        amountA = tokenA == address(token0) ? actual0 : actual1;
        amountB = tokenA == address(token0) ? actual1 : actual0;

        if (amountADesired > amountA) {
            IERC20(tokenA).safeTransfer(msg.sender, amountADesired - amountA);
        }

        if (amountBDesired > amountB) {
            IERC20(tokenB).safeTransfer(msg.sender, amountBDesired - amountB);
        }

        emit LiquidityAdded(msg.sender, tokenA, tokenB, amountA, amountB, liquidity, recipient);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address recipient,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        _validateTokens(tokenA, tokenB);
        _validateRecipient(recipient);

        if (liquidity == 0) {
            revert InsufficientOutputAmount();
        }

        address pair = factory.getPair(tokenA, tokenB);

        if (pair == address(0)) {
            revert PairNotFound();
        }

        LPToken lpToken = AMMPair(pair).lpToken();

        IERC20(address(lpToken)).safeTransferFrom(msg.sender, address(this), liquidity);

        (uint256 amount0Min, uint256 amount1Min) = _sortAmounts(pair, tokenA, amountAMin, amountBMin);

        (uint256 amount0, uint256 amount1) = AMMPair(pair).removeLiquidity(liquidity, amount0Min, amount1Min, recipient);

        IERC20 token0 = AMMPair(pair).token0();

        amountA = tokenA == address(token0) ? amount0 : amount1;
        amountB = tokenA == address(token0) ? amount1 : amount0;

        emit LiquidityRemoved(msg.sender, tokenA, tokenB, amountA, amountB, liquidity, recipient);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address recipient,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        _validatePath(path);
        _validateRecipient(recipient);

        if (amountIn == 0) {
            revert InsufficientAAmount();
        }

        amounts = getAmountsOut(amountIn, path);

        if (amounts[amounts.length - 1] < amountOutMin) {
            revert InsufficientOutputAmount();
        }

        address firstPair = factory.getPair(path[0], path[1]);

        IERC20(path[0]).safeTransferFrom(msg.sender, firstPair, amounts[0]);

        _swap(amounts, path, recipient);

        emit TokensSwapped(
            msg.sender, path[0], path[path.length - 1], amounts[0], amounts[amounts.length - 1], recipient
        );
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address recipient,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        _validatePath(path);
        _validateRecipient(recipient);

        if (amountOut == 0) {
            revert InsufficientOutputAmount();
        }

        amounts = getAmountsIn(amountOut, path);

        if (amounts[0] > amountInMax) {
            revert ExcessiveInputAmount();
        }

        address firstPair = factory.getPair(path[0], path[1]);

        IERC20(path[0]).safeTransferFrom(msg.sender, firstPair, amounts[0]);

        _swap(amounts, path, recipient);

        emit TokensSwapped(
            msg.sender, path[0], path[path.length - 1], amounts[0], amounts[amounts.length - 1], recipient
        );
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
        _validatePath(path);

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i; i < path.length - 1; ++i) {
            address pair = factory.getPair(path[i], path[i + 1]);

            if (pair == address(0)) {
                revert PairNotFound();
            }

            (uint256 reserveIn, uint256 reserveOut) = AMMLibrary.getReserves(pair, path[i], path[i + 1]);

            amounts[i + 1] = AMMLibrary.getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts) {
        _validatePath(path);

        amounts = new uint256[](path.length);
        amounts[path.length - 1] = amountOut;

        for (uint256 i = path.length - 1; i > 0; --i) {
            address pair = factory.getPair(path[i - 1], path[i]);

            if (pair == address(0)) {
                revert PairNotFound();
            }

            (uint256 reserveIn, uint256 reserveOut) = AMMLibrary.getReserves(pair, path[i - 1], path[i]);

            amounts[i - 1] = AMMLibrary.getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }

    function _swap(uint256[] memory amounts, address[] calldata path, address finalRecipient) internal {
        for (uint256 i; i < path.length - 1; ++i) {
            address input = path[i];
            address output = path[i + 1];

            address pair = factory.getPair(input, output);

            if (pair == address(0)) {
                revert PairNotFound();
            }

            (uint256 amount0Out, uint256 amount1Out) = _getOutputAmounts(pair, input, amounts[i + 1]);

            address recipient;

            if (i < path.length - 2) {
                recipient = factory.getPair(output, path[i + 2]);

                if (recipient == address(0)) {
                    revert PairNotFound();
                }
            } else {
                recipient = finalRecipient;
            }

            AMMPair(pair).swap(amount0Out, amount1Out, recipient);
        }
    }

    function _calculateLiquidityAmounts(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountA, uint256 amountB) {
        if (reserveA == 0 && reserveB == 0) {
            return (amountADesired, amountBDesired);
        }

        uint256 amountBOptimal = AMMLibrary.quote(amountADesired, reserveA, reserveB);

        if (amountBOptimal <= amountBDesired) {
            return (amountADesired, amountBOptimal);
        }

        uint256 amountAOptimal = AMMLibrary.quote(amountBDesired, reserveB, reserveA);

        return (amountAOptimal, amountBDesired);
    }

    function _getOrCreatePair(address tokenA, address tokenB) internal returns (address pair) {
        pair = factory.getPair(tokenA, tokenB);

        if (pair == address(0)) {
            pair = factory.createPair(tokenA, tokenB);
        }
    }

    function _validateTokens(address tokenA, address tokenB) internal pure {
        if (tokenA == address(0) || tokenB == address(0)) {
            revert ZeroAddress();
        }

        if (tokenA == tokenB) {
            revert IdenticalTokens();
        }
    }

    function _validateRecipient(address recipient) internal view {
        if (recipient == address(0) || recipient == address(this)) {
            revert InvalidRecipient();
        }
    }

    function _validatePath(address[] memory path) internal pure {
        if (path.length < 2) {
            revert InvalidPath();
        }

        for (uint256 i; i < path.length; ++i) {
            if (path[i] == address(0)) {
                revert InvalidPath();
            }

            if (i > 0 && path[i] == path[i - 1]) {
                revert InvalidPath();
            }
        }
    }

    function _sortAmounts(address pair, address tokenA, uint256 amountA, uint256 amountB)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        address token0 = address(AMMPair(pair).token0());

        if (tokenA == token0) {
            return (amountA, amountB);
        }

        return (amountB, amountA);
    }

    function _sortMinimum(address pair, address tokenA, uint256 amount0, uint256 amount1)
        internal
        view
        returns (uint256)
    {
        address token0 = address(AMMPair(pair).token0());

        return tokenA == token0 ? amount0 : amount1;
    }

    function _getOutputAmounts(address pair, address input, uint256 amountOut)
        internal
        view
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        address token0 = address(AMMPair(pair).token0());

        if (input == token0) {
            return (0, amountOut);
        }

        return (amountOut, 0);
    }
}
