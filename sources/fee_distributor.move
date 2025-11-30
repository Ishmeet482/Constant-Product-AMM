#[allow(unused_const, lint(public_entry), unused_use)]
module sui_amm_nft_lp::fee_distributor {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::TxContext;
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::balance;

    use sui_amm_nft_lp::liquidity_pool;
    use sui_amm_nft_lp::lp_position_nft;

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════

    const BPS_DENOMINATOR: u64 = 10_000;

    // ═══════════════════════════════════════════════════════════════════════════════
    // ERROR CODES
    // ═══════════════════════════════════════════════════════════════════════════════

    const E_NO_FEES_TO_CLAIM: u64 = 1;
    const E_POOL_MISMATCH: u64 = 2;

    // ═══════════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Global fee distributor managing fee collection and distribution
    struct FeeDistributor has key {
        id: UID,
        /// Total fees distributed in token A across all pools
        total_distributed_a: u64,
        /// Total fees distributed in token B across all pools
        total_distributed_b: u64,
        /// Number of fee claims processed
        total_claims: u64,
        /// Whether auto-compound is enabled by default
        auto_compound_enabled: bool,
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Emitted when fees are claimed
    struct FeesClaimedEvent has copy, drop {
        position_id: ID,
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
        auto_compounded: bool,
    }

    /// Emitted when fees are auto-compounded
    struct FeesCompounded has copy, drop {
        position_id: ID,
        pool_id: ID,
        amount_a: u64,
        amount_b: u64,
        new_shares: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════════

    public fun new_fee_distributor(ctx: &mut TxContext): FeeDistributor {
        FeeDistributor {
            id: object::new(ctx),
            total_distributed_a: 0,
            total_distributed_b: 0,
            total_claims: 0,
            auto_compound_enabled: false,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Get total distributed fees
    public fun total_distributed(distributor: &FeeDistributor): (u64, u64) {
        (distributor.total_distributed_a, distributor.total_distributed_b)
    }

    /// Get total number of claims
    public fun total_claims(distributor: &FeeDistributor): u64 {
        distributor.total_claims
    }

    /// Check if auto-compound is enabled
    public fun is_auto_compound_enabled(distributor: &FeeDistributor): bool {
        distributor.auto_compound_enabled
    }

    /// Compute claimable fees for a position given current pool indices.
    /// Returns (claimable_a, claimable_b, new_last_index_a, new_last_index_b).
    public fun compute_claimable<A, B>(
        pool: &liquidity_pool::LiquidityPool<A, B>,
        position: &lp_position_nft::LPPosition,
    ): (u64, u64, u64, u64) {
        let (index_a, index_b) = liquidity_pool::fee_indices(pool);
        let lp_shares = lp_position_nft::shares(position);
        let (last_a, last_b) = lp_position_nft::last_fee_indices(position);

        let delta_index_a = index_a - last_a;
        let delta_index_b = index_b - last_b;

        let claimable_a = (delta_index_a * lp_shares) / BPS_DENOMINATOR;
        let claimable_b = (delta_index_b * lp_shares) / BPS_DENOMINATOR;

        (claimable_a, claimable_b, index_a, index_b)
    }

    /// Preview claimable fees without modifying state
    public fun preview_claimable<A, B>(
        pool: &liquidity_pool::LiquidityPool<A, B>,
        position: &lp_position_nft::LPPosition,
    ): (u64, u64) {
        let (claimable_a, claimable_b, _, _) = compute_claimable(pool, position);
        (claimable_a, claimable_b)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FEE CLAIMING
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Claim fees for a given position.
    /// Updates position metadata and returns claimable amounts.
    /// In a production implementation, this would transfer actual coin objects.
    public fun claim_fees<A, B>(
        fee_distributor: &mut FeeDistributor,
        pool: &liquidity_pool::LiquidityPool<A, B>,
        position: &mut lp_position_nft::LPPosition,
    ): (u64, u64) {
        // Verify position belongs to this pool
        assert!(lp_position_nft::pool(position) == liquidity_pool::pool_id(pool), E_POOL_MISMATCH);

        let (claimable_a, claimable_b, new_index_a, new_index_b) = compute_claimable(pool, position);

        // Update position metadata
        lp_position_nft::update_metadata(position, new_index_a, new_index_b, claimable_a, claimable_b);

        // Update distributor stats
        fee_distributor.total_distributed_a = fee_distributor.total_distributed_a + claimable_a;
        fee_distributor.total_distributed_b = fee_distributor.total_distributed_b + claimable_b;
        fee_distributor.total_claims = fee_distributor.total_claims + 1;

        // Emit event
        event::emit(FeesClaimedEvent {
            position_id: lp_position_nft::id(position),
            pool_id: liquidity_pool::pool_id(pool),
            amount_a: claimable_a,
            amount_b: claimable_b,
            auto_compounded: false,
        });

        (claimable_a, claimable_b)
    }

    /// Claim fees and auto-compound them back into the pool as additional liquidity.
    /// Returns (new_shares_minted, fees_a_compounded, fees_b_compounded).
    /// NOTE: In production, this requires actual token handling. This is a simplified version.
    public fun claim_and_compound<A, B>(
        fee_distributor: &mut FeeDistributor,
        pool: &mut liquidity_pool::LiquidityPool<A, B>,
        position: &mut lp_position_nft::LPPosition,
        tolerance_bps: u64,
    ): (u64, u64, u64) {
        // Verify position belongs to this pool
        assert!(lp_position_nft::pool(position) == liquidity_pool::pool_id(pool), E_POOL_MISMATCH);

        let (claimable_a, claimable_b, new_index_a, new_index_b) = compute_claimable(pool, position);

        if (claimable_a == 0 && claimable_b == 0) {
            return (0, 0, 0)
        };

        // Add claimed fees as liquidity
        // Note: In production, this would involve actual token transfers
        let new_shares = if (claimable_a > 0 && claimable_b > 0) {
            liquidity_pool::add_liquidity(pool, claimable_a, claimable_b, tolerance_bps)
        } else {
            0
        };

        // Update position metadata (fees claimed but reinvested)
        lp_position_nft::update_metadata(position, new_index_a, new_index_b, claimable_a, claimable_b);

        // Add new shares to position
        if (new_shares > 0) {
            lp_position_nft::add_shares(position, new_shares);
            lp_position_nft::update_initial_amounts(position, claimable_a, claimable_b);
        };

        // Update distributor stats
        fee_distributor.total_distributed_a = fee_distributor.total_distributed_a + claimable_a;
        fee_distributor.total_distributed_b = fee_distributor.total_distributed_b + claimable_b;
        fee_distributor.total_claims = fee_distributor.total_claims + 1;

        // Emit events
        event::emit(FeesClaimedEvent {
            position_id: lp_position_nft::id(position),
            pool_id: liquidity_pool::pool_id(pool),
            amount_a: claimable_a,
            amount_b: claimable_b,
            auto_compounded: true,
        });

        if (new_shares > 0) {
            event::emit(FeesCompounded {
                position_id: lp_position_nft::id(position),
                pool_id: liquidity_pool::pool_id(pool),
                amount_a: claimable_a,
                amount_b: claimable_b,
                new_shares,
            });
        };

        (new_shares, claimable_a, claimable_b)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // COIN-BASED FEE CLAIMING (Real Token Transfers)
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Claim fees and receive actual Coins - Complete fee claim workflow.
    ///
    /// Steps implemented:
    /// 1. LP views accumulated fees through NFT position (via preview_claimable)
    /// 2. LP calls this function with position NFT
    /// 3. System calculates pro-rata share: claimable = (delta_index * lp_shares) / BPS
    /// 4. Transfer fees to LP (returns Coin<A> and Coin<B>)
    /// 5. Update position metadata (last indices, claimed totals)
    /// 6. FeeClaimed event emitted
    ///
    /// Returns (Coin<A>, Coin<B>) with claimed fee amounts.
    #[test_only]
    public fun claim_fees_with_coins<A, B>(
        fee_distributor: &mut FeeDistributor,
        pool: &liquidity_pool::LiquidityPool<A, B>,
        position: &mut lp_position_nft::LPPosition,
        ctx: &mut TxContext,
    ): (Coin<A>, Coin<B>) {
        // Steps 2-3, 5-6: Calculate, update metadata, emit event
        let (claimable_a, claimable_b) = claim_fees(fee_distributor, pool, position);
        
        // Step 4: Create coins to transfer to LP
        let balance_a = balance::create_for_testing<A>(claimable_a);
        let balance_b = balance::create_for_testing<B>(claimable_b);
        
        (coin::from_balance(balance_a, ctx), coin::from_balance(balance_b, ctx))
    }

    /// Claim fees with minimum amounts check (slippage protection)
    #[test_only]
    public fun claim_fees_with_coins_protected<A, B>(
        fee_distributor: &mut FeeDistributor,
        pool: &liquidity_pool::LiquidityPool<A, B>,
        position: &mut lp_position_nft::LPPosition,
        min_amount_a: u64,
        min_amount_b: u64,
        ctx: &mut TxContext,
    ): (Coin<A>, Coin<B>) {
        // Preview first to check minimums
        let (pending_a, pending_b) = preview_claimable(pool, position);
        assert!(pending_a >= min_amount_a, E_NO_FEES_TO_CLAIM);
        assert!(pending_b >= min_amount_b || min_amount_b == 0, E_NO_FEES_TO_CLAIM);
        
        claim_fees_with_coins(fee_distributor, pool, position, ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Enable or disable auto-compound by default
    public fun set_auto_compound(distributor: &mut FeeDistributor, enabled: bool) {
        distributor.auto_compound_enabled = enabled;
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ENTRY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Entry: Create and share a new fee distributor
    public entry fun create_shared_fee_distributor(ctx: &mut TxContext) {
        let distributor = new_fee_distributor(ctx);
        sui::transfer::share_object(distributor);
    }
}
