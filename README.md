# sUSD3 Compounder Strategy

A Yearn V3 tokenized strategy that compounds sUSD3 staking yield for USDC depositors.

**Fund flow:** USDC → USD3 → sUSD3. Yield accrues through sUSD3 share price appreciation.

## Setup

Install [Foundry](https://book.getfoundry.sh/getting-started/installation), then:

```sh
git clone --recursive https://github.com/3jane/susd3-strategy
cd susd3-strategy
cp .env.example .env  # add ETH_RPC_URL
```

## Build & Test

See [Makefile](Makefile) for all targets. Key ones:

```sh
make build              # compile
make test-unit          # unit tests (no RPC needed)
make test               # unit + fork tests (requires ETH_RPC_URL)
make lint               # forge lint
make format             # forge fmt
make coverage-html      # HTML coverage report
```

Unit tests use mocked contracts etched at mainnet addresses. Fork tests (`ForkOperation.t.sol`) run against real mainnet contracts at a pinned block.

## Architecture

- **`Strategy.sol`** — Extends `Base4626Compounder`. Overrides staking hooks, deposit/withdraw limits. USDC/USD3/sUSD3 addresses are hardcoded constants.
- **`Base4626Compounder`** (in `@periphery/`) — Handles deploy/free funds, harvest, and emergency withdraw.

See [AGENTS.md](AGENTS.md) for full architecture docs.

## Security Considerations

- **sUSD3 lock reset on tend/report**: Every `_stake()` call (via `tend()` or `report()`) resets the sUSD3 30-day lock period. Both entry points are gated by `onlyKeepers`. The keeper MUST NOT be set to a permissionless relayer (e.g. `0x52605BbF54845f520a3E94792d019f62407db2f8`) or an attacker could grief the lock by repeatedly calling `tend()`.

## CI

GitHub Actions workflows: [test](.github/workflows/test.yml), [lint](.github/workflows/lint.yaml), [coverage](.github/workflows/coverage.yml), [slither](.github/workflows/slither.yml).

Requires `ETH_RPC_URL` secret for fork tests and coverage. Optionally add `GH_TOKEN` for PR coverage comments.
