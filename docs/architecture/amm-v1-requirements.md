# Aegis AMM DEX — V1 Requirements

## 1. Objective

Build a non-upgradeable, Uniswap V2-style constant-product AMM
using Solidity and Foundry.

## 2. V1 Scope

- Permissionless pool creation through a factory.
- One pool per unique token pair.
- ERC-20 token swaps.
- Liquidity addition and removal.
- ERC-20 liquidity provider (LP) shares.
- Slippage protection for swaps and liquidity operations.
- Deadline validation for user transactions.
- Unit, fuzz, invariant, and integration tests.

## 3. Initial Technical Baseline

- Solidity: 0.8.30
- Development framework: Foundry
- Pool model: Constant product, x * y = k
- Initial swap fee proposal: 0.30%
- Fee formula and LP accounting must be specified before implementation.
- Contracts are non-upgradeable for V1.

## 4. Token Compatibility

Initial support is limited to conventional ERC-20 tokens.

Fee-on-transfer, rebasing, callback-enabled, and otherwise non-standard
tokens are not guaranteed to be supported. Token compatibility must be
documented and tested.

## 5. Security Requirements

- Validate addresses and amounts.
- Reject identical token pairs and zero addresses.
- Prevent duplicate pools.
- Follow checks-effects-interactions where applicable.
- Protect sensitive external-call flows against reentrancy.
- Use safe ERC-20 transfer handling.
- Enforce minimum output and minimum liquidity-share constraints.
- Prevent invalid reserve updates and division-by-zero.
- Handle integer rounding explicitly.
- Avoid relying on untrusted token metadata for core accounting.

## 6. Required Pool Invariants

- Pool token addresses are distinct and non-zero.
- Recorded reserves match the supported token-balance accounting model.
- Swaps cannot violate the fee-adjusted constant-product invariant.
- LP share accounting remains internally consistent.
- A failed operation must revert without partially applying state changes.
- Factory mappings must identify the correct pool for each token pair.

## 7. Testing Requirements

- Unit tests for successful and failing operations.
- Fuzz tests for amounts, reserves, and token-pair inputs.
- Invariant tests for pool accounting and LP shares.
- Integration tests covering factory, pool, and mock ERC-20 tokens.
- Regression tests for every discovered bug.
- Gas measurements for critical operations.

## 8. Explicit V1 Limitations

- No flash swaps in the initial implementation.
- No protocol-fee mechanism unless added through a documented design change.
- No upgradeability.
- No guarantee of compatibility with non-standard ERC-20 tokens.
- No production deployment claim before security review and audit.

## 9. Design Decisions Still Requiring Review

- Exact swap-fee arithmetic and rounding policy.
- Initial LP-share formula and minimum-liquidity policy.
- Reserve synchronization and donation handling.
- Pool initialization and reentrancy boundaries.
- Whether any protocol fee is needed in V1.
