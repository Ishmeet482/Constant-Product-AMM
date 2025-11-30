/// Unit tests for amm_router module
/// Tests: Router functions for pool creation, liquidity, and swaps
#[test_only]
#[allow(unused_use, unused_variable, unused_const, deprecated_usage)]
module sui_amm_nft_lp::amm_router_tests {
    use sui::test_scenario::{Self as ts};
    use sui_amm_nft_lp::pool_factory;
    use sui_amm_nft_lp::liquidity_pool;
    use sui_amm_nft_lp::lp_position_nft;
    use sui_amm_nft_lp::fee_distributor;
    use sui_amm_nft_lp::slippage_protection;

    struct USDC has drop {}
    struct ETH has drop {}

    const ADMIN: address = @0xAD;
    const LP1: address = @0x1;

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL CREATION WORKFLOW TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_pool_with_factory() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            let pool = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            
            // Verify pool state
            assert!(liquidity_pool::fee_bps(&pool) == 30, 0);
            assert!(pool_factory::pool_count(&factory) == 1, 1);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_create_pool_and_add_liquidity() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            let pool = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            
            // Add initial liquidity
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            assert!(shares > 0, 0);
            
            // Verify reserves
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a == 1_000_000, 1);
            assert!(reserve_b == 1_000_000, 2);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // LIQUIDITY MANAGEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_add_liquidity_to_existing_pool() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            let initial_shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Add more liquidity
            let new_shares = liquidity_pool::add_liquidity(&mut pool, 500_000, 500_000, 50);
            assert!(new_shares > 0, 0);
            
            // Verify reserves increased
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a > 1_000_000, 1);
            assert!(reserve_b > 1_000_000, 2);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_remove_liquidity_from_pool() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Remove half
            let (amount_a, amount_b) = liquidity_pool::remove_liquidity(&mut pool, shares / 2);
            assert!(amount_a > 0, 0);
            assert!(amount_b > 0, 1);
            
            // Verify reserves decreased
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a < 1_000_000, 2);
            assert!(reserve_b < 1_000_000, 3);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // SWAP WORKFLOW TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_swap_a_to_b() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let (amount_out, fee) = liquidity_pool::swap(&mut pool, 100_000, true);
            
            assert!(amount_out > 0, 0);
            assert!(fee > 0, 1);
            
            // Verify reserves changed correctly
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a > 1_000_000, 2); // A increased
            assert!(reserve_b < 1_000_000, 3); // B decreased
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_swap_b_to_a() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let (amount_out, fee) = liquidity_pool::swap(&mut pool, 100_000, false);
            
            assert!(amount_out > 0, 0);
            assert!(fee > 0, 1);
            
            // Verify reserves changed correctly
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a < 1_000_000, 2); // A decreased
            assert!(reserve_b > 1_000_000, 3); // B increased
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_swap_with_slippage_protection() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Get expected output
            let (expected_out, _) = liquidity_pool::get_amount_out(&pool, 100_000, true);
            let min_out = slippage_protection::calculate_min_output(expected_out, 50);
            
            // Execute with slippage protection
            let (actual_out, _) = liquidity_pool::swap_with_slippage(&mut pool, 100_000, min_out, true);
            
            assert!(actual_out >= min_out, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // VIEW HELPER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_get_amount_out_quote() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let (amount_out, fee) = liquidity_pool::get_amount_out(&pool, 100_000, true);
            
            // Should get reasonable output
            assert!(amount_out > 0, 0);
            assert!(amount_out < 100_000, 1); // Less than input due to fees and slippage
            assert!(fee > 0, 2);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_get_spot_price() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 2_000_000);
            
            let price_a_to_b = liquidity_pool::get_spot_price_a_to_b(&pool);
            let price_b_to_a = liquidity_pool::get_spot_price_b_to_a(&pool);
            
            // Price of A in terms of B should be ~2 (scaled by 1e8)
            // Price of B in terms of A should be ~0.5 (scaled by 1e8)
            assert!(price_a_to_b > price_b_to_a, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // LP POSITION INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_mint_lp_position_for_liquidity() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let pool_id = liquidity_pool::pool_id(&pool);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            // Mint NFT for LP
            lp_position_nft::mint(
                pool_id,
                shares,
                idx_a, idx_b,
                1_000_000, 1_000_000,
                LP1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, LP1);
        {
            let position = ts::take_from_sender<lp_position_nft::LPPosition>(&scenario);
            
            assert!(lp_position_nft::shares(&position) > 0, 0);
            
            lp_position_nft::burn(position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_position_value_calculation() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let pool_id = liquidity_pool::pool_id(&pool);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            lp_position_nft::mint(
                pool_id,
                shares,
                idx_a, idx_b,
                1_000_000, 1_000_000,
                LP1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, LP1);
        {
            let position = ts::take_from_sender<lp_position_nft::LPPosition>(&scenario);
            
            // Calculate position value
            let (value_a, value_b) = lp_position_nft::calculate_position_value(
                &position,
                1_000_000,  // reserve_a
                1_000_000,  // reserve_b
                lp_position_nft::shares(&position) + 1000  // total_shares
            );
            
            assert!(value_a > 0, 0);
            assert!(value_b > 0, 1);
            
            lp_position_nft::burn(position);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FEE CLAIMING INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_fees_accumulate_on_swaps() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let (idx_a_before, idx_b_before) = liquidity_pool::fee_indices(&pool);
            
            // Execute swaps
            liquidity_pool::swap(&mut pool, 100_000, true);
            liquidity_pool::swap(&mut pool, 50_000, false);
            
            let (idx_a_after, idx_b_after) = liquidity_pool::fee_indices(&pool);
            
            // Fee indices should increase
            assert!(idx_a_after > idx_a_before || idx_b_after > idx_b_before, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }
}
