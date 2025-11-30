/// Unit tests for pool_registry module
/// Tests: Duplicate prevention, pool lookup, registration workflow
#[test_only]
#[allow(unused_use, unused_variable, deprecated_usage)]
module sui_amm_nft_lp::pool_registry_tests {
    use sui::test_scenario::{Self as ts};
    use sui::object;
    use sui_amm_nft_lp::pool_registry::{Self, PoolRegistry};
    use sui_amm_nft_lp::pool_factory;
    use sui_amm_nft_lp::liquidity_pool;
    use sui_amm_nft_lp::amm_router;

    struct USDC has drop {}
    struct ETH has drop {}
    struct BTC has drop {}

    const ADMIN: address = @0xAD;
    const LP1: address = @0x1;

    // ═══════════════════════════════════════════════════════════════════════════════
    // REGISTRY CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_registry() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let registry = pool_registry::new_registry(ctx);
            
            assert!(pool_registry::total_pools(&registry) == 0, 0);
            assert!(pool_registry::active_pools(&registry) == 0, 1);
            
            sui::test_utils::destroy(registry);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL REGISTRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_register_pool() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let registry = pool_registry::new_registry(ctx);
            let factory = pool_factory::new_factory_default(ctx);
            
            // Create a pool
            let pool = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            // Register it
            pool_registry::register_pool<USDC, ETH>(
                &mut registry,
                pool_id,
                30, // 0.30% fee
                ADMIN,
                ctx
            );
            
            // Verify registration
            assert!(pool_registry::total_pools(&registry) == 1, 0);
            assert!(pool_registry::active_pools(&registry) == 1, 1);
            assert!(pool_registry::pool_exists<USDC, ETH>(&registry, 30), 2);
            
            // Lookup should return correct pool ID
            let found_id = pool_registry::get_pool<USDC, ETH>(&registry, 30);
            assert!(found_id == pool_id, 3);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
            sui::test_utils::destroy(registry);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // DUPLICATE PREVENTION TESTS (Step 2)
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    #[expected_failure(abort_code = pool_registry::E_POOL_ALREADY_EXISTS)]
    fun test_duplicate_pool_prevention() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let registry = pool_registry::new_registry(ctx);
            let factory = pool_factory::new_factory_default(ctx);
            
            // Create and register first pool
            let pool1 = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            let pool1_id = liquidity_pool::pool_id(&pool1);
            
            pool_registry::register_pool<USDC, ETH>(
                &mut registry,
                pool1_id,
                30,
                ADMIN,
                ctx
            );
            
            // Try to register duplicate - should FAIL
            let pool2 = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            let pool2_id = liquidity_pool::pool_id(&pool2);
            
            // This should abort with E_POOL_ALREADY_EXISTS
            pool_registry::register_pool<USDC, ETH>(
                &mut registry,
                pool2_id,
                30, // Same fee tier
                ADMIN,
                ctx
            );
            
            sui::test_utils::destroy(pool1);
            sui::test_utils::destroy(pool2);
            sui::test_utils::destroy(factory);
            sui::test_utils::destroy(registry);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_same_pair_different_fee_tiers_allowed() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let registry = pool_registry::new_registry(ctx);
            let factory = pool_factory::new_factory_default(ctx);
            
            // Create USDC/ETH at 0.05% fee
            let pool1 = pool_factory::create_stable_pool<USDC, ETH>(&mut factory, ctx);
            pool_registry::register_pool<USDC, ETH>(
                &mut registry,
                liquidity_pool::pool_id(&pool1),
                5, // 0.05%
                ADMIN,
                ctx
            );
            
            // Create USDC/ETH at 0.30% fee - should succeed (different fee tier)
            let pool2 = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            pool_registry::register_pool<USDC, ETH>(
                &mut registry,
                liquidity_pool::pool_id(&pool2),
                30, // 0.30%
                ADMIN,
                ctx
            );
            
            // Create USDC/ETH at 1.00% fee - should also succeed
            let pool3 = pool_factory::create_exotic_pool<USDC, ETH>(&mut factory, ctx);
            pool_registry::register_pool<USDC, ETH>(
                &mut registry,
                liquidity_pool::pool_id(&pool3),
                100, // 1.00%
                ADMIN,
                ctx
            );
            
            // All three should exist
            assert!(pool_registry::pool_exists<USDC, ETH>(&registry, 5), 0);
            assert!(pool_registry::pool_exists<USDC, ETH>(&registry, 30), 1);
            assert!(pool_registry::pool_exists<USDC, ETH>(&registry, 100), 2);
            assert!(pool_registry::total_pools(&registry) == 3, 3);
            
            sui::test_utils::destroy(pool1);
            sui::test_utils::destroy(pool2);
            sui::test_utils::destroy(pool3);
            sui::test_utils::destroy(factory);
            sui::test_utils::destroy(registry);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_token_order_independence() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let registry = pool_registry::new_registry(ctx);
            let factory = pool_factory::new_factory_default(ctx);
            
            // Register USDC/ETH
            let pool = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            pool_registry::register_pool<USDC, ETH>(
                &mut registry,
                liquidity_pool::pool_id(&pool),
                30,
                ADMIN,
                ctx
            );
            
            // Looking up ETH/USDC should find the same pool
            // (token order should be normalized)
            assert!(pool_registry::pool_exists<USDC, ETH>(&registry, 30), 0);
            assert!(pool_registry::pool_exists<ETH, USDC>(&registry, 30), 1);
            
            let id1 = pool_registry::get_pool<USDC, ETH>(&registry, 30);
            let id2 = pool_registry::get_pool<ETH, USDC>(&registry, 30);
            assert!(id1 == id2, 2);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
            sui::test_utils::destroy(registry);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FULL WORKFLOW TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_full_workflow_with_registry() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let registry = pool_registry::new_registry(ctx);
            let factory = pool_factory::new_factory_default(ctx);
            
            // Use the full workflow function
            let pool = amm_router::create_pool_full_workflow<USDC, ETH>(
                &mut factory,
                &mut registry,
                30,
                1_000_000,
                1_000_000,
                LP1,
                ctx
            );
            
            // Verify pool was created and registered
            assert!(pool_registry::pool_exists<USDC, ETH>(&registry, 30), 0);
            assert!(pool_registry::total_pools(&registry) == 1, 1);
            
            // Verify pool has liquidity
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a == 1_000_000, 2);
            assert!(reserve_b == 1_000_000, 3);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
            sui::test_utils::destroy(registry);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = pool_registry::E_POOL_ALREADY_EXISTS)]
    fun test_full_workflow_prevents_duplicate() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let registry = pool_registry::new_registry(ctx);
            let factory = pool_factory::new_factory_default(ctx);
            
            // First pool - should succeed
            let pool1 = amm_router::create_pool_full_workflow<USDC, ETH>(
                &mut factory,
                &mut registry,
                30,
                1_000_000,
                1_000_000,
                LP1,
                ctx
            );
            
            // Second pool with same pair and fee - should FAIL
            let pool2 = amm_router::create_pool_full_workflow<USDC, ETH>(
                &mut factory,
                &mut registry,
                30, // Same fee tier
                500_000,
                500_000,
                LP1,
                ctx
            );
            
            sui::test_utils::destroy(pool1);
            sui::test_utils::destroy(pool2);
            sui::test_utils::destroy(factory);
            sui::test_utils::destroy(registry);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL DEACTIVATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_deactivate_reactivate_pool() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let registry = pool_registry::new_registry(ctx);
            let factory = pool_factory::new_factory_default(ctx);
            
            let pool = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            pool_registry::register_pool<USDC, ETH>(
                &mut registry,
                liquidity_pool::pool_id(&pool),
                30,
                ADMIN,
                ctx
            );
            
            assert!(pool_registry::is_pool_active<USDC, ETH>(&registry, 30), 0);
            assert!(pool_registry::active_pools(&registry) == 1, 1);
            
            // Deactivate
            pool_registry::deactivate_pool<USDC, ETH>(&mut registry, 30);
            assert!(!pool_registry::is_pool_active<USDC, ETH>(&registry, 30), 2);
            assert!(pool_registry::active_pools(&registry) == 0, 3);
            assert!(pool_registry::total_pools(&registry) == 1, 4); // Still tracked
            
            // Reactivate
            pool_registry::reactivate_pool<USDC, ETH>(&mut registry, 30);
            assert!(pool_registry::is_pool_active<USDC, ETH>(&registry, 30), 5);
            assert!(pool_registry::active_pools(&registry) == 1, 6);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
            sui::test_utils::destroy(registry);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // LOOKUP TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_try_get_pool() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let registry = pool_registry::new_registry(ctx);
            let factory = pool_factory::new_factory_default(ctx);
            
            // Non-existent pool
            let (exists, _) = pool_registry::try_get_pool<USDC, ETH>(&registry, 30);
            assert!(!exists, 0);
            
            // Create and register
            let pool = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            pool_registry::register_pool<USDC, ETH>(
                &mut registry,
                pool_id,
                30,
                ADMIN,
                ctx
            );
            
            // Now it should exist
            let (exists2, found_id) = pool_registry::try_get_pool<USDC, ETH>(&registry, 30);
            assert!(exists2, 1);
            assert!(found_id == pool_id, 2);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
            sui::test_utils::destroy(registry);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = pool_registry::E_POOL_NOT_FOUND)]
    fun test_get_nonexistent_pool_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let registry = pool_registry::new_registry(ctx);
            
            // This should abort
            let _ = pool_registry::get_pool<USDC, ETH>(&registry, 30);
            
            sui::test_utils::destroy(registry);
        };
        ts::end(scenario);
    }
}
