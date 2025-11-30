# Decentralized AMM with NFT LP Positions

A comprehensive automated market maker (AMM) implementation on Sui blockchain featuring NFT-based liquidity provider positions, constant product formula (x*y=k), StableSwap pools, fee distribution, and slippage protection.

## Features

### Core AMM Functionality
- **Constant Product Formula (x*y=k)**: Standard Uniswap V2-style AMM math
- **StableSwap Pools**: Optimized for stable asset pairs with amplification coefficient
- **Multi-tier Fee Structure**: 0.05% (stable), 0.30% (standard), 1.00% (exotic)
- **Protocol Fee Collection**: 10% of trading fees go to protocol

### NFT LP Positions
- **Transferable Positions**: LP positions represented as NFTs with `store` ability
- **Dynamic Metadata**: Track shares, fees, initial deposits, and creation time
- **Impermanent Loss Calculation**: Built-in IL tracking vs HODL
- **Position Value Calculation**: Real-time underlying token value
- **Accumulated Fee Tracking**: View pending and claimed fees

### Slippage Protection
- **Minimum Output Enforcement**: Protect against price manipulation
- **Price Impact Calculation**: Preview trade impact before execution
- **Deadline Enforcement**: Epoch-based transaction expiry
- **Configurable Tolerance**: Default 0.5%, max 50%

### Fee Distribution
- **Pro-rata Distribution**: Fees distributed proportionally to LP shares
- **Global Fee Indices**: Efficient fee accumulation without iteration
- **Auto-compound Option**: Reinvest fees back into position
- **Claim Anytime**: LPs can claim accumulated fees at will

## Smart Contracts

| Contract | Purpose |
|----------|---------|
| `pool_factory` | Create and manage liquidity pools with fee tier management |
| `liquidity_pool` | Core AMM logic with constant product formula |
| `stable_swap_pool` | Optimized AMM for stable asset pairs |
| `lp_position_nft` | NFT-based representation of LP positions |
| `fee_distributor` | Fee collection and distribution to LPs |
| `slippage_protection` | Slippage management and deadline enforcement |
| `amm_router` | Orchestrator for common AMM workflows |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       AMM Router                            │
│  (Orchestrates pool creation, liquidity, swaps, fees)       │
└─────────────────┬───────────────────────────────────────────┘
                  │
    ┌─────────────┼─────────────┬─────────────┬───────────────┐
    │             │             │             │               │
    ▼             ▼             ▼             ▼               ▼
┌─────────┐ ┌──────────┐ ┌───────────┐ ┌──────────┐ ┌─────────────┐
│  Pool   │ │ Liquidity│ │  Stable   │ │   LP     │ │    Fee      │
│ Factory │ │   Pool   │ │   Swap    │ │ Position │ │ Distributor │
└─────────┘ └──────────┘ └───────────┘ │   NFT    │ └─────────────┘
                                       └──────────┘
                                             │
                                             ▼
                                    ┌─────────────────┐
                                    │    Slippage     │
                                    │   Protection    │
                                    └─────────────────┘
```

## Getting Started

### Prerequisites
- [Sui CLI](https://docs.sui.io/build/install) installed
- Sui wallet with testnet/devnet SUI

### Build
```bash
cd sui-amm-nft-lp
sui move build
```

### Test
```bash
sui move test
```

### Deploy (Testnet)
```bash
sui client publish --gas-budget 100000000
```

## Core Workflows

### 1. Pool Creation
```move
// Create pool via factory with 0.30% fee tier
let pool = pool_factory::create_pool<CoinA, CoinB>(factory, 30, ctx);

// Provide initial liquidity
let shares = liquidity_pool::provide_initial_liquidity(&mut pool, amount_a, amount_b);

// Mint LP position NFT
lp_position_nft::mint(pool_id, shares, idx_a, idx_b, amount_a, amount_b, recipient, ctx);
```

### 2. Add Liquidity
```move
// Add liquidity with ratio tolerance (50 bps = 0.5%)
let new_shares = amm_router::add_liquidity_with_nft(
    &mut pool,
    &mut position,
    amount_a,
    amount_b,
    50, // tolerance_bps
);
```

### 3. Swap Tokens
```move
// Swap with slippage protection
let (amount_out, fee) = liquidity_pool::swap_with_slippage(
    &mut pool,
    amount_in,
    min_amount_out,
    true, // a_to_b
);

// Or use auto-slippage calculation
let (amount_out, fee) = amm_router::swap_with_auto_slippage(
    &mut pool,
    amount_in,
    50, // 0.5% slippage tolerance
    true,
);
```

### 4. Claim Fees
```move
// Claim accumulated fees
let (claimed_a, claimed_b) = amm_router::claim_fees_for_position(
    &mut fee_dist,
    &pool,
    &mut position,
);

// Or auto-compound fees back into position
let (new_shares, comp_a, comp_b) = amm_router::claim_and_compound(
    &mut fee_dist,
    &mut pool,
    &mut position,
    50, // tolerance
);
```

### 5. Remove Liquidity
```move
// Remove liquidity with slippage protection
let (out_a, out_b) = amm_router::remove_liquidity_with_slippage(
    &mut pool,
    &mut position,
    shares_to_burn,
    min_amount_a,
    min_amount_b,
);
```

## Events

| Event | Description |
|-------|-------------|
| `PoolCreated` | New pool created via factory |
| `LiquidityAdded` | Liquidity added to pool |
| `LiquidityRemoved` | Liquidity removed from pool |
| `SwapExecuted` | Token swap completed |
| `PositionMinted` | New LP position NFT created |
| `PositionBurned` | LP position NFT destroyed |
| `FeesClaimed` | Fees claimed from position |
| `FeesCompounded` | Fees auto-compounded |
| `SharesUpdated` | Position shares changed |

## Fee Tiers

| Tier | Fee (BPS) | Fee (%) | Use Case |
|------|-----------|---------|----------|
| Low | 5 | 0.05% | Stable pairs (USDC/USDT) |
| Medium | 30 | 0.30% | Standard pairs (ETH/SUI) |
| High | 100 | 1.00% | Exotic/volatile pairs |

## Testing

The test suite covers:

- **AMM Math Tests**: LP share proportionality, output calculations
- **Liquidity Tests**: Add/remove liquidity ratio checks
- **Swap Tests**: Fee calculation, output math verification
- **Slippage Tests**: Price impact calculations, enforcement
- **Router Tests**: Integration workflow sanity checks

```bash
# Run all tests
sui move test

# Run specific test
sui move test --filter amm_math
```

## Demo Interfaces

### CLI Demo
```bash
cd cli
npm install
node index.js
```

### Web Demo
Open `web/index.html` in a browser for an interactive AMM simulator.

## Project Structure

```
sui-amm-nft-lp/
├── Move.toml                 # Package manifest
├── sources/
│   ├── liquidity_pool.move   # Core AMM logic
│   ├── pool_factory.move     # Pool creation & registry
│   ├── stable_swap_pool.move # StableSwap implementation
│   ├── lp_position_nft.move  # LP position NFTs
│   ├── fee_distributor.move  # Fee distribution
│   ├── slippage_protection.move # Slippage helpers
│   └── amm_router.move       # Workflow orchestration
├── tests/
│   ├── amm_math_tests.move   # Math unit tests
│   ├── liquidity_pool_tests.move
│   ├── amm_e2e_tests.move    # Integration tests
│   └── amm_router_tests.move
├── cli/                      # Node.js CLI demo
├── web/                      # Browser demo
└── SECURITY_CHECKLIST.md     # Security audit checklist
```

## Security Considerations

See [SECURITY_CHECKLIST.md](./SECURITY_CHECKLIST.md) for the full security audit checklist.

Key security features:
- **Minimum Liquidity Lock**: First 1000 shares permanently locked
- **Slippage Protection**: Configurable bounds with max 50%
- **Overflow Protection**: u128 arithmetic for large values
- **Access Control**: Protocol fee withdrawal restricted


