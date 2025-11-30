#[allow(unused_const, unused_use)]
module sui_amm_nft_lp::amm_router {
    use sui::tx_context::TxContext;
    use sui::object::ID;

    use sui_amm_nft_lp::pool_factory;
    use sui_amm_nft_lp::liquidity_pool;
    use sui_amm_nft_lp::lp_position_nft;
    use sui_amm_nft_lp::fee_distributor;
    use sui_amm_nft_lp::slippage_protection;
    use sui_amm_nft_lp::pool_registry::{Self, PoolRegistry};

    // ═══════════════════════════════════════════════════════════════════════════════
    // PLACEHOLDER TYPES
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Placeholder coin types for demonstration
    struct CoinA has drop, store {}
    struct CoinB has drop, store {}

    // ═══════════════════════════════════════════════════════════════════════════════
    // ERROR CODES
    // ═══════════════════════════════════════════════════════════════════════════════

    const E_POOL_MISMATCH: u64 = 1;
    const E_INSUFFICIENT_SHARES: u64 = 2;
    const E_SLIPPAGE_EXCEEDED: u64 = 3;

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL CREATION WORKFLOWS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Creates a pool for CoinA/CoinB, provides initial liquidity, and mints an LPPosition NFT.
    /// Returns the created pool so callers (e.g. tests) can inspect reserves and other fields.
    public fun create_pool_and_initial_lp(
        factory: &mut pool_factory::PoolFactory,
        _fee_dist: &mut fee_distributor::FeeDistributor,
        amount_a: u64,
        amount_b: u64,
        recipient: address,
        ctx: &mut TxContext,
    ): liquidity_pool::LiquidityPool<CoinA, CoinB> {
        let pool = pool_factory::create_pool<CoinA, CoinB>(factory, 30, ctx);
        let shares = liquidity_pool::provide_initial_liquidity<CoinA, CoinB>(&mut pool, amount_a, amount_b);
        let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
        lp_position_nft::mint(
            liquidity_pool::pool_id(&pool),
            shares,
            idx_a,
            idx_b,
            amount_a,  // initial_amount_a
            amount_b,  // initial_amount_b
            recipient,
            ctx
        );
        pool
    }

    /// Generic pool creation with custom fee tier
    public fun create_pool_with_fee<A, B>(
        factory: &mut pool_factory::PoolFactory,
        fee_tier_bps: u64,
        amount_a: u64,
        amount_b: u64,
        recipient: address,
        ctx: &mut TxContext,
    ): liquidity_pool::LiquidityPool<A, B> {
        let pool = pool_factory::create_pool<A, B>(factory, fee_tier_bps, ctx);
        let shares = liquidity_pool::provide_initial_liquidity<A, B>(&mut pool, amount_a, amount_b);
        let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
        lp_position_nft::mint(
            liquidity_pool::pool_id(&pool),
            shares,
            idx_a,
            idx_b,
            amount_a,
            amount_b,
            recipient,
            ctx
        );
        pool
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL CREATION WITH REGISTRY (Full Workflow - Steps 1-8)
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Complete pool creation workflow with registry validation.
    /// Implements ALL 8 steps of pool creation:
    /// 1. User calls create_pool with token pair and fee tier
    /// 2. System validates tokens aren't already paired at this fee tier
    /// 3. User provides initial liquidity (minimum amounts)
    /// 4. Pool calculates initial K value (reserve_a * reserve_b)
    /// 5. System mints LP shares based on geometric mean: sqrt(amount_a * amount_b)
    /// 6. NFT position created for creator
    /// 7. PoolCreated event emitted
    /// 8. Pool indexed in factory registry
    public fun create_pool_full_workflow<A, B>(
        factory: &mut pool_factory::PoolFactory,
        registry: &mut PoolRegistry,
        fee_tier_bps: u64,
        amount_a: u64,
        amount_b: u64,
        recipient: address,
        ctx: &mut TxContext,
    ): liquidity_pool::LiquidityPool<A, B> {
        // Step 2: Validate tokens aren't already paired at this fee tier
        pool_registry::assert_pool_not_exists<A, B>(registry, fee_tier_bps);
        
        // Step 1 & 7: Create pool (emits PoolCreated event)
        let pool = pool_factory::create_pool<A, B>(factory, fee_tier_bps, ctx);
        let pool_id = liquidity_pool::pool_id(&pool);
        
        // Steps 3, 4, 5: Provide initial liquidity
        // - Validates minimum amounts (step 3)
        // - Calculates K = reserve_a * reserve_b (step 4)
        // - Mints LP shares = sqrt(amount_a * amount_b) (step 5)
        let shares = liquidity_pool::provide_initial_liquidity<A, B>(&mut pool, amount_a, amount_b);
        
        // Step 6: Create NFT position for creator
        let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
        lp_position_nft::mint(
            pool_id,
            shares,
            idx_a,
            idx_b,
            amount_a,
            amount_b,
            recipient,
            ctx
        );
        
        // Step 8: Index pool in registry
        pool_registry::register_pool<A, B>(
            registry,
            pool_id,
            fee_tier_bps,
            recipient,
            ctx
        );
        
        pool
    }

    /// Create a standard pool (0.30% fee) with full workflow
    public fun create_standard_pool_full<A, B>(
        factory: &mut pool_factory::PoolFactory,
        registry: &mut PoolRegistry,
        amount_a: u64,
        amount_b: u64,
        recipient: address,
        ctx: &mut TxContext,
    ): liquidity_pool::LiquidityPool<A, B> {
        create_pool_full_workflow<A, B>(factory, registry, 30, amount_a, amount_b, recipient, ctx)
    }

    /// Create a stable pool (0.05% fee) with full workflow
    public fun create_stable_pool_full<A, B>(
        factory: &mut pool_factory::PoolFactory,
        registry: &mut PoolRegistry,
        amount_a: u64,
        amount_b: u64,
        recipient: address,
        ctx: &mut TxContext,
    ): liquidity_pool::LiquidityPool<A, B> {
        create_pool_full_workflow<A, B>(factory, registry, 5, amount_a, amount_b, recipient, ctx)
    }

    /// Create an exotic pool (1.00% fee) with full workflow
    public fun create_exotic_pool_full<A, B>(
        factory: &mut pool_factory::PoolFactory,
        registry: &mut PoolRegistry,
        amount_a: u64,
        amount_b: u64,
        recipient: address,
        ctx: &mut TxContext,
    ): liquidity_pool::LiquidityPool<A, B> {
        create_pool_full_workflow<A, B>(factory, registry, 100, amount_a, amount_b, recipient, ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL LOOKUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Check if a pool exists for the given token pair and fee tier
    public fun pool_exists<A, B>(registry: &PoolRegistry, fee_bps: u64): bool {
        pool_registry::pool_exists<A, B>(registry, fee_bps)
    }

    /// Get pool ID for a token pair and fee tier
    public fun get_pool_id<A, B>(registry: &PoolRegistry, fee_bps: u64): ID {
        pool_registry::get_pool<A, B>(registry, fee_bps)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // LIQUIDITY HELPERS (Step 2: Calculate required ratio)
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Calculate required amount_b for a given amount_a to maintain pool ratio.
    /// Step 2 of Add Liquidity workflow: amount_b = (amount_a * reserve_b) / reserve_a
    public fun calculate_required_amount_b<A, B>(
        pool: &liquidity_pool::LiquidityPool<A, B>,
        amount_a: u64,
    ): u64 {
        let (reserve_a, reserve_b) = liquidity_pool::reserves(pool);
        if (reserve_a == 0) return 0;
        (amount_a * reserve_b) / reserve_a
    }

    /// Calculate required amount_a for a given amount_b to maintain pool ratio.
    public fun calculate_required_amount_a<A, B>(
        pool: &liquidity_pool::LiquidityPool<A, B>,
        amount_b: u64,
    ): u64 {
        let (reserve_a, reserve_b) = liquidity_pool::reserves(pool);
        if (reserve_b == 0) return 0;
        (amount_b * reserve_a) / reserve_b
    }

    /// Calculate optimal amounts given maximum limits for both tokens.
    /// Returns (optimal_a, optimal_b) that maximizes liquidity while maintaining ratio.
    public fun calculate_optimal_amounts<A, B>(
        pool: &liquidity_pool::LiquidityPool<A, B>,
        max_amount_a: u64,
        max_amount_b: u64,
    ): (u64, u64) {
        let (reserve_a, reserve_b) = liquidity_pool::reserves(pool);
        
        if (reserve_a == 0 || reserve_b == 0) {
            // Empty pool - use provided amounts as-is
            return (max_amount_a, max_amount_b)
        };
        
        // Try using max_amount_a and calculate required_b
        let required_b = (max_amount_a * reserve_b) / reserve_a;
        
        if (required_b <= max_amount_b) {
            // Can use full amount_a
            (max_amount_a, required_b)
        } else {
            // Use max_amount_b and calculate required_a
            let required_a = (max_amount_b * reserve_a) / reserve_b;
            (required_a, max_amount_b)
        }
    }

    /// Preview LP shares that would be minted for given amounts
    public fun preview_add_liquidity<A, B>(
        pool: &liquidity_pool::LiquidityPool<A, B>,
        amount_a: u64,
        amount_b: u64,
    ): u64 {
        let (reserve_a, reserve_b) = liquidity_pool::reserves(pool);
        let total_shares = liquidity_pool::total_shares(pool);
        
        if (total_shares == 0 || reserve_a == 0 || reserve_b == 0) {
            return 0
        };
        
        // min(amount_a * total_shares / reserve_a, amount_b * total_shares / reserve_b)
        let shares_a = (amount_a * total_shares) / reserve_a;
        let shares_b = (amount_b * total_shares) / reserve_b;
        if (shares_a < shares_b) { shares_a } else { shares_b }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // LIQUIDITY MANAGEMENT WITH NFT
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Add Liquidity Workflow - Complete 8-step process for NEW LPs.
    /// Creates a new NFT position for the LP.
    /// 
    /// Steps implemented:
    /// 1. LP selects pool and amounts to deposit (params)
    /// 2. System calculates required ratio: amount_b = (amount_a * reserve_b) / reserve_a
    /// 3. LP provides both tokens (params)
    /// 4. System validates amounts maintain current ratio (±tolerance_bps)
    /// 5. Calculate LP tokens: lp_tokens = min(amount_a * total_supply / reserve_a, ...)
    /// 6. Mint LP tokens and CREATE NFT position
    /// 7. Update reserves and position metadata
    /// 8. LiquidityAdded event emitted
    public fun add_liquidity_new_position<A, B>(
        pool: &mut liquidity_pool::LiquidityPool<A, B>,
        amount_a: u64,
        amount_b: u64,
        tolerance_bps: u64,
        recipient: address,
        ctx: &mut TxContext,
    ): u64 {
        let pool_id = liquidity_pool::pool_id(pool);
        
        // Steps 2-5, 7-8: Add liquidity (validates ratio, calculates shares, updates reserves, emits event)
        let shares = liquidity_pool::add_liquidity<A, B>(pool, amount_a, amount_b, tolerance_bps);
        
        // Step 6: Create NEW NFT position for this LP
        let (idx_a, idx_b) = liquidity_pool::fee_indices(pool);
        lp_position_nft::mint(
            pool_id,
            shares,
            idx_a,
            idx_b,
            amount_a,
            amount_b,
            recipient,
            ctx
        );
        
        shares
    }

    /// Add liquidity to a pool and UPDATE an existing LP position NFT with more shares.
    /// Use this when LP already has a position in this pool.
    public fun add_liquidity_with_nft<A, B>(
        pool: &mut liquidity_pool::LiquidityPool<A, B>,
        position: &mut lp_position_nft::LPPosition,
        amount_a: u64,
        amount_b: u64,
        tolerance_bps: u64,
    ): u64 {
        let pool_id = liquidity_pool::pool_id(pool);
        assert!(lp_position_nft::pool(position) == pool_id, E_POOL_MISMATCH);

        let delta_shares = liquidity_pool::add_liquidity<A, B>(pool, amount_a, amount_b, tolerance_bps);
        lp_position_nft::add_shares(position, delta_shares);
        lp_position_nft::update_initial_amounts(position, amount_a, amount_b);

        delta_shares
    }

    /// Remove liquidity from a pool and decrease the LP position's shares.
    /// Returns (amount_a, amount_b) withdrawn.
    public fun remove_liquidity_with_nft<A, B>(
        pool: &mut liquidity_pool::LiquidityPool<A, B>,
        position: &mut lp_position_nft::LPPosition,
        burn_shares: u64,
    ): (u64, u64) {
        let pool_id = liquidity_pool::pool_id(pool);
        assert!(lp_position_nft::pool(position) == pool_id, E_POOL_MISMATCH);
        assert!(lp_position_nft::shares(position) >= burn_shares, E_INSUFFICIENT_SHARES);

        let (out_a, out_b) = liquidity_pool::remove_liquidity<A, B>(pool, burn_shares);
        lp_position_nft::reduce_shares(position, burn_shares);

        (out_a, out_b)
    }

    /// Remove liquidity with minimum output protection
    public fun remove_liquidity_with_slippage<A, B>(
        pool: &mut liquidity_pool::LiquidityPool<A, B>,
        position: &mut lp_position_nft::LPPosition,
        burn_shares: u64,
        min_amount_a: u64,
        min_amount_b: u64,
    ): (u64, u64) {
        let (out_a, out_b) = remove_liquidity_with_nft(pool, position, burn_shares);
        assert!(out_a >= min_amount_a && out_b >= min_amount_b, E_SLIPPAGE_EXCEEDED);
        (out_a, out_b)
    }

    /// Remove ALL liquidity and burn the NFT position.
    /// Complete workflow for Step 5: Update/burn NFT if fully removed.
    /// 
    /// Steps implemented:
    /// 1. LP specifies to remove all liquidity (position.shares)
    /// 2. Calculate token amounts: (shares * reserve) / total_supply
    /// 3. Validate minimum amounts (slippage protection)
    /// 4. Transfer tokens to LP (returns amounts)
    /// 5. Burn NFT position (fully removed)
    /// 6. Update reserves
    /// 7. LiquidityRemoved event emitted
    public fun remove_all_liquidity_and_burn<A, B>(
        pool: &mut liquidity_pool::LiquidityPool<A, B>,
        position: lp_position_nft::LPPosition,
        min_amount_a: u64,
        min_amount_b: u64,
    ): (u64, u64) {
        let pool_id = liquidity_pool::pool_id(pool);
        assert!(lp_position_nft::pool(&position) == pool_id, E_POOL_MISMATCH);
        
        // Step 1: Get all shares
        let all_shares = lp_position_nft::shares(&position);
        
        // Steps 2, 6, 7: Remove liquidity (calculates amounts, updates reserves, emits event)
        let (out_a, out_b) = liquidity_pool::remove_liquidity<A, B>(pool, all_shares);
        
        // Step 3: Validate minimum amounts (slippage protection)
        assert!(out_a >= min_amount_a && out_b >= min_amount_b, E_SLIPPAGE_EXCEEDED);
        
        // Step 5: Burn the NFT (position is consumed)
        lp_position_nft::burn(position);
        
        // Step 4: Return amounts (caller receives tokens)
        (out_a, out_b)
    }

    /// Check if position should be burned (has zero shares)
    public fun should_burn_position(position: &lp_position_nft::LPPosition): bool {
        lp_position_nft::shares(position) == 0
    }

    /// Preview remove liquidity amounts
    public fun preview_remove_liquidity<A, B>(
        pool: &liquidity_pool::LiquidityPool<A, B>,
        shares_to_burn: u64,
    ): (u64, u64) {
        let (reserve_a, reserve_b) = liquidity_pool::reserves(pool);
        let total_shares = liquidity_pool::total_shares(pool);
        
        if (total_shares == 0) return (0, 0);
        
        let amount_a = ((shares_to_burn as u128) * (reserve_a as u128) / (total_shares as u128) as u64);
        let amount_b = ((shares_to_burn as u128) * (reserve_b as u128) / (total_shares as u128) as u64);
        
        (amount_a, amount_b)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FEE CLAIMING
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Claim fees for a given LP position using the FeeDistributor and pool fee indices.
    /// Returns (claimed_a, claimed_b).
    public fun claim_fees_for_position<A, B>(
        fee_dist: &mut fee_distributor::FeeDistributor,
        pool: &liquidity_pool::LiquidityPool<A, B>,
        position: &mut lp_position_nft::LPPosition,
    ): (u64, u64) {
        fee_distributor::claim_fees<A, B>(fee_dist, pool, position)
    }

    /// Claim fees and auto-compound them back into the pool.
    /// Returns (new_shares, compounded_a, compounded_b).
    public fun claim_and_compound<A, B>(
        fee_dist: &mut fee_distributor::FeeDistributor,
        pool: &mut liquidity_pool::LiquidityPool<A, B>,
        position: &mut lp_position_nft::LPPosition,
        tolerance_bps: u64,
    ): (u64, u64, u64) {
        fee_distributor::claim_and_compound<A, B>(fee_dist, pool, position, tolerance_bps)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // SWAP WORKFLOWS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Execute a swap with automatic slippage calculation.
    /// slippage_bps: maximum acceptable slippage in basis points.
    public fun swap_with_auto_slippage<A, B>(
        pool: &mut liquidity_pool::LiquidityPool<A, B>,
        amount_in: u64,
        slippage_bps: u64,
        a_to_b: bool,
    ): (u64, u64) {
        // Calculate expected output and minimum acceptable
        let (expected_out, _) = liquidity_pool::get_amount_out(pool, amount_in, a_to_b);
        let min_out = slippage_protection::calculate_min_output(expected_out, slippage_bps);

        // Execute swap with slippage protection
        liquidity_pool::swap_with_slippage(pool, amount_in, min_out, a_to_b)
    }

    /// Execute swap with explicit minimum output
    public fun swap_exact_in<A, B>(
        pool: &mut liquidity_pool::LiquidityPool<A, B>,
        amount_in: u64,
        min_amount_out: u64,
        a_to_b: bool,
    ): (u64, u64) {
        liquidity_pool::swap_with_slippage(pool, amount_in, min_amount_out, a_to_b)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // VIEW HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Get position value in terms of underlying tokens
    public fun get_position_value<A, B>(
        pool: &liquidity_pool::LiquidityPool<A, B>,
        position: &lp_position_nft::LPPosition,
    ): (u64, u64) {
        let (reserve_a, reserve_b) = liquidity_pool::reserves(pool);
        let total_shares = liquidity_pool::total_shares(pool);
        lp_position_nft::calculate_position_value(position, reserve_a, reserve_b, total_shares)
    }

    /// Get pending fees for a position
    public fun get_pending_fees<A, B>(
        pool: &liquidity_pool::LiquidityPool<A, B>,
        position: &lp_position_nft::LPPosition,
    ): (u64, u64) {
        let (idx_a, idx_b) = liquidity_pool::fee_indices(pool);
        lp_position_nft::calculate_pending_fees(position, idx_a, idx_b)
    }

    /// Get impermanent loss for a position
    public fun get_impermanent_loss<A, B>(
        pool: &liquidity_pool::LiquidityPool<A, B>,
        position: &lp_position_nft::LPPosition,
    ): (u64, bool) {
        let (value_a, value_b) = get_position_value(pool, position);
        lp_position_nft::calculate_impermanent_loss(position, value_a, value_b)
    }

    /// Get swap quote (amount out for given amount in)
    public fun get_swap_quote<A, B>(
        pool: &liquidity_pool::LiquidityPool<A, B>,
        amount_in: u64,
        a_to_b: bool,
    ): (u64, u64, u64) {
        let (amount_out, fee) = liquidity_pool::get_amount_out(pool, amount_in, a_to_b);
        let price_impact = liquidity_pool::get_price_impact(pool, amount_in, a_to_b);
        (amount_out, fee, price_impact)
    }
}
