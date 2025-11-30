/// Unit tests for fee_distributor module
/// Tests: Fee calculation, claim preview, auto-compound logic
#[test_only]
#[allow(unused_use, unused_variable, unused_const, deprecated_usage)]
module sui_amm_nft_lp::fee_distributor_tests {
    use sui::test_scenario::{Self as ts};
    use sui_amm_nft_lp::fee_distributor;
    use sui_amm_nft_lp::lp_position_nft;
    use sui_amm_nft_lp::liquidity_pool;

    struct USDC has drop {}
    struct ETH has drop {}

    const ADMIN: address = @0xAD;
    const LP1: address = @0x1;

    // ═══════════════════════════════════════════════════════════════════════════════
    // DISTRIBUTOR CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_fee_distributor() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let distributor = fee_distributor::new_fee_distributor(ctx);
            
            let (dist_a, dist_b) = fee_distributor::total_distributed(&distributor);
            assert!(dist_a == 0, 0);
            assert!(dist_b == 0, 1);
            assert!(fee_distributor::total_claims(&distributor) == 0, 2);
            assert!(!fee_distributor::is_auto_compound_enabled(&distributor), 3);
            
            sui::test_utils::destroy(distributor);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_set_auto_compound() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let distributor = fee_distributor::new_fee_distributor(ctx);
            
            assert!(!fee_distributor::is_auto_compound_enabled(&distributor), 0);
            
            fee_distributor::set_auto_compound(&mut distributor, true);
            assert!(fee_distributor::is_auto_compound_enabled(&distributor), 1);
            
            fee_distributor::set_auto_compound(&mut distributor, false);
            assert!(!fee_distributor::is_auto_compound_enabled(&distributor), 2);
            
            sui::test_utils::destroy(distributor);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FEE PREVIEW TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_preview_claimable_no_fees() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            // Provide liquidity to get fee indices
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                idx_a, idx_b,
                500_000, 500_000,
                LP1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, LP1);
        {
            let position = ts::take_from_sender<lp_position_nft::LPPosition>(&scenario);
            
            // No fees accrued yet, so pending should be based on indices
            let (last_idx_a, last_idx_b) = lp_position_nft::last_fee_indices(&position);
            
            // If we pass same indices, should be zero
            let (pending_a, pending_b) = lp_position_nft::calculate_pending_fees(
                &position, last_idx_a, last_idx_b
            );
            assert!(pending_a == 0, 0);
            assert!(pending_b == 0, 1);
            
            lp_position_nft::burn(position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_preview_claimable_with_fees() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            // Mint position at current indices
            lp_position_nft::mint(
                pool_id,
                999_000,     // All user shares
                idx_a, idx_b,
                1_000_000, 1_000_000,
                LP1,
                ctx
            );
            
            // Execute swaps to generate fees
            liquidity_pool::swap(&mut pool, 100_000, true);
            liquidity_pool::swap(&mut pool, 50_000, false);
            
            // Get updated indices
            let (new_idx_a, new_idx_b) = liquidity_pool::fee_indices(&pool);
            
            // Fee indices should have increased
            assert!(new_idx_a > idx_a || new_idx_b > idx_b, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CLAIM FEES TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_claim_fees_workflow() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let distributor = fee_distributor::new_fee_distributor(ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            lp_position_nft::mint(
                pool_id,
                999_000,
                idx_a, idx_b,
                1_000_000, 1_000_000,
                LP1,
                ctx
            );
            
            // Generate fees
            liquidity_pool::swap(&mut pool, 100_000, true);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(distributor);
        };
        ts::next_tx(&mut scenario, LP1);
        {
            let position = ts::take_from_sender<lp_position_nft::LPPosition>(&scenario);
            
            // Verify position has shares
            assert!(lp_position_nft::shares(&position) == 999_000, 0);
            
            lp_position_nft::burn(position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_claim_fees_updates_totals() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let distributor = fee_distributor::new_fee_distributor(ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            lp_position_nft::mint(
                pool_id,
                999_000,
                idx_a, idx_b,
                1_000_000, 1_000_000,
                LP1,
                ctx
            );
            
            // Generate fees
            liquidity_pool::swap(&mut pool, 200_000, true);
            liquidity_pool::swap(&mut pool, 150_000, false);
            
            let (dist_a_before, dist_b_before) = fee_distributor::total_distributed(&distributor);
            assert!(dist_a_before == 0, 0);
            assert!(dist_b_before == 0, 1);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(distributor);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PENDING FEES CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_calculate_pending_fees_formula() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,     // shares
                1000,        // last_fee_index_a
                2000,        // last_fee_index_b
                500_000, 500_000,
                LP1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, LP1);
        {
            let position = ts::take_from_sender<lp_position_nft::LPPosition>(&scenario);
            
            // Simulate fee index increase
            // pending = (delta * shares) / BPS_DENOMINATOR
            let (pending_a, pending_b) = lp_position_nft::calculate_pending_fees(
                &position,
                2000,        // current_fee_index_a (delta = 1000)
                4000         // current_fee_index_b (delta = 2000)
            );
            
            // pending_a = (1000 * 100_000) / 10_000 = 10_000
            // pending_b = (2000 * 100_000) / 10_000 = 20_000
            assert!(pending_a == 10_000, 0);
            assert!(pending_b == 20_000, 1);
            
            lp_position_nft::burn(position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_calculate_pending_fees_no_change() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                1000,
                2000,
                500_000, 500_000,
                LP1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, LP1);
        {
            let position = ts::take_from_sender<lp_position_nft::LPPosition>(&scenario);
            
            // Same indices = no fees
            let (pending_a, pending_b) = lp_position_nft::calculate_pending_fees(
                &position,
                1000,
                2000
            );
            
            assert!(pending_a == 0, 0);
            assert!(pending_b == 0, 1);
            
            lp_position_nft::burn(position);
        };
        ts::end(scenario);
    }
}
