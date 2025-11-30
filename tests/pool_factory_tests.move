/// Comprehensive unit tests for pool_factory module
/// Tests: Factory creation, pool creation, fee tier management, admin functions
#[test_only]
module sui_amm_nft_lp::pool_factory_tests {
    use sui::test_scenario::{Self as ts};
    use sui_amm_nft_lp::pool_factory::{Self, PoolFactory};
    use sui_amm_nft_lp::liquidity_pool;

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST COIN TYPES
    // ═══════════════════════════════════════════════════════════════════════════════

    struct USDC has drop {}
    struct USDT has drop {}
    struct ETH has drop {}
    struct BTC has drop {}

    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;

    // ═══════════════════════════════════════════════════════════════════════════════
    // FACTORY CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_factory() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory(ADMIN, ctx);
            
            assert!(pool_factory::pool_count(&factory) == 0, 0);
            assert!(pool_factory::fee_recipient(&factory) == ADMIN, 1);
            assert!(!pool_factory::is_paused(&factory), 2);
            
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_create_factory_default() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            assert!(pool_factory::fee_recipient(&factory) == ADMIN, 0);
            
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_get_fee_tiers() {
        let (low, medium, high) = pool_factory::get_fee_tiers();
        
        assert!(low == 5, 0);      // 0.05%
        assert!(medium == 30, 1);  // 0.30%
        assert!(high == 100, 2);   // 1.00%
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_pool_low_fee() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            let pool = pool_factory::create_stable_pool<USDC, USDT>(&mut factory, ctx);
            
            assert!(liquidity_pool::fee_bps(&pool) == 5, 0); // 0.05%
            assert!(pool_factory::pool_count(&factory) == 1, 1);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_create_pool_medium_fee() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            let pool = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            
            assert!(liquidity_pool::fee_bps(&pool) == 30, 0); // 0.30%
            assert!(pool_factory::pool_count(&factory) == 1, 1);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_create_pool_high_fee() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            let pool = pool_factory::create_exotic_pool<ETH, BTC>(&mut factory, ctx);
            
            assert!(liquidity_pool::fee_bps(&pool) == 100, 0); // 1.00%
            assert!(pool_factory::pool_count(&factory) == 1, 1);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_create_pool_custom_fee() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            // Use standard fee tier
            let pool = pool_factory::create_pool<USDC, ETH>(&mut factory, 30, ctx);
            
            assert!(liquidity_pool::fee_bps(&pool) == 30, 0);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_create_pool_invalid_fee_tier_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            // 50 bps is not a valid fee tier
            let pool = pool_factory::create_pool<USDC, ETH>(&mut factory, 50, ctx);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_pool_count_increments() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            assert!(pool_factory::pool_count(&factory) == 0, 0);
            
            let pool1 = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            assert!(pool_factory::pool_count(&factory) == 1, 1);
            
            sui::test_utils::destroy(pool1);
            sui::test_utils::destroy(factory);
        };
        ts::next_tx(&mut scenario, ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            let pool1 = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            let pool2 = pool_factory::create_stable_pool<USDC, USDT>(&mut factory, ctx);
            let pool3 = pool_factory::create_exotic_pool<ETH, BTC>(&mut factory, ctx);
            
            assert!(pool_factory::pool_count(&factory) == 3, 2);
            
            sui::test_utils::destroy(pool1);
            sui::test_utils::destroy(pool2);
            sui::test_utils::destroy(pool3);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_fee_recipient() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            assert!(pool_factory::fee_recipient(&factory) == ADMIN, 0);
            
            pool_factory::set_fee_recipient(&mut factory, USER1);
            
            assert!(pool_factory::fee_recipient(&factory) == USER1, 1);
            
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_pause_and_unpause() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            assert!(!pool_factory::is_paused(&factory), 0);
            
            pool_factory::set_paused(&mut factory, true);
            assert!(pool_factory::is_paused(&factory), 1);
            
            pool_factory::set_paused(&mut factory, false);
            assert!(!pool_factory::is_paused(&factory), 2);
            
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_create_pool_when_paused_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            pool_factory::set_paused(&mut factory, true);
            
            // This should fail because factory is paused
            let pool = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_create_pool_after_unpause() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            pool_factory::set_paused(&mut factory, true);
            pool_factory::set_paused(&mut factory, false);
            
            // This should succeed after unpause
            let pool = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            
            assert!(pool_factory::pool_count(&factory) == 1, 0);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // MULTIPLE POOLS TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_multiple_pools_same_pair_different_fees() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            // Create same pair at different fee tiers
            let pool_low = pool_factory::create_stable_pool<USDC, ETH>(&mut factory, ctx);
            let pool_med = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            let pool_high = pool_factory::create_exotic_pool<USDC, ETH>(&mut factory, ctx);
            
            assert!(liquidity_pool::fee_bps(&pool_low) == 5, 0);
            assert!(liquidity_pool::fee_bps(&pool_med) == 30, 1);
            assert!(liquidity_pool::fee_bps(&pool_high) == 100, 2);
            assert!(pool_factory::pool_count(&factory) == 3, 3);
            
            sui::test_utils::destroy(pool_low);
            sui::test_utils::destroy(pool_med);
            sui::test_utils::destroy(pool_high);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_create_different_pair_pools() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            let pool1 = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            let pool2 = pool_factory::create_standard_pool<USDC, BTC>(&mut factory, ctx);
            let pool3 = pool_factory::create_standard_pool<ETH, BTC>(&mut factory, ctx);
            let pool4 = pool_factory::create_stable_pool<USDC, USDT>(&mut factory, ctx);
            
            assert!(pool_factory::pool_count(&factory) == 4, 0);
            
            // Verify each pool has correct fee
            assert!(liquidity_pool::fee_bps(&pool1) == 30, 1);
            assert!(liquidity_pool::fee_bps(&pool2) == 30, 2);
            assert!(liquidity_pool::fee_bps(&pool3) == 30, 3);
            assert!(liquidity_pool::fee_bps(&pool4) == 5, 4);
            
            sui::test_utils::destroy(pool1);
            sui::test_utils::destroy(pool2);
            sui::test_utils::destroy(pool3);
            sui::test_utils::destroy(pool4);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL CREATION WITH LIQUIDITY WORKFLOW TEST
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_pool_creation_and_initial_liquidity() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            let pool = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            
            // Pool should start empty
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a == 0 && reserve_b == 0, 0);
            
            // Provide initial liquidity
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 2_000_000);
            assert!(shares > 0, 1);
            
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a == 1_000_000, 2);
            assert!(reserve_b == 2_000_000, 3);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }
}
