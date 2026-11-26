pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library FeeLibrary {
    function calculateProtocolFeeLiquidity(uint256 totalSupply, uint256 reserve0, uint256 reserve1, uint256 kLast)
        internal
        pure
        returns (uint256 liquidity)
    {
        if (kLast == 0 || totalSupply == 0) {
            return 0;
        }

        uint256 rootK = Math.sqrt(reserve0 * reserve1);

        uint256 rootKLast = Math.sqrt(kLast);

        if (rootK <= rootKLast) {
            return 0;
        }

        uint256 numerator = rootK - rootKLast;

        uint256 denominator = (rootK * 5) + rootKLast;

        liquidity = Math.mulDiv(totalSupply, numerator, denominator);
    }
}
