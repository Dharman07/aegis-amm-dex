# Aegis AMM V1 — Math and Accounting

## 1. Swap Fee

Proposed fee: 0.30%.

Fee multiplier: 997 / 1000.

amountInWithFee = amountIn * 997

amountOut =
    (amountInWithFee * reserveOut) /
    (reserveIn * 1000 + amountInWithFee)

All calculations use integer arithmetic. Rounding is downward.

## 2. Constant Product

Before swap:

kBefore = reserveIn * reserveOut

After swap, the fee-adjusted invariant must not be violated.
The implementation and tests must verify this using overflow-safe
arithmetic and the exact integer formula.

## 3. Initial Liquidity

For the first liquidity deposit:

liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY

The minimum-liquidity policy and exact value must be reviewed before
implementation. The multiplication and square-root calculation must
be checked for overflow and rounding behavior.

## 4. Subsequent Liquidity

For existing reserves reserve0 and reserve1, the deposit must preserve
the pool's price ratio.

The LP shares minted must be based on the limiting deposit ratio,
rather than allowing an imbalanced deposit to mint excess shares.

The exact formula and rounding policy must be finalized in tests.

## 5. Liquidity Removal

Token amounts returned are proportional to the LP shares burned:

amount0 = liquidityBurned * reserve0 / totalSupply
amount1 = liquidityBurned * reserve1 / totalSupply

Integer division rounds down. Validate non-zero amounts and ensure
the total supply and reserves are consistent before executing.

## 6. Required Edge Cases

- Zero input and zero output.
- Empty pool and insufficient reserves.
- Tiny amounts that round to zero.
- Very large values and multiplication overflow.
- First liquidity deposit.
- Imbalanced subsequent deposits.
- LP share rounding and minimum-liquidity behavior.
- Swap slippage and expired deadline.
- Token transfer failure or reversion.
- Donations that make token balances differ from recorded reserves.

## 7. Implementation Gate

Do not implement production contracts until formulas, minimum-liquidity
policy, reserve accounting, and invariant tests are reviewed.
