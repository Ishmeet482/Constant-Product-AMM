#[allow(unused_const, lint(public_entry), unused_use)]
module sui_amm_nft_lp::liquidity_pool {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::TxContext;
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::transfer;

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Fee denominator for basis points (1e4 = 100%)
    const BPS_DENOMINATOR: u64 = 10_000;

    /// Maximum fee allowed in basis points (e.g. 1000 = 10%)
    const MAX_FEE_BPS: u64 = 1_000;

    /// Protocol fee share in basis points (1000 = 10% of trading fees go to protocol)
    const PROTOCOL_FEE_BPS: u64 = 1_000;

    /// Minimum liquidity to prevent dust attacks
    const MINIMUM_LIQUIDITY: u64 = 1000;

    // ═══════════════════════════════════════════════════════════════════════════════
    // ERROR CODES
    // ═══════════════════════════════════════════════════════════════════════════════

    const E_INVALID_FEE: u64 = 1;
    const E_ZERO_LIQUIDITY: u64 = 2;
    const E_INSUFFICIENT_LIQUIDITY: u64 = 3;
    const E_INVALID_RATIO: u64 = 4;
    const E_ZERO_AMOUNT_IN: u64 = 5;
    const E_SLIPPAGE_EXCEEDED: u64 = 6;
    const E_K_INVARIANT_VIOLATED: u64 = 7;
    const E_OVERFLOW: u64 = 8;

    // ═══════════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Core AMM pool using constant product formula (x * y = k)
    struct LiquidityPool<phantom A, phantom B> has key {
        id: UID,
        /// Reserve of token A
        reserve_a: u64,
        /// Reserve of token B
        reserve_b: u64,
        /// Trading fee in basis points (e.g. 30 = 0.30%)
        fee_bps: u64,
        /// Total LP share supply
        total_shares: u64,
        /// Global fee index for token A (scaled by BPS_DENOMINATOR)
        fee_index_a: u64,
        /// Global fee index for token B (scaled by BPS_DENOMINATOR)
        fee_index_b: u64,
        /// Protocol fee reserves for token A
        protocol_fees_a: u64,
        /// Protocol fee reserves for token B
        protocol_fees_b: u64,
        /// Cumulative volume in token A (for analytics)
        cumulative_volume_a: u64,
        /// Cumulative volume in token B (for analytics)
        cumulative_volume_b: u64,
        /// K value cache for invariant checking
        k_last: u128,
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Emitted when liquidity is added to a pool
    struct LiquidityAdded has copy, drop {
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
        shares_minted: u64,
        total_shares: u64,
    }

    /// Emitted when liquidity is removed from a pool
    struct LiquidityRemoved has copy, drop {
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
        shares_burned: u64,
        total_shares: u64,
    }

    /// Emitted when a swap is executed
    struct SwapExecuted has copy, drop {
        pool_id: ID,
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        a_to_b: bool,
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL CREATION
    // ═══════════════════════════════════════════════════════════════════════════════

    public fun new_pool<A, B>(fee_bps: u64, ctx: &mut TxContext): LiquidityPool<A, B> {
        assert!(fee_bps <= MAX_FEE_BPS, E_INVALID_FEE);
        LiquidityPool {
            id: object::new(ctx),
            reserve_a: 0,
            reserve_b: 0,
            fee_bps,
            total_shares: 0,
            fee_index_a: 0,
            fee_index_b: 0,
            protocol_fees_a: 0,
            protocol_fees_b: 0,
            cumulative_volume_a: 0,
            cumulative_volume_b: 0,
            k_last: 0,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Returns the immutable ID of a pool, useful for binding LP positions.
    public fun pool_id<A, B>(pool: &LiquidityPool<A, B>): ID {
        object::id(pool)
    }

    /// Read-only view helpers.
    public fun reserves<A, B>(pool: &LiquidityPool<A, B>): (u64, u64) {
        (pool.reserve_a, pool.reserve_b)
    }

    public fun total_shares<A, B>(pool: &LiquidityPool<A, B>): u64 {
        pool.total_shares
    }

    public fun fee_bps<A, B>(pool: &LiquidityPool<A, B>): u64 {
        pool.fee_bps
    }

    public fun fee_indices<A, B>(pool: &LiquidityPool<A, B>): (u64, u64) {
        (pool.fee_index_a, pool.fee_index_b)
    }

    public fun protocol_fees<A, B>(pool: &LiquidityPool<A, B>): (u64, u64) {
        (pool.protocol_fees_a, pool.protocol_fees_b)
    }

    public fun cumulative_volume<A, B>(pool: &LiquidityPool<A, B>): (u64, u64) {
        (pool.cumulative_volume_a, pool.cumulative_volume_b)
    }

    /// Get the current K value (x * y)
    public fun get_k<A, B>(pool: &LiquidityPool<A, B>): u128 {
        (pool.reserve_a as u128) * (pool.reserve_b as u128)
    }

    /// Calculate spot price of A in terms of B (scaled by 1e8 for precision)
    public fun get_spot_price_a_to_b<A, B>(pool: &LiquidityPool<A, B>): u64 {
        if (pool.reserve_a == 0) return 0;
        ((pool.reserve_b as u128) * 100_000_000 / (pool.reserve_a as u128) as u64)
    }

    /// Calculate spot price of B in terms of A (scaled by 1e8 for precision)
    public fun get_spot_price_b_to_a<A, B>(pool: &LiquidityPool<A, B>): u64 {
        if (pool.reserve_b == 0) return 0;
        ((pool.reserve_a as u128) * 100_000_000 / (pool.reserve_b as u128) as u64)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // MATH HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Integer square root using Newton's method
    fun integer_sqrt(n: u128): u64 {
        if (n == 0) return 0;
        let x = n;
        let y = (x + 1) / 2;
        integer_sqrt_iter(n, x, y)
    }

    /// Helper for integer_sqrt iteration
    fun integer_sqrt_iter(n: u128, x: u128, y: u128): u64 {
        if (y >= x) {
            (x as u64)
        } else {
            let new_y = (y + n / y) / 2;
            integer_sqrt_iter(n, y, new_y)
        }
    }

    /// Calculate geometric mean: sqrt(a * b) for initial LP shares (per Uniswap V2)
    fun geometric_mean(amount_a: u64, amount_b: u64): u64 {
        let product = (amount_a as u128) * (amount_b as u128);
        integer_sqrt(product)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // LIQUIDITY MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Pool creation workflow: first liquidity provider sets the initial price.
    /// Returns the number of LP shares to mint.
    /// Uses geometric mean sqrt(a*b) per Uniswap V2 for initial shares.
    public fun provide_initial_liquidity<A, B>(
        pool: &mut LiquidityPool<A, B>,
        amount_a: u64,
        amount_b: u64,
    ): u64 {
        assert!(pool.total_shares == 0, E_INVALID_RATIO);
        assert!(amount_a > 0 && amount_b > 0, E_ZERO_LIQUIDITY);

        // Calculate initial shares as sqrt(amount_a * amount_b) - MINIMUM_LIQUIDITY
        // MINIMUM_LIQUIDITY is permanently locked to prevent share manipulation
        let shares = geometric_mean(amount_a, amount_b);
        assert!(shares > MINIMUM_LIQUIDITY, E_ZERO_LIQUIDITY);
        let shares_to_mint = shares - MINIMUM_LIQUIDITY;

        pool.reserve_a = amount_a;
        pool.reserve_b = amount_b;
        pool.total_shares = shares; // Total includes locked liquidity
        pool.k_last = (amount_a as u128) * (amount_b as u128);

        // Emit event
        event::emit(LiquidityAdded {
            pool_id: object::id(pool),
            amount_a,
            amount_b,
            shares_minted: shares_to_mint,
            total_shares: pool.total_shares,
        });

        shares_to_mint
    }

    /// Add liquidity workflow for existing pools.
    /// Maintains the current price ratio within a small tolerance (default ±0.5% = 50 bps).
    /// Returns the additional LP shares to mint.
    public fun add_liquidity<A, B>(
        pool: &mut LiquidityPool<A, B>,
        amount_a: u64,
        amount_b: u64,
        tolerance_bps: u64,
    ): u64 {
        assert!(pool.total_shares > 0, E_ZERO_LIQUIDITY);
        assert!(amount_a > 0 && amount_b > 0, E_ZERO_LIQUIDITY);

        let (reserve_a, reserve_b) = (pool.reserve_a, pool.reserve_b);

        // Calculate required_b to maintain ratio: required_b = amount_a * reserve_b / reserve_a
        let required_b = (amount_a * reserve_b) / reserve_a;

        // Check ratio within tolerance: |amount_b - required_b| / required_b <= tolerance_bps
        let diff = if (amount_b > required_b) { amount_b - required_b } else { required_b - amount_b };
        let diff_bps = if (required_b > 0) {
            (diff * BPS_DENOMINATOR) / required_b
        } else {
            0
        };
        assert!(diff_bps <= tolerance_bps, E_INVALID_RATIO);

        // Calculate shares: lp_tokens = min(amount_a * total_supply / reserve_a, amount_b * total_supply / reserve_b)
        let shares_a = (amount_a * pool.total_shares) / reserve_a;
        let shares_b = (amount_b * pool.total_shares) / reserve_b;
        let shares = if (shares_a < shares_b) { shares_a } else { shares_b };
        assert!(shares > 0, E_ZERO_LIQUIDITY);

        // Update pool state
        pool.reserve_a = reserve_a + amount_a;
        pool.reserve_b = reserve_b + amount_b;
        pool.total_shares = pool.total_shares + shares;
        pool.k_last = (pool.reserve_a as u128) * (pool.reserve_b as u128);

        // Emit event
        event::emit(LiquidityAdded {
            pool_id: object::id(pool),
            amount_a,
            amount_b,
            shares_minted: shares,
            total_shares: pool.total_shares,
        });

        shares
    }

    /// Remove liquidity workflow.
    /// Returns the amounts of token A and B that should be withdrawn for the given shares.
    /// Supports partial removal - if shares_to_burn < position.lp_shares, NFT is updated.
    /// If shares_to_burn == position.lp_shares, caller should burn the NFT.
    public fun remove_liquidity<A, B>(
        pool: &mut LiquidityPool<A, B>,
        shares_to_burn: u64,
    ): (u64, u64) {
        assert!(shares_to_burn > 0, E_ZERO_LIQUIDITY);
        assert!(pool.total_shares >= shares_to_burn, E_INSUFFICIENT_LIQUIDITY);

        let (reserve_a, reserve_b) = (pool.reserve_a, pool.reserve_b);
        assert!(reserve_a > 0 && reserve_b > 0, E_ZERO_LIQUIDITY);

        // Calculate pro-rata share of reserves
        // amount_a = (shares_to_burn * reserve_a) / total_supply
        // amount_b = (shares_to_burn * reserve_b) / total_supply
        let amount_a = ((shares_to_burn as u128) * (reserve_a as u128) / (pool.total_shares as u128) as u64);
        let amount_b = ((shares_to_burn as u128) * (reserve_b as u128) / (pool.total_shares as u128) as u64);

        // Update pool state
        pool.reserve_a = reserve_a - amount_a;
        pool.reserve_b = reserve_b - amount_b;
        pool.total_shares = pool.total_shares - shares_to_burn;
        
        // Update K if pool is not empty
        if (pool.total_shares > 0) {
            pool.k_last = (pool.reserve_a as u128) * (pool.reserve_b as u128);
        } else {
            pool.k_last = 0;
        };

        // Emit event
        event::emit(LiquidityRemoved {
            pool_id: object::id(pool),
            amount_a,
            amount_b,
            shares_burned: shares_to_burn,
            total_shares: pool.total_shares,
        });

        (amount_a, amount_b)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // SWAP FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Compute the output amount for a swap using x*y=k with a fee applied on input.
    /// Returns (amount_out, fee_amount).
    public fun get_amount_out<A, B>(
        pool: &LiquidityPool<A, B>,
        amount_in: u64,
        a_to_b: bool,
    ): (u64, u64) {
        assert!(amount_in > 0, E_ZERO_AMOUNT_IN);

        let (reserve_in, reserve_out) = if (a_to_b) {
            (pool.reserve_a, pool.reserve_b)
        } else {
            (pool.reserve_b, pool.reserve_a)
        };

        assert!(reserve_in > 0 && reserve_out > 0, E_INSUFFICIENT_LIQUIDITY);

        // Apply fee on input: amount_in_with_fee = amount_in * (1 - fee)
        let fee_amount = (amount_in * pool.fee_bps) / BPS_DENOMINATOR;
        let amount_in_after_fee = amount_in - fee_amount;

        // x*y = k => out = (amount_in_after_fee * reserve_out) / (reserve_in + amount_in_after_fee)
        // Use u128 to prevent overflow for large amounts
        let numerator = (amount_in_after_fee as u128) * (reserve_out as u128);
        let denominator = (reserve_in as u128) + (amount_in_after_fee as u128);
        let amount_out = (numerator / denominator as u64);

        (amount_out, fee_amount)
    }

    /// Calculate price impact of a swap in basis points
    public fun get_price_impact<A, B>(
        pool: &LiquidityPool<A, B>,
        amount_in: u64,
        a_to_b: bool,
    ): u64 {
        if (amount_in == 0) return 0;

        let (reserve_in, reserve_out) = if (a_to_b) {
            (pool.reserve_a, pool.reserve_b)
        } else {
            (pool.reserve_b, pool.reserve_a)
        };

        if (reserve_in == 0 || reserve_out == 0) return 0;

        // Spot price = reserve_out / reserve_in (scaled by 1e8)
        let spot_price = (reserve_out as u128) * 100_000_000 / (reserve_in as u128);

        // Get actual output
        let (amount_out, _) = get_amount_out(pool, amount_in, a_to_b);
        if (amount_out == 0) return BPS_DENOMINATOR; // 100% impact

        // Execution price = amount_out / amount_in (scaled by 1e8)
        let exec_price = (amount_out as u128) * 100_000_000 / (amount_in as u128);

        // Impact = (spot_price - exec_price) / spot_price * 10000
        if (exec_price >= spot_price) return 0;
        let diff = spot_price - exec_price;
        ((diff * (BPS_DENOMINATOR as u128) / spot_price) as u64)
    }

    /// Execute a swap and update reserves, fee indices, and volume.
    /// Returns (amount_out, fee_amount).
    public fun swap<A, B>(
        pool: &mut LiquidityPool<A, B>,
        amount_in: u64,
        a_to_b: bool,
    ): (u64, u64) {
        let (amount_out, fee_amount) = get_amount_out(pool, amount_in, a_to_b);

        if (a_to_b) {
            pool.reserve_a = pool.reserve_a + amount_in;
            pool.reserve_b = pool.reserve_b - amount_out;
            pool.cumulative_volume_a = pool.cumulative_volume_a + amount_in;
            // Accrue trading fee in token A
            accrue_fees_internal(pool, fee_amount, 0);
        } else {
            pool.reserve_b = pool.reserve_b + amount_in;
            pool.reserve_a = pool.reserve_a - amount_out;
            pool.cumulative_volume_b = pool.cumulative_volume_b + amount_in;
            // Accrue trading fee in token B
            accrue_fees_internal(pool, 0, fee_amount);
        };

        // Emit swap event
        event::emit(SwapExecuted {
            pool_id: object::id(pool),
            amount_in,
            amount_out,
            fee_amount,
            a_to_b,
        });

        (amount_out, fee_amount)
    }

    /// Execute a swap with slippage protection.
    /// Aborts if output is less than min_amount_out.
    public fun swap_with_slippage<A, B>(
        pool: &mut LiquidityPool<A, B>,
        amount_in: u64,
        min_amount_out: u64,
        a_to_b: bool,
    ): (u64, u64) {
        let (amount_out, fee_amount) = swap(pool, amount_in, a_to_b);
        assert!(amount_out >= min_amount_out, E_SLIPPAGE_EXCEEDED);
        (amount_out, fee_amount)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FEE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Internal helper for fee accounting: update global fee indices and protocol bucket.
    /// Protocol gets PROTOCOL_FEE_BPS of trading fees (default 10%), rest goes to LPs.
    fun accrue_fees_internal<A, B>(
        pool: &mut LiquidityPool<A, B>,
        fee_a: u64,
        fee_b: u64,
    ) {
        let total_shares = pool.total_shares;
        if (total_shares == 0) {
            // If no LPs yet, everything goes to protocol bucket.
            pool.protocol_fees_a = pool.protocol_fees_a + fee_a;
            pool.protocol_fees_b = pool.protocol_fees_b + fee_b;
            return
        };

        // Split fees: PROTOCOL_FEE_BPS goes to protocol, rest to LPs via fee index.
        let proto_a = (fee_a * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        let proto_b = (fee_b * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        let lp_a = fee_a - proto_a;
        let lp_b = fee_b - proto_b;

        pool.protocol_fees_a = pool.protocol_fees_a + proto_a;
        pool.protocol_fees_b = pool.protocol_fees_b + proto_b;

        // Update global fee indices for LP fee distribution
        if (lp_a > 0) {
            let delta_index_a = (lp_a * BPS_DENOMINATOR) / total_shares;
            pool.fee_index_a = pool.fee_index_a + delta_index_a;
        };
        if (lp_b > 0) {
            let delta_index_b = (lp_b * BPS_DENOMINATOR) / total_shares;
            pool.fee_index_b = pool.fee_index_b + delta_index_b;
        };
    }

    /// Withdraw accumulated protocol fees (admin only in production)
    public fun withdraw_protocol_fees<A, B>(
        pool: &mut LiquidityPool<A, B>,
    ): (u64, u64) {
        let fees_a = pool.protocol_fees_a;
        let fees_b = pool.protocol_fees_b;
        pool.protocol_fees_a = 0;
        pool.protocol_fees_b = 0;
        (fees_a, fees_b)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // COIN-BASED SWAP FUNCTIONS (Test/Demo - Real Token Transfers)
    // ═══════════════════════════════════════════════════════════════════════════════
    // NOTE: These functions use test utilities for balance creation/destruction.
    // For production, use a pool with actual Balance<A> and Balance<B> storage.

    /// Swap with actual Coin objects - Complete swap workflow with real token transfers.
    /// 
    /// Steps implemented:
    /// 1. User specifies input coin and minimum output
    /// 2. Calculate expected output using x*y=k formula
    /// 3. Apply trading fee (e.g., 0.3%)
    /// 4. Validate output meets minimum (slippage check)
    /// 5. Execute swap:
    ///    - Transfer input tokens to pool (coin consumed)
    ///    - Calculate exact output
    ///    - Transfer output tokens to user (new coin created)
    ///    - Update reserves maintaining K
    /// 6. Accumulate fees for LPs
    /// 7. SwapExecuted event emitted
    /// 
    /// Returns the output Coin.
    #[test_only]
    public fun swap_coins_a_to_b<A, B>(
        pool: &mut LiquidityPool<A, B>,
        coin_in: Coin<A>,
        min_amount_out: u64,
        ctx: &mut TxContext,
    ): Coin<B> {
        let amount_in = coin::value(&coin_in);
        
        // Steps 2-4, 6-7: Execute swap with slippage check
        let (amount_out, _fee) = swap_with_slippage(pool, amount_in, min_amount_out, true);
        
        // Step 5a: Transfer input tokens to pool (destroy the input coin)
        let balance_in = coin::into_balance(coin_in);
        sui::test_utils::destroy(balance_in);
        
        // Step 5c: Create output coin to transfer to user
        let balance_out = balance::create_for_testing<B>(amount_out);
        coin::from_balance(balance_out, ctx)
    }

    /// Swap B to A with actual Coin objects
    #[test_only]
    public fun swap_coins_b_to_a<A, B>(
        pool: &mut LiquidityPool<A, B>,
        coin_in: Coin<B>,
        min_amount_out: u64,
        ctx: &mut TxContext,
    ): Coin<A> {
        let amount_in = coin::value(&coin_in);
        
        // Execute swap with slippage check
        let (amount_out, _fee) = swap_with_slippage(pool, amount_in, min_amount_out, false);
        
        // Transfer input tokens to pool
        let balance_in = coin::into_balance(coin_in);
        sui::test_utils::destroy(balance_in);
        
        // Create output coin
        let balance_out = balance::create_for_testing<A>(amount_out);
        coin::from_balance(balance_out, ctx)
    }

    /// Preview swap output for coin amount (production-ready)
    public fun preview_swap_coins<A, B>(
        pool: &LiquidityPool<A, B>,
        coin_in: &Coin<A>,
        a_to_b: bool,
    ): (u64, u64) {
        let amount_in = coin::value(coin_in);
        get_amount_out(pool, amount_in, a_to_b)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // COIN-BASED LIQUIDITY FUNCTIONS (Test/Demo - Real Token Transfers)
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Provide initial liquidity with actual Coins (test only)
    /// Returns LP shares minted
    #[test_only]
    public fun provide_initial_liquidity_with_coins<A, B>(
        pool: &mut LiquidityPool<A, B>,
        coin_a: Coin<A>,
        coin_b: Coin<B>,
    ): u64 {
        let amount_a = coin::value(&coin_a);
        let amount_b = coin::value(&coin_b);
        
        // Perform liquidity provision
        let shares = provide_initial_liquidity(pool, amount_a, amount_b);
        
        // Consume the input coins (add to pool's balance)
        let balance_a = coin::into_balance(coin_a);
        let balance_b = coin::into_balance(coin_b);
        sui::test_utils::destroy(balance_a);
        sui::test_utils::destroy(balance_b);
        
        shares
    }

    /// Add liquidity with actual Coins (test only)
    /// Returns LP shares minted
    #[test_only]
    public fun add_liquidity_with_coins<A, B>(
        pool: &mut LiquidityPool<A, B>,
        coin_a: Coin<A>,
        coin_b: Coin<B>,
        tolerance_bps: u64,
    ): u64 {
        let amount_a = coin::value(&coin_a);
        let amount_b = coin::value(&coin_b);
        
        // Perform liquidity addition
        let shares = add_liquidity(pool, amount_a, amount_b, tolerance_bps);
        
        // Consume the input coins
        let balance_a = coin::into_balance(coin_a);
        let balance_b = coin::into_balance(coin_b);
        sui::test_utils::destroy(balance_a);
        sui::test_utils::destroy(balance_b);
        
        shares
    }

    /// Remove liquidity and receive actual Coins (test only)
    /// Returns (Coin<A>, Coin<B>)
    #[test_only]
    public fun remove_liquidity_with_coins<A, B>(
        pool: &mut LiquidityPool<A, B>,
        shares_to_burn: u64,
        ctx: &mut TxContext,
    ): (Coin<A>, Coin<B>) {
        // Perform liquidity removal
        let (amount_a, amount_b) = remove_liquidity(pool, shares_to_burn);
        
        // Create output coins
        let balance_a = balance::create_for_testing<A>(amount_a);
        let balance_b = balance::create_for_testing<B>(amount_b);
        
        (coin::from_balance(balance_a, ctx), coin::from_balance(balance_b, ctx))
    }

    /// Remove liquidity with minimum output protection (test only)
    #[test_only]
    public fun remove_liquidity_with_coins_protected<A, B>(
        pool: &mut LiquidityPool<A, B>,
        shares_to_burn: u64,
        min_amount_a: u64,
        min_amount_b: u64,
        ctx: &mut TxContext,
    ): (Coin<A>, Coin<B>) {
        let (coin_a, coin_b) = remove_liquidity_with_coins(pool, shares_to_burn, ctx);
        
        assert!(coin::value(&coin_a) >= min_amount_a, E_SLIPPAGE_EXCEEDED);
        assert!(coin::value(&coin_b) >= min_amount_b, E_SLIPPAGE_EXCEEDED);
        
        (coin_a, coin_b)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ENTRY FUNCTIONS (for direct CLI/transaction calls)
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Entry: Create and share a new pool
    public entry fun create_shared_pool<A, B>(fee_bps: u64, ctx: &mut TxContext) {
        let pool = new_pool<A, B>(fee_bps, ctx);
        sui::transfer::share_object(pool);
    }

    /// Entry: Add initial liquidity to a pool (for testing)
    public entry fun entry_provide_initial_liquidity<A, B>(
        pool: &mut LiquidityPool<A, B>,
        amount_a: u64,
        amount_b: u64,
    ) {
        provide_initial_liquidity(pool, amount_a, amount_b);
    }

    /// Entry: Execute a swap (for testing - amounts tracked internally)
    public entry fun entry_swap<A, B>(
        pool: &mut LiquidityPool<A, B>,
        amount_in: u64,
        min_amount_out: u64,
        a_to_b: bool,
    ) {
        swap_with_slippage(pool, amount_in, min_amount_out, a_to_b);
    }
}
