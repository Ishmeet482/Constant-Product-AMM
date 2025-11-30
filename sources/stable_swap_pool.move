module sui_amm_nft_lp::stable_swap_pool {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::TxContext;
    use sui::event;

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════

    const BPS_DENOMINATOR: u64 = 10_000;

    /// Default amplification factor for stable pairs
    const DEFAULT_AMP_FACTOR: u64 = 100;

    /// Maximum amplification factor
    const MAX_AMP_FACTOR: u64 = 10_000;

    /// Default fee for stable swaps (0.04%)
    const DEFAULT_FEE_BPS: u64 = 4;

    /// Maximum fee (1%)
    const MAX_FEE_BPS: u64 = 100;

    // ═══════════════════════════════════════════════════════════════════════════════
    // ERROR CODES
    // ═══════════════════════════════════════════════════════════════════════════════

    const E_INVALID_AMP: u64 = 1;
    const E_INVALID_FEE: u64 = 2;
    const E_ZERO_LIQUIDITY: u64 = 3;
    const E_INSUFFICIENT_LIQUIDITY: u64 = 4;
    const E_SLIPPAGE_EXCEEDED: u64 = 5;
    const E_ZERO_AMOUNT: u64 = 6;

    // ═══════════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// StableSwap pool optimized for similar-priced assets (stablecoins, wrapped assets)
    /// Uses a modified invariant that provides lower slippage for balanced trades
    struct StableSwapPool<phantom A, phantom B> has key {
        id: UID,
        /// Reserve of token A
        reserve_a: u64,
        /// Reserve of token B
        reserve_b: u64,
        /// Amplification coefficient (higher = more like constant-sum)
        amp_factor: u64,
        /// Trading fee in basis points
        fee_bps: u64,
        /// Total LP shares
        total_shares: u64,
        /// Global fee index for token A
        fee_index_a: u64,
        /// Global fee index for token B
        fee_index_b: u64,
        /// Protocol fees accumulated
        protocol_fees_a: u64,
        protocol_fees_b: u64,
        /// Cumulative volume
        cumulative_volume: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Emitted when a stable swap is executed
    struct StableSwapExecuted has copy, drop {
        pool_id: ID,
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        a_to_b: bool,
    }

    /// Emitted when liquidity is added to stable pool
    struct StableLiquidityAdded has copy, drop {
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
        shares_minted: u64,
    }

    /// Emitted when liquidity is removed from stable pool
    struct StableLiquidityRemoved has copy, drop {
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
        shares_burned: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL CREATION
    // ═══════════════════════════════════════════════════════════════════════════════

    public fun new_stable_pool<A, B>(
        amp_factor: u64,
        fee_bps: u64,
        ctx: &mut TxContext
    ): StableSwapPool<A, B> {
        assert!(amp_factor > 0 && amp_factor <= MAX_AMP_FACTOR, E_INVALID_AMP);
        assert!(fee_bps <= MAX_FEE_BPS, E_INVALID_FEE);

        StableSwapPool {
            id: object::new(ctx),
            reserve_a: 0,
            reserve_b: 0,
            amp_factor,
            fee_bps,
            total_shares: 0,
            fee_index_a: 0,
            fee_index_b: 0,
            protocol_fees_a: 0,
            protocol_fees_b: 0,
            cumulative_volume: 0,
        }
    }

    /// Create a stable pool with default parameters
    public fun new_stable_pool_default<A, B>(ctx: &mut TxContext): StableSwapPool<A, B> {
        new_stable_pool<A, B>(DEFAULT_AMP_FACTOR, DEFAULT_FEE_BPS, ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    public fun pool_id<A, B>(pool: &StableSwapPool<A, B>): ID {
        object::id(pool)
    }

    public fun reserves<A, B>(pool: &StableSwapPool<A, B>): (u64, u64) {
        (pool.reserve_a, pool.reserve_b)
    }

    public fun amp_factor<A, B>(pool: &StableSwapPool<A, B>): u64 {
        pool.amp_factor
    }

    public fun fee_bps<A, B>(pool: &StableSwapPool<A, B>): u64 {
        pool.fee_bps
    }

    public fun total_shares<A, B>(pool: &StableSwapPool<A, B>): u64 {
        pool.total_shares
    }

    public fun fee_indices<A, B>(pool: &StableSwapPool<A, B>): (u64, u64) {
        (pool.fee_index_a, pool.fee_index_b)
    }

    public fun cumulative_volume<A, B>(pool: &StableSwapPool<A, B>): u64 {
        pool.cumulative_volume
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // LIQUIDITY MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Provide initial liquidity to stable pool
    public fun provide_initial_liquidity<A, B>(
        pool: &mut StableSwapPool<A, B>,
        amount_a: u64,
        amount_b: u64,
    ): u64 {
        assert!(pool.total_shares == 0, E_ZERO_LIQUIDITY);
        assert!(amount_a > 0 && amount_b > 0, E_ZERO_AMOUNT);

        // For stable pools, initial shares = sum of deposits (assuming 1:1 pricing)
        let shares = amount_a + amount_b;

        pool.reserve_a = amount_a;
        pool.reserve_b = amount_b;
        pool.total_shares = shares;

        event::emit(StableLiquidityAdded {
            pool_id: object::id(pool),
            amount_a,
            amount_b,
            shares_minted: shares,
        });

        shares
    }

    /// Add liquidity to existing stable pool
    public fun add_liquidity<A, B>(
        pool: &mut StableSwapPool<A, B>,
        amount_a: u64,
        amount_b: u64,
    ): u64 {
        assert!(pool.total_shares > 0, E_ZERO_LIQUIDITY);
        assert!(amount_a > 0 || amount_b > 0, E_ZERO_AMOUNT);

        let total_reserve = pool.reserve_a + pool.reserve_b;
        let deposit_value = amount_a + amount_b;

        // Shares proportional to deposit value vs total value
        let shares = (deposit_value * pool.total_shares) / total_reserve;

        pool.reserve_a = pool.reserve_a + amount_a;
        pool.reserve_b = pool.reserve_b + amount_b;
        pool.total_shares = pool.total_shares + shares;

        event::emit(StableLiquidityAdded {
            pool_id: object::id(pool),
            amount_a,
            amount_b,
            shares_minted: shares,
        });

        shares
    }

    /// Remove liquidity from stable pool
    public fun remove_liquidity<A, B>(
        pool: &mut StableSwapPool<A, B>,
        shares_to_burn: u64,
    ): (u64, u64) {
        assert!(shares_to_burn > 0, E_ZERO_AMOUNT);
        assert!(pool.total_shares >= shares_to_burn, E_INSUFFICIENT_LIQUIDITY);

        // Pro-rata share of reserves
        let amount_a = (shares_to_burn * pool.reserve_a) / pool.total_shares;
        let amount_b = (shares_to_burn * pool.reserve_b) / pool.total_shares;

        pool.reserve_a = pool.reserve_a - amount_a;
        pool.reserve_b = pool.reserve_b - amount_b;
        pool.total_shares = pool.total_shares - shares_to_burn;

        event::emit(StableLiquidityRemoved {
            pool_id: object::id(pool),
            amount_a,
            amount_b,
            shares_burned: shares_to_burn,
        });

        (amount_a, amount_b)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // SWAP FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Calculate output for a stable swap.
    /// Uses a weighted combination of constant-product and constant-sum formulas
    /// based on the amplification factor for low slippage on balanced trades.
    public fun get_amount_out<A, B>(
        pool: &StableSwapPool<A, B>,
        amount_in: u64,
        a_to_b: bool,
    ): (u64, u64) {
        assert!(amount_in > 0, E_ZERO_AMOUNT);

        let (reserve_in, reserve_out) = if (a_to_b) {
            (pool.reserve_a, pool.reserve_b)
        } else {
            (pool.reserve_b, pool.reserve_a)
        };

        assert!(reserve_in > 0 && reserve_out > 0, E_INSUFFICIENT_LIQUIDITY);

        // Apply fee
        let fee_amount = (amount_in * pool.fee_bps) / BPS_DENOMINATOR;
        let amount_in_after_fee = amount_in - fee_amount;

        // StableSwap formula: weighted average of constant-product and constant-sum
        // Higher amp_factor = more like constant-sum (1:1 output)
        // Lower amp_factor = more like constant-product

        // Constant product output
        let k = (reserve_in as u128) * (reserve_out as u128);
        let new_reserve_in = reserve_in + amount_in_after_fee;
        let new_reserve_out_cp = (k / (new_reserve_in as u128) as u64);
        let out_cp = reserve_out - new_reserve_out_cp;

        // Constant sum output (1:1)
        let out_cs = if (amount_in_after_fee <= reserve_out) {
            amount_in_after_fee
        } else {
            reserve_out
        };

        // Weighted average based on amplification
        // weight = A / (A + 1), where A = amp_factor
        let weight_num = pool.amp_factor;
        let weight_den = pool.amp_factor + 1;

        let out = (out_cs * weight_num) / weight_den + (out_cp * 1) / weight_den;

        // Ensure output doesn't exceed reserve
        let final_out = if (out > reserve_out) { reserve_out } else { out };

        (final_out, fee_amount)
    }

    /// Execute a stable swap
    public fun stable_swap<A, B>(
        pool: &mut StableSwapPool<A, B>,
        amount_in: u64,
        a_to_b: bool,
    ): u64 {
        let (amount_out, fee_amount) = get_amount_out(pool, amount_in, a_to_b);

        if (a_to_b) {
            pool.reserve_a = pool.reserve_a + amount_in;
            pool.reserve_b = pool.reserve_b - amount_out;
        } else {
            pool.reserve_b = pool.reserve_b + amount_in;
            pool.reserve_a = pool.reserve_a - amount_out;
        };

        // Accrue fees (90% to LPs, 10% to protocol)
        let proto_fee = fee_amount / 10;
        let lp_fee = fee_amount - proto_fee;

        if (a_to_b) {
            pool.protocol_fees_a = pool.protocol_fees_a + proto_fee;
            if (pool.total_shares > 0) {
                pool.fee_index_a = pool.fee_index_a + (lp_fee * BPS_DENOMINATOR) / pool.total_shares;
            };
        } else {
            pool.protocol_fees_b = pool.protocol_fees_b + proto_fee;
            if (pool.total_shares > 0) {
                pool.fee_index_b = pool.fee_index_b + (lp_fee * BPS_DENOMINATOR) / pool.total_shares;
            };
        };

        pool.cumulative_volume = pool.cumulative_volume + amount_in;

        event::emit(StableSwapExecuted {
            pool_id: object::id(pool),
            amount_in,
            amount_out,
            fee_amount,
            a_to_b,
        });

        amount_out
    }

    /// Execute swap with slippage protection
    public fun stable_swap_with_slippage<A, B>(
        pool: &mut StableSwapPool<A, B>,
        amount_in: u64,
        min_amount_out: u64,
        a_to_b: bool,
    ): u64 {
        let amount_out = stable_swap(pool, amount_in, a_to_b);
        assert!(amount_out >= min_amount_out, E_SLIPPAGE_EXCEEDED);
        amount_out
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Update amplification factor
    public fun set_amp_factor<A, B>(pool: &mut StableSwapPool<A, B>, new_amp: u64) {
        assert!(new_amp > 0 && new_amp <= MAX_AMP_FACTOR, E_INVALID_AMP);
        pool.amp_factor = new_amp;
    }

    /// Withdraw protocol fees
    public fun withdraw_protocol_fees<A, B>(pool: &mut StableSwapPool<A, B>): (u64, u64) {
        let fees_a = pool.protocol_fees_a;
        let fees_b = pool.protocol_fees_b;
        pool.protocol_fees_a = 0;
        pool.protocol_fees_b = 0;
        (fees_a, fees_b)
    }
}
