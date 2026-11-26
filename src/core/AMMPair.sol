pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IEmergencyControl} from "../interfaces/IEmergencyControl.sol";
import {FeeLibrary} from "../fees/FeeLibrary.sol";

import {LPToken} from "../token/LPToken.sol";
import {IFlashSwapCallback} from "../flash/interfaces/IFlashSwapCallback.sol";

interface IAMMFactoryFeeConfig {
    function feeTo() external view returns (address);
}

contract AMMPair is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable factory;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    LPToken public immutable lpToken;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public kLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    IEmergencyControl public immutable emergencyControl;

    bytes32 public constant SWAP_OPERATION = keccak256("SWAP");

    bytes32 public constant ADD_LIQUIDITY_OPERATION = keccak256("ADD_LIQUIDITY");

    uint32 public blockTimestampLast;

    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    uint256 public constant MAX_RESERVE = type(uint112).max;

    error ZeroAddress();
    error IdenticalTokens();
    error InvalidToken();
    error InsufficientLiquidity();
    error InsufficientAmount();
    error Unauthorized();
    error InvalidRecipient();
    error InsufficientLiquidityMinted();
    error InsufficientAmountReceived();
    error InsufficientOutputAmount();
    error InsufficientInputAmount();
    error InsufficientBalance();
    error KInvariant();
    error ReserveOverflow();
    error OperationPaused(bytes32 operation);

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

    constructor(address token0_, address token1_, address emergencyControl_) {
        factory = msg.sender;

        if (token0_ == address(0) || token1_ == address(0)) {
            revert ZeroAddress();
        }

        if (token0_ == token1_) {
            revert IdenticalTokens();
        }

        if (token0_.code.length == 0 || token1_.code.length == 0) {
            revert InvalidToken();
        }

        if (emergencyControl_ == address(0) || emergencyControl_.code.length == 0) {
            revert ZeroAddress();
        }

        emergencyControl = IEmergencyControl(emergencyControl_);

        token0 = IERC20(token0_);
        token1 = IERC20(token1_);

        lpToken = new LPToken("Aegis AMM LP Token", "AAG-LP", address(this));
    }

    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient
    ) external nonReentrant returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        _checkOperation(ADD_LIQUIDITY_OPERATION);

        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        if (amount0Desired == 0 || amount1Desired == 0) {
            revert InsufficientAmount();
        }

        bool feeOn = _mintFee(reserve0, reserve1);

        (amount0, amount1) = _calculateLiquidityAmounts(amount0Desired, amount1Desired);

        if (amount0 < amount0Min || amount1 < amount1Min) {
            revert InsufficientAmountReceived();
        }

        uint256 balance0Before = token0.balanceOf(address(this));

        uint256 balance1Before = token1.balanceOf(address(this));

        token0.safeTransferFrom(msg.sender, address(this), amount0);

        token1.safeTransferFrom(msg.sender, address(this), amount1);

        uint256 balance0After = token0.balanceOf(address(this));

        uint256 balance1After = token1.balanceOf(address(this));

        uint256 amount0Received = balance0After - balance0Before;

        uint256 amount1Received = balance1After - balance1Before;

        if (amount0Received < amount0Min || amount1Received < amount1Min) {
            revert InsufficientAmountReceived();
        }

        if (balance0After > MAX_RESERVE || balance1After > MAX_RESERVE) {
            revert ReserveOverflow();
        }

        liquidity = _calculateLiquidityMint(amount0Received, amount1Received);

        if (liquidity == 0) {
            revert InsufficientLiquidityMinted();
        }

        _updateReserves(balance0After, balance1After);

        _updateKLast(feeOn);

        lpToken.mint(recipient, liquidity);

        emit Mint(msg.sender, amount0Received, amount1Received, recipient);

        amount0 = amount0Received;
        amount1 = amount1Received;
    }

    function removeLiquidity(uint256 liquidity, uint256 amount0Min, uint256 amount1Min, address recipient)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (
            recipient == address(0) || recipient == address(this) || recipient == address(token0)
                || recipient == address(token1)
        ) {
            revert InvalidRecipient();
        }

        if (liquidity == 0) {
            revert InsufficientAmount();
        }

        bool feeOn = _mintFee(reserve0, reserve1);

        uint256 totalSupply = lpToken.totalSupply();

        if (totalSupply == 0) {
            revert InsufficientLiquidity();
        }

        uint256 reserve0Before = reserve0;
        uint256 reserve1Before = reserve1;

        amount0 = Math.mulDiv(liquidity, reserve0Before, totalSupply);

        amount1 = Math.mulDiv(liquidity, reserve1Before, totalSupply);

        if (amount0 < amount0Min || amount1 < amount1Min) {
            revert InsufficientAmountReceived();
        }

        lpToken.burn(msg.sender, liquidity);

        token0.safeTransfer(recipient, amount0);

        token1.safeTransfer(recipient, amount1);

        uint256 balance0After = token0.balanceOf(address(this));

        uint256 balance1After = token1.balanceOf(address(this));

        _updateReserves(balance0After, balance1After);

        _updateKLast(feeOn);

        emit Burn(msg.sender, recipient, amount0, amount1, liquidity);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address recipient) external nonReentrant {
        _swap(amount0Out, amount1Out, recipient, bytes(""), msg.sender);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address recipient, bytes calldata data)
        external
        nonReentrant
    {
        _swap(amount0Out, amount1Out, recipient, data, msg.sender);
    }

    function _swap(uint256 amount0Out, uint256 amount1Out, address recipient, bytes memory data, address sender)
        internal
    {
        _checkOperation(SWAP_OPERATION);

        if (
            recipient == address(0) || recipient == address(this) || recipient == address(token0)
                || recipient == address(token1)
        ) {
            revert InvalidRecipient();
        }

        if (amount0Out == 0 && amount1Out == 0) {
            revert InsufficientOutputAmount();
        }

        uint256 reserve0Before = reserve0;
        uint256 reserve1Before = reserve1;

        if (amount0Out >= reserve0Before || amount1Out >= reserve1Before) {
            revert InsufficientLiquidity();
        }

        if (amount0Out > 0) {
            token0.safeTransfer(recipient, amount0Out);
        }

        if (amount1Out > 0) {
            token1.safeTransfer(recipient, amount1Out);
        }

        if (data.length > 0) {
            if (recipient.code.length == 0) {
                revert InvalidRecipient();
            }

            IFlashSwapCallback(recipient).aegisCall(sender, amount0Out, amount1Out, data);
        }

        uint256 balance0 = token0.balanceOf(address(this));

        uint256 balance1 = token1.balanceOf(address(this));

        if (balance0 > MAX_RESERVE || balance1 > MAX_RESERVE) {
            revert ReserveOverflow();
        }

        uint256 amount0In = balance0 > reserve0Before - amount0Out ? balance0 - (reserve0Before - amount0Out) : 0;

        uint256 amount1In = balance1 > reserve1Before - amount1Out ? balance1 - (reserve1Before - amount1Out) : 0;

        if (amount0In == 0 && amount1In == 0) {
            revert InsufficientInputAmount();
        }

        uint256 balance0Adjusted = balance0 * FEE_DENOMINATOR - amount0In * (FEE_DENOMINATOR - FEE_NUMERATOR);

        uint256 balance1Adjusted = balance1 * FEE_DENOMINATOR - amount1In * (FEE_DENOMINATOR - FEE_NUMERATOR);

        if (balance0Adjusted * balance1Adjusted < reserve0Before * reserve1Before * FEE_DENOMINATOR * FEE_DENOMINATOR) {
            revert KInvariant();
        }

        _updateReserves(balance0, balance1);

        emit Swap(sender, amount0In, amount1In, amount0Out, amount1Out, recipient);
    }

    function _calculateLiquidityAmounts(uint256 amount0Desired, uint256 amount1Desired)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        if (reserve0 == 0 && reserve1 == 0) {
            return (amount0Desired, amount1Desired);
        }

        if (reserve0 == 0 || reserve1 == 0) {
            revert InsufficientLiquidity();
        }

        uint256 amount1Optimal = Math.mulDiv(amount0Desired, reserve1, reserve0);

        if (amount1Optimal <= amount1Desired) {
            return (amount0Desired, amount1Optimal);
        }

        uint256 amount0Optimal = Math.mulDiv(amount1Desired, reserve0, reserve1);

        return (amount0Optimal, amount1Desired);
    }

    function _calculateLiquidityMint(uint256 amount0, uint256 amount1) internal returns (uint256 liquidity) {
        uint256 totalSupply = lpToken.totalSupply();

        if (totalSupply == 0) {
            uint256 initialLiquidity = Math.sqrt(amount0 * amount1);

            if (initialLiquidity <= MINIMUM_LIQUIDITY) {
                revert InsufficientLiquidityMinted();
            }

            // Permanently lock minimum liquidity.

            lpToken.mint(address(0x000000000000000000000000000000000000dEaD), MINIMUM_LIQUIDITY);

            return initialLiquidity - MINIMUM_LIQUIDITY;
        }

        if (reserve0 == 0 || reserve1 == 0) {
            revert InsufficientLiquidity();
        }

        uint256 liquidity0 = Math.mulDiv(amount0, totalSupply, reserve0);

        uint256 liquidity1 = Math.mulDiv(amount1, totalSupply, reserve1);

        liquidity = _min(liquidity0, liquidity1);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _mintFee(uint256 reserve0_, uint256 reserve1_) internal returns (bool feeOn) {
        address feeRecipient;

        try IAMMFactoryFeeConfig(factory).feeTo() returns (address recipient) {
            feeRecipient = recipient;
        } catch {
            feeRecipient = address(0);
        }

        feeOn = feeRecipient != address(0);

        uint256 _kLast = kLast;

        if (feeOn) {
            if (_kLast != 0) {
                uint256 liquidity =
                    FeeLibrary.calculateProtocolFeeLiquidity(lpToken.totalSupply(), reserve0_, reserve1_, _kLast);

                if (liquidity > 0) {
                    lpToken.mint(feeRecipient, liquidity);

                    emit ProtocolFeeMinter(feeRecipient, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function _updateKLast(bool feeOn) internal {
        if (feeOn) {
            kLast = reserve0 * reserve1;
        }
    }

    function _updateReserves(uint256 balance0, uint256 balance1) internal {
        if (balance0 > MAX_RESERVE || balance1 > MAX_RESERVE) {
            revert ReserveOverflow();
        }

        uint32 blockTimestamp = uint32(block.timestamp);

        uint32 timeElapsed;

        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast;
        }

        if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            uint256 price0 = (reserve1 << 112) / reserve0;

            uint256 price1 = (reserve0 << 112) / reserve1;

            unchecked {
                price0CumulativeLast += price0 * timeElapsed;

                price1CumulativeLast += price1 * timeElapsed;
            }
        }

        blockTimestampLast = blockTimestamp;

        reserve0 = balance0;
        reserve1 = balance1;

        emit Sync(reserve0, reserve1);
    }

    function sync() external nonReentrant {
        uint256 balance0 = token0.balanceOf(address(this));

        uint256 balance1 = token1.balanceOf(address(this));

        _updateReserves(balance0, balance1);
    }

    function skim(address recipient) external nonReentrant {
        if (
            recipient == address(0) || recipient == address(this) || recipient == address(token0)
                || recipient == address(token1)
        ) {
            revert InvalidRecipient();
        }

        uint256 balance0 = token0.balanceOf(address(this));

        uint256 balance1 = token1.balanceOf(address(this));

        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        if (amount0 > 0) {
            token0.safeTransfer(recipient, amount0);
        }

        if (amount1 > 0) {
            token1.safeTransfer(recipient, amount1);
        }

        emit Skim(msg.sender, recipient, amount0, amount1);
    }

    function _checkOperation(bytes32 operation) internal view {
        if (emergencyControl.isPaused(operation)) {
            revert OperationPaused(operation);
        }
    }
}
