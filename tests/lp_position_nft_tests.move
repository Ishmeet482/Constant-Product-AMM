/// Comprehensive unit tests for lp_position_nft module
/// Tests: NFT minting, burning, fee tracking, impermanent loss calculation, transfers
#[test_only]
#[allow(unused_use, deprecated_usage)]
module sui_amm_nft_lp::lp_position_nft_tests {
    use sui::test_scenario::{Self as ts};
    use sui::object;
    use sui_amm_nft_lp::lp_position_nft::{Self, LPPosition};
    use sui_amm_nft_lp::liquidity_pool;

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST COIN TYPES
    // ═══════════════════════════════════════════════════════════════════════════════

    struct USDC has drop {}
    struct ETH has drop {}

    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2;

    // ═══════════════════════════════════════════════════════════════════════════════
    // MINTING TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_mint_lp_position() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,     // lp_shares
                0,           // curr_fee_index_a
                0,           // curr_fee_index_b
                500_000,     // initial_amount_a
                1_000_000,   // initial_amount_b
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            // User should have received the NFT
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            assert!(lp_position_nft::shares(&position) == 100_000, 0);
            let (init_a, init_b) = lp_position_nft::initial_amounts(&position);
            assert!(init_a == 500_000, 1);
            assert!(init_b == 1_000_000, 2);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = lp_position_nft::E_ZERO_SHARES)]
    fun test_mint_zero_shares_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            // This should fail
            lp_position_nft::mint(
                pool_id,
                0,           // zero shares
                0, 0,
                500_000, 1_000_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_mint_with_fee_indices() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                1000,        // fee_index_a
                2000,        // fee_index_b
                500_000, 1_000_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            let (idx_a, idx_b) = lp_position_nft::last_fee_indices(&position);
            assert!(idx_a == 1000, 0);
            assert!(idx_b == 2000, 1);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // BURNING TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_burn_lp_position() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000, 0, 0,
                500_000, 1_000_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            // Burn the position
            lp_position_nft::burn(position);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_view_functions() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                500, 600,
                500_000, 1_000_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            // Test all view functions
            assert!(lp_position_nft::shares(&position) == 100_000, 0);
            
            let (init_a, init_b) = lp_position_nft::initial_amounts(&position);
            assert!(init_a == 500_000, 1);
            assert!(init_b == 1_000_000, 2);
            
            let (idx_a, idx_b) = lp_position_nft::last_fee_indices(&position);
            assert!(idx_a == 500, 3);
            assert!(idx_b == 600, 4);
            
            let (claimed_a, claimed_b) = lp_position_nft::claimed_fees(&position);
            assert!(claimed_a == 0, 5);
            assert!(claimed_b == 0, 6);
            
            let name = lp_position_nft::name(&position);
            assert!(*name == b"LP Position", 7);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // POSITION VALUE CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_calculate_position_value() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            // Position with 50% of total shares
            lp_position_nft::mint(
                pool_id,
                500_000,     // 50% of 1M total shares
                0, 0,
                500_000, 500_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            // Pool has 1M reserve_a, 2M reserve_b, 1M total shares
            // Position has 500K shares = 50% ownership
            let (value_a, value_b) = lp_position_nft::calculate_position_value(
                &position,
                1_000_000,   // pool_reserve_a
                2_000_000,   // pool_reserve_b
                1_000_000    // pool_total_shares
            );
            
            // Should get 50% of each reserve
            assert!(value_a == 500_000, 0);
            assert!(value_b == 1_000_000, 1);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_calculate_position_value_zero_shares() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                0, 0,
                500_000, 500_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            // Zero total shares should return zero value
            let (value_a, value_b) = lp_position_nft::calculate_position_value(
                &position,
                1_000_000,
                2_000_000,
                0            // zero total shares
            );
            
            assert!(value_a == 0, 0);
            assert!(value_b == 0, 1);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // IMPERMANENT LOSS CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_calculate_impermanent_loss_no_change() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                0, 0,
                500_000,     // initial_a
                500_000,     // initial_b
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            // Current value equals initial amounts - no IL
            let (il_bps, is_loss) = lp_position_nft::calculate_impermanent_loss(
                &position,
                500_000,     // current_value_a (same as initial)
                500_000      // current_value_b (same as initial)
            );
            
            assert!(il_bps == 0, 0);
            assert!(!is_loss, 1);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_calculate_impermanent_loss_positive() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                0, 0,
                1_000_000,   // initial_a
                1_000_000,   // initial_b
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            // Current value less than initial - impermanent loss
            let (il_bps, is_loss) = lp_position_nft::calculate_impermanent_loss(
                &position,
                900_000,     // current_value_a (lost 100K)
                900_000      // current_value_b (lost 100K)
            );
            
            // HODL = 2M, LP = 1.8M, loss = 10% = 1000 bps
            assert!(il_bps == 1000, 0);
            assert!(is_loss, 1);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_calculate_impermanent_gain() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                0, 0,
                1_000_000,
                1_000_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            // Current value MORE than initial - impermanent gain (from fees)
            let (gain_bps, is_loss) = lp_position_nft::calculate_impermanent_loss(
                &position,
                1_100_000,   // current_value_a (gained 100K)
                1_100_000    // current_value_b (gained 100K)
            );
            
            // HODL = 2M, LP = 2.2M, gain = 10% = 1000 bps
            assert!(gain_bps == 1000, 0);
            assert!(!is_loss, 1);  // Not a loss
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PENDING FEES CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_calculate_pending_fees() {
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
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            // Current indices are higher - fees accrued
            let (pending_a, pending_b) = lp_position_nft::calculate_pending_fees(
                &position,
                2000,        // current_fee_index_a (delta = 1000)
                4000         // current_fee_index_b (delta = 2000)
            );
            
            // pending = (delta * shares) / BPS_DENOMINATOR
            // pending_a = (1000 * 100_000) / 10_000 = 10_000
            // pending_b = (2000 * 100_000) / 10_000 = 20_000
            assert!(pending_a == 10_000, 0);
            assert!(pending_b == 20_000, 1);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_calculate_pending_fees_no_accrual() {
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
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            // Same indices - no fees accrued
            let (pending_a, pending_b) = lp_position_nft::calculate_pending_fees(
                &position,
                1000,
                2000
            );
            
            assert!(pending_a == 0, 0);
            assert!(pending_b == 0, 1);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // MUTATION FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_add_shares() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                0, 0,
                500_000, 500_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            assert!(lp_position_nft::shares(&position) == 100_000, 0);
            
            lp_position_nft::add_shares(&mut position, 50_000);
            
            assert!(lp_position_nft::shares(&position) == 150_000, 1);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_reduce_shares() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                0, 0,
                500_000, 500_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            lp_position_nft::reduce_shares(&mut position, 30_000);
            
            assert!(lp_position_nft::shares(&position) == 70_000, 0);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = lp_position_nft::E_INSUFFICIENT_SHARES)]
    fun test_reduce_shares_exceeds_balance_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                0, 0,
                500_000, 500_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            // Try to reduce more than available
            lp_position_nft::reduce_shares(&mut position, 150_000);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_update_metadata() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                1000, 2000,
                500_000, 500_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            // Update metadata after claiming fees
            lp_position_nft::update_metadata(
                &mut position,
                3000,        // new_last_index_a
                4000,        // new_last_index_b
                500,         // claimed_delta_a
                1000         // claimed_delta_b
            );
            
            let (idx_a, idx_b) = lp_position_nft::last_fee_indices(&position);
            assert!(idx_a == 3000, 0);
            assert!(idx_b == 4000, 1);
            
            let (claimed_a, claimed_b) = lp_position_nft::claimed_fees(&position);
            assert!(claimed_a == 500, 2);
            assert!(claimed_b == 1000, 3);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_update_initial_amounts() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                0, 0,
                500_000, 500_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            lp_position_nft::update_initial_amounts(&mut position, 100_000, 200_000);
            
            let (init_a, init_b) = lp_position_nft::initial_amounts(&position);
            assert!(init_a == 600_000, 0);
            assert!(init_b == 700_000, 1);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_set_name() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                0, 0,
                500_000, 500_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            assert!(*lp_position_nft::name(&position) == b"LP Position", 0);
            
            lp_position_nft::set_name(&mut position, b"My Custom LP");
            
            assert!(*lp_position_nft::name(&position) == b"My Custom LP", 1);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_transfer_position() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            lp_position_nft::mint(
                pool_id,
                100_000,
                0, 0,
                500_000, 500_000,
                USER1,
                ctx
            );
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, USER1);
        {
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            // Transfer to USER2
            lp_position_nft::transfer_position(position, USER2);
        };
        ts::next_tx(&mut scenario, USER2);
        {
            // USER2 should now own the position
            let position = ts::take_from_sender<LPPosition>(&scenario);
            
            assert!(lp_position_nft::shares(&position) == 100_000, 0);
            
            ts::return_to_sender(&scenario, position);
        };
        ts::end(scenario);
    }
}
