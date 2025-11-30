#[allow(lint(public_entry), unused_use)]
module sui_amm_nft_lp::pool_factory {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::TxContext;
    use sui::event;
    use sui::transfer;

    use sui_amm_nft_lp::liquidity_pool;

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Supported fee tiers in basis points.
    const FEE_TIER_LOW: u64 = 5;      // 0.05% - for stable pairs
    const FEE_TIER_MEDIUM: u64 = 30;  // 0.30% - standard pairs
    const FEE_TIER_HIGH: u64 = 100;   // 1.00% - exotic pairs

    // ═══════════════════════════════════════════════════════════════════════════════
    // ERROR CODES
    // ═══════════════════════════════════════════════════════════════════════════════

    const E_INVALID_FEE_TIER: u64 = 1;
    const E_PAUSED: u64 = 2;
    const E_NOT_AUTHORIZED: u64 = 3;

    // ═══════════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Factory for creating and tracking liquidity pools
    struct PoolFactory has key {
        id: UID,
        /// Total number of pools created
        pool_count: u64,
        /// Protocol fee recipient address
        fee_recipient: address,
        /// Whether pool creation is paused
        paused: bool,
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Emitted when a new pool is created
    struct PoolCreated has copy, drop {
        pool_id: ID,
        fee_bps: u64,
        pool_index: u64,
        creator: address,
    }

    /// Emitted when factory settings are updated
    struct FactoryUpdated has copy, drop {
        fee_recipient: address,
        paused: bool,
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FACTORY CREATION
    // ═══════════════════════════════════════════════════════════════════════════════

    public fun new_factory(fee_recipient: address, ctx: &mut TxContext): PoolFactory {
        PoolFactory {
            id: object::new(ctx),
            pool_count: 0,
            fee_recipient,
            paused: false,
        }
    }

    /// Convenience constructor with sender as fee recipient
    public fun new_factory_default(ctx: &mut TxContext): PoolFactory {
        new_factory(sui::tx_context::sender(ctx), ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    public fun pool_count(factory: &PoolFactory): u64 {
        factory.pool_count
    }

    public fun fee_recipient(factory: &PoolFactory): address {
        factory.fee_recipient
    }

    public fun is_paused(factory: &PoolFactory): bool {
        factory.paused
    }

    /// Get all supported fee tiers
    public fun get_fee_tiers(): (u64, u64, u64) {
        (FEE_TIER_LOW, FEE_TIER_MEDIUM, FEE_TIER_HIGH)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL CREATION
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Create a constant-product pool for types A and B at a given fee tier.
    /// Returns the newly created pool object.
    public fun create_pool<A, B>(
        factory: &mut PoolFactory,
        fee_tier_bps: u64,
        ctx: &mut TxContext,
    ): liquidity_pool::LiquidityPool<A, B> {
        assert!(!factory.paused, 0);

        let fee_bps = normalize_fee_tier(fee_tier_bps);
        let pool = liquidity_pool::new_pool<A, B>(fee_bps, ctx);
        let pool_id = liquidity_pool::pool_id(&pool);

        // Increment pool counter
        factory.pool_count = factory.pool_count + 1;

        // Emit creation event for indexing
        event::emit(PoolCreated {
            pool_id,
            fee_bps,
            pool_index: factory.pool_count,
            creator: sui::tx_context::sender(ctx),
        });

        pool
    }

    /// Create pool with low fee tier (0.05%) - ideal for stable pairs
    public fun create_stable_pool<A, B>(
        factory: &mut PoolFactory,
        ctx: &mut TxContext,
    ): liquidity_pool::LiquidityPool<A, B> {
        create_pool<A, B>(factory, FEE_TIER_LOW, ctx)
    }

    /// Create pool with medium fee tier (0.30%) - standard trading pairs
    public fun create_standard_pool<A, B>(
        factory: &mut PoolFactory,
        ctx: &mut TxContext,
    ): liquidity_pool::LiquidityPool<A, B> {
        create_pool<A, B>(factory, FEE_TIER_MEDIUM, ctx)
    }

    /// Create pool with high fee tier (1%) - exotic/volatile pairs
    public fun create_exotic_pool<A, B>(
        factory: &mut PoolFactory,
        ctx: &mut TxContext,
    ): liquidity_pool::LiquidityPool<A, B> {
        create_pool<A, B>(factory, FEE_TIER_HIGH, ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Update fee recipient address
    public fun set_fee_recipient(
        factory: &mut PoolFactory,
        new_recipient: address,
    ) {
        factory.fee_recipient = new_recipient;
        event::emit(FactoryUpdated {
            fee_recipient: factory.fee_recipient,
            paused: factory.paused,
        });
    }

    /// Pause/unpause pool creation
    public fun set_paused(
        factory: &mut PoolFactory,
        paused: bool,
    ) {
        factory.paused = paused;
        event::emit(FactoryUpdated {
            fee_recipient: factory.fee_recipient,
            paused: factory.paused,
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ENTRY FUNCTIONS (for direct CLI/transaction calls)
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Entry: Create and share a new factory
    public entry fun create_shared_factory(ctx: &mut TxContext) {
        let factory = new_factory_default(ctx);
        transfer::share_object(factory);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Normalize incoming fee tier into one of the supported values.
    fun normalize_fee_tier(fee_tier_bps: u64): u64 {
        if (fee_tier_bps == FEE_TIER_LOW) {
            FEE_TIER_LOW
        } else if (fee_tier_bps == FEE_TIER_MEDIUM) {
            FEE_TIER_MEDIUM
        } else if (fee_tier_bps == FEE_TIER_HIGH) {
            FEE_TIER_HIGH
        } else {
            abort E_INVALID_FEE_TIER
        }
    }
}
