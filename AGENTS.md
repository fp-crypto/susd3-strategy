# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Build & Test

See @Makefile for all available targets. Key ones:

- `make build` — compile
- `make test` — unit tests (no fork) + fork tests (requires `ETH_RPC_URL`)
- `make test-unit` — unit tests only (no RPC needed)
- `make test-test test=test_functionName` — single test with traces
- `make lint` — forge lint
- `make format` — forge fmt

Fork tests (`ForkOperation.t.sol`) require `ETH_RPC_URL` and pin to a specific mainnet block. Unit tests use mocked contracts etched at mainnet addresses via `vm.etch`.

## Architecture

This is a **Yearn V3 tokenized strategy** that compounds sUSD3 staking yield using the `Base4626Compounder` pattern.

**Fund flow:** User USDC → `vault.deposit()` → USD3 shares → `staking.deposit()` → sUSD3 shares. Yield accrues through sUSD3 share price appreciation.

### Key contracts

- **`Strategy.sol`** — Extends `Base4626Compounder`. Overrides `_stake()`, `_unStake()`, `balanceOfStake()`, `vaultsMaxWithdraw()`, `availableDepositLimit()`. All three token addresses (USDC, USD3, sUSD3) are hardcoded constants. Constructor takes only a name.
- **`Base4626Compounder`** (in `@periphery/`) — Handles `_deployFunds` (deposit + stake), `_freeFunds` (unstake + redeem), `_harvestAndReport`, and `_emergencyWithdraw`. Strategy overrides the staking hooks.

### sUSD3 constraints

- **30-day lock period** on deposits (config-driven, resets on each `_stake()` call). Strategy accepts the rolling lock.
- **Cooldown** for withdrawals (currently 0, but config-driven). Management can call `startCooldown`/`cancelCooldown`.
- **Shutdown does NOT unlock staked funds** — sUSD3 enforces its own lock regardless of strategy state.
- `vaultsMaxWithdraw()` uses `staking.maxRedeem()` which encodes all lock/cooldown logic.
- **Keeper must not be permissionless** — `tend()` and `report()` both call `_stake()` which resets the sUSD3 lock. A permissionless keeper relayer would allow griefing.

### Deposit controls

- **Depositor whitelist** — `availableDepositLimit` returns 0 for non-whitelisted addresses.
- **sUSD3 subordination cap** — deposit limit bounded by `min(vault limit, sUSD3 remaining capacity in USDC)`.

## Conventions

- Use `previewRedeem` (not `convertToAssets`) for withdrawal-direction value conversions.
- Use `@inheritdoc` tags on all overridden functions, referencing the correct base contract (`Base4626Compounder` or `BaseStrategy`).
- Management functions use `onlyManagement` modifier; error string is `"!management"`.
- Use conventional commit format: `feat:`, `fix:`, `refactor:`, etc.

## Test setup

- **Unit tests** (`Setup.sol`): Deploy mock USD3/sUSD3/MorphoCredit from scratch, etch at hardcoded mainnet addresses. No RPC needed.
- **Fork tests** (`ForkSetup.sol`): Use real mainnet contracts at block 22089000. Require `ETH_RPC_URL`.
- `skipLockPeriod()` advances 91 days past the sUSD3 lock.
- Yield simulation: airdrop USD3 to sUSD3 → `susd3.report()` → skip `profitMaxUnlockTime` → `strategy.report()`.

## Dependencies

Managed as git submodules under `lib/`. Remappings in `foundry.toml`:
- `@tokenized-strategy/` — Yearn V3 base strategy (BaseStrategy, TokenizedStrategy)
- `@periphery/` — Base4626Compounder, BaseHealthCheck, AprOracleBase
- `@3jane/` — USD3, sUSD3, MorphoCredit, mocks
- `@openzeppelin/` — v4.9.5 (uses `Math.Rounding.Down`/`Up`, not `Floor`/`Ceil`)
