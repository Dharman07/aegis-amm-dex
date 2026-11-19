pragma solidity ^0.8.30;

interface IFlashSwapCallback {
    function aegisCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
