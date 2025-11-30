/// Pool Registry Module
/// Provides pool lookup by token pair and prevents duplicate pools.
/// Implements Step 2 (duplicate validation) and Step 8 (registry indexing) of pool creation.
#[allow(unused_const)]
module sui_amm_nft_lp::pool_registry {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::event;
    use sui::table::{Self, Table};
    use std::type_name::{Self, TypeName};

    // ═══════════════════════════════════════════════════════════════════════════════
    // ERROR CODES
    // ═══════════════════════════════════════════════════════════════════════════════

    const E_POOL_ALREADY_EXISTS: u64 = 1;
    const E_POOL_NOT_FOUND: u64 = 2;

    // ═══════════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Unique key for a pool: token pair + fee tier
    struct PoolKey has copy, drop, store {
        token_a: TypeName,
        token_b: TypeName,
        fee_bps: u64,
    }

    /// Pool metadata stored in registry
    struct PoolEntry has store, copy, drop {
        pool_id: ID,
        fee_bps: u64,
        created_at: u64,
        creator: address,
        is_active: bool,
    }

    /// Global pool registry - shared object
    struct PoolRegistry has key {
        id: UID,
        /// Main index: PoolKey → PoolEntry
        pools: Table<PoolKey, PoolEntry>,
        /// All pool IDs for enumeration
        all_pools: vector<ID>,
        /// Count of active pools
        active_count: u64,
        /// Total pools ever created
        total_count: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════

    struct PoolRegistered has copy, drop {
        pool_id: ID,
        token_a: TypeName,
        token_b: TypeName,
        fee_bps: u64,
        creator: address,
    }

    struct PoolDeactivated has copy, drop {
        pool_id: ID,
    }

    struct PoolReactivated has copy, drop {
        pool_id: ID,
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // REGISTRY CREATION
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Create a new pool registry
    public fun new_registry(ctx: &mut TxContext): PoolRegistry {
        PoolRegistry {
            id: object::new(ctx),
            pools: table::new(ctx),
            all_pools: std::vector::empty(),
            active_count: 0,
            total_count: 0,
        }
    }

    /// Create and share a pool registry (entry point)
    public entry fun create_shared_registry(ctx: &mut TxContext) {
        let registry = new_registry(ctx);
        transfer::share_object(registry);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL REGISTRATION (Step 2 & 8)
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Check if a pool already exists for the given token pair and fee tier.
    /// This implements Step 2: duplicate validation.
    public fun pool_exists<A, B>(
        registry: &PoolRegistry,
        fee_bps: u64,
    ): bool {
        let key = make_pool_key<A, B>(fee_bps);
        table::contains(&registry.pools, key)
    }

    /// Assert that a pool does NOT exist (for use before creation)
    public fun assert_pool_not_exists<A, B>(
        registry: &PoolRegistry,
        fee_bps: u64,
    ) {
        assert!(!pool_exists<A, B>(registry, fee_bps), E_POOL_ALREADY_EXISTS);
    }

    /// Register a new pool in the registry.
    /// Call this AFTER creating the pool via pool_factory.
    /// This implements Step 8: pool indexing.
    public fun register_pool<A, B>(
        registry: &mut PoolRegistry,
        pool_id: ID,
        fee_bps: u64,
        creator: address,
        ctx: &TxContext,
    ) {
        let key = make_pool_key<A, B>(fee_bps);
        
        // Step 2: Validate no duplicate exists
        assert!(!table::contains(&registry.pools, key), E_POOL_ALREADY_EXISTS);

        let entry = PoolEntry {
            pool_id,
            fee_bps,
            created_at: sui::tx_context::epoch(ctx),
            creator,
            is_active: true,
        };

        // Step 8: Index the pool
        table::add(&mut registry.pools, key, entry);
        std::vector::push_back(&mut registry.all_pools, pool_id);
        registry.active_count = registry.active_count + 1;
        registry.total_count = registry.total_count + 1;

        let (token_a, token_b) = get_ordered_types<A, B>();
        event::emit(PoolRegistered {
            pool_id,
            token_a,
            token_b,
            fee_bps,
            creator,
        });
    }

    /// Combined check and register - validates then registers
    public fun validate_and_register<A, B>(
        registry: &mut PoolRegistry,
        pool_id: ID,
        fee_bps: u64,
        creator: address,
        ctx: &TxContext,
    ) {
        // This will abort if pool exists
        register_pool<A, B>(registry, pool_id, fee_bps, creator, ctx);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL LOOKUP
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Get pool ID for a token pair and fee tier
    public fun get_pool<A, B>(
        registry: &PoolRegistry,
        fee_bps: u64,
    ): ID {
        let key = make_pool_key<A, B>(fee_bps);
        assert!(table::contains(&registry.pools, key), E_POOL_NOT_FOUND);
        let entry = table::borrow(&registry.pools, key);
        entry.pool_id
    }

    /// Get pool ID if it exists, otherwise return option
    public fun try_get_pool<A, B>(
        registry: &PoolRegistry,
        fee_bps: u64,
    ): (bool, ID) {
        let key = make_pool_key<A, B>(fee_bps);
        if (table::contains(&registry.pools, key)) {
            let entry = table::borrow(&registry.pools, key);
            (true, entry.pool_id)
        } else {
            (false, object::id_from_address(@0x0))
        }
    }

    /// Get full pool entry details
    public fun get_pool_entry<A, B>(
        registry: &PoolRegistry,
        fee_bps: u64,
    ): PoolEntry {
        let key = make_pool_key<A, B>(fee_bps);
        assert!(table::contains(&registry.pools, key), E_POOL_NOT_FOUND);
        *table::borrow(&registry.pools, key)
    }

    /// Check if a specific pool is active
    public fun is_pool_active<A, B>(
        registry: &PoolRegistry,
        fee_bps: u64,
    ): bool {
        let key = make_pool_key<A, B>(fee_bps);
        if (!table::contains(&registry.pools, key)) {
            return false
        };
        let entry = table::borrow(&registry.pools, key);
        entry.is_active
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Deactivate a pool (admin function)
    public fun deactivate_pool<A, B>(
        registry: &mut PoolRegistry,
        fee_bps: u64,
    ) {
        let key = make_pool_key<A, B>(fee_bps);
        assert!(table::contains(&registry.pools, key), E_POOL_NOT_FOUND);
        
        let entry = table::borrow_mut(&mut registry.pools, key);
        if (entry.is_active) {
            entry.is_active = false;
            registry.active_count = registry.active_count - 1;
            event::emit(PoolDeactivated { pool_id: entry.pool_id });
        };
    }

    /// Reactivate a pool (admin function)
    public fun reactivate_pool<A, B>(
        registry: &mut PoolRegistry,
        fee_bps: u64,
    ) {
        let key = make_pool_key<A, B>(fee_bps);
        assert!(table::contains(&registry.pools, key), E_POOL_NOT_FOUND);
        
        let entry = table::borrow_mut(&mut registry.pools, key);
        if (!entry.is_active) {
            entry.is_active = true;
            registry.active_count = registry.active_count + 1;
            event::emit(PoolReactivated { pool_id: entry.pool_id });
        };
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Total number of pools ever created
    public fun total_pools(registry: &PoolRegistry): u64 {
        registry.total_count
    }

    /// Number of currently active pools
    public fun active_pools(registry: &PoolRegistry): u64 {
        registry.active_count
    }

    /// Get all pool IDs (for enumeration)
    public fun all_pool_ids(registry: &PoolRegistry): &vector<ID> {
        &registry.all_pools
    }

    /// PoolEntry accessors
    public fun entry_pool_id(entry: &PoolEntry): ID { entry.pool_id }
    public fun entry_fee_bps(entry: &PoolEntry): u64 { entry.fee_bps }
    public fun entry_created_at(entry: &PoolEntry): u64 { entry.created_at }
    public fun entry_creator(entry: &PoolEntry): address { entry.creator }
    public fun entry_is_active(entry: &PoolEntry): bool { entry.is_active }

    // ═══════════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Create a PoolKey with tokens in canonical order
    fun make_pool_key<A, B>(fee_bps: u64): PoolKey {
        let (token_a, token_b) = get_ordered_types<A, B>();
        PoolKey { token_a, token_b, fee_bps }
    }

    /// Get type names in canonical (sorted) order
    /// This ensures (A, B) and (B, A) map to the same key
    fun get_ordered_types<A, B>(): (TypeName, TypeName) {
        let type_a = type_name::get<A>();
        let type_b = type_name::get<B>();
        
        let str_a = type_name::into_string(type_a);
        let str_b = type_name::into_string(type_b);
        
        // Compare lexicographically - smaller one goes first
        if (is_less_than(&str_a, &str_b)) {
            (type_name::get<A>(), type_name::get<B>())
        } else {
            (type_name::get<B>(), type_name::get<A>())
        }
    }

    /// Compare two ASCII strings lexicographically
    fun is_less_than(a: &std::ascii::String, b: &std::ascii::String): bool {
        let bytes_a = std::ascii::as_bytes(a);
        let bytes_b = std::ascii::as_bytes(b);
        compare_bytes(bytes_a, bytes_b, 0)
    }

    /// Recursive byte comparison
    fun compare_bytes(a: &vector<u8>, b: &vector<u8>, i: u64): bool {
        let len_a = std::vector::length(a);
        let len_b = std::vector::length(b);
        
        if (i >= len_a && i >= len_b) {
            return false // Equal
        };
        if (i >= len_a) {
            return true // a is shorter, so a < b
        };
        if (i >= len_b) {
            return false // b is shorter, so a > b
        };
        
        let byte_a = *std::vector::borrow(a, i);
        let byte_b = *std::vector::borrow(b, i);
        
        if (byte_a < byte_b) {
            true
        } else if (byte_a > byte_b) {
            false
        } else {
            compare_bytes(a, b, i + 1)
        }
    }
}
