/// Comprehensive unit tests for liquidity_pool module
/// Tests: AMM math, constant product formula, swaps, liquidity management, fee calculation
#[test_only]
module sui_amm_nft_lp::liquidity_pool_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui_amm_nft_lp::liquidity_pool::{Self, LiquidityPool};

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST COIN TYPES
    // ═══════════════════════════════════════════════════════════════════════════════

    struct USDC has drop {}
    struct USDT has drop {}
    struct ETH has drop {}

    const BPS_DENOMINATOR: u64 = 10_000;
    const ADMIN: address = @0xAD;

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_pool_with_valid_fee() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx); // 0.3% fee
            
            assert!(liquidity_pool::fee_bps(&pool) == 30, 0);
            assert!(liquidity_pool::total_shares(&pool) == 0, 1);
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a == 0 && reserve_b == 0, 2);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_create_pool_with_different_fee_tiers() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // Low fee tier (0.05%)
            let pool_low = liquidity_pool::new_pool<USDC, ETH>(5, ctx);
            assert!(liquidity_pool::fee_bps(&pool_low) == 5, 0);
            sui::test_utils::destroy(pool_low);
        };
        ts::next_tx(&mut scenario, ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // Medium fee tier (0.3%)
            let pool_med = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            assert!(liquidity_pool::fee_bps(&pool_med) == 30, 1);
            sui::test_utils::destroy(pool_med);
        };
        ts::next_tx(&mut scenario, ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // High fee tier (1%)
            let pool_high = liquidity_pool::new_pool<USDC, ETH>(100, ctx);
            assert!(liquidity_pool::fee_bps(&pool_high) == 100, 2);
            sui::test_utils::destroy(pool_high);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = liquidity_pool::E_INVALID_FEE)]
    fun test_create_pool_fee_too_high_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(1001, ctx); // > 10%
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // INITIAL LIQUIDITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_provide_initial_liquidity() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            let amount_a = 1_000_000;
            let amount_b = 2_000_000;
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, amount_a, amount_b);
            
            // Shares = sqrt(amount_a * amount_b) - MINIMUM_LIQUIDITY
            // sqrt(1_000_000 * 2_000_000) = sqrt(2_000_000_000_000) ≈ 1_414_213
            // shares = 1_414_213 - 1000 = 1_413_213
            assert!(shares > 0, 0);
            
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a == amount_a, 1);
            assert!(reserve_b == amount_b, 2);
            
            // Total shares includes MINIMUM_LIQUIDITY
            assert!(liquidity_pool::total_shares(&pool) == shares + 1000, 3);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_initial_liquidity_geometric_mean() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            // Equal amounts: sqrt(1M * 1M) = 1M
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            // shares = 1_000_000 - 1000 = 999_000
            assert!(shares == 999_000, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = liquidity_pool::E_ZERO_LIQUIDITY)]
    fun test_initial_liquidity_zero_amount_a_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool, 0, 1_000_000);
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = liquidity_pool::E_ZERO_LIQUIDITY)]
    fun test_initial_liquidity_zero_amount_b_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 0);
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ADD LIQUIDITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_add_liquidity_maintains_ratio() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            // Initial liquidity: 1:2 ratio
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 2_000_000);
            
            // Add more liquidity at same ratio
            let new_shares = liquidity_pool::add_liquidity(&mut pool, 500_000, 1_000_000, 50);
            assert!(new_shares > 0, 0);
            
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a == 1_500_000, 1);
            assert!(reserve_b == 3_000_000, 2);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_add_liquidity_within_tolerance() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 2_000_000);
            
            // Slight deviation within 0.5% tolerance
            // Required B = 500_000 * 2 = 1_000_000
            // Adding 1_004_000 is 0.4% off - within tolerance
            let new_shares = liquidity_pool::add_liquidity(&mut pool, 500_000, 1_004_000, 50);
            assert!(new_shares > 0, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = liquidity_pool::E_INVALID_RATIO)]
    fun test_add_liquidity_exceeds_tolerance_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 2_000_000);
            
            // Required B = 500_000 * 2 = 1_000_000
            // Adding 1_100_000 is 10% off - exceeds tolerance
            liquidity_pool::add_liquidity(&mut pool, 500_000, 1_100_000, 50);
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_add_liquidity_share_calculation() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let total_before = liquidity_pool::total_shares(&pool);
            
            // Adding 50% more liquidity should mint ~50% more shares
            let new_shares = liquidity_pool::add_liquidity(&mut pool, 500_000, 500_000, 50);
            let total_after = liquidity_pool::total_shares(&pool);
            
            // new_shares = (500_000 * total_before) / 1_000_000 = total_before / 2
            assert!(new_shares == total_before / 2, 0);
            assert!(total_after == total_before + new_shares, 1);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // REMOVE LIQUIDITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_remove_liquidity_proportional() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 2_000_000);
            let total = liquidity_pool::total_shares(&pool);
            
            // Remove half of user's shares
            let burn_amount = shares / 2;
            let (amount_a, amount_b) = liquidity_pool::remove_liquidity(&mut pool, burn_amount);
            
            // Should get proportional amounts
            // amount_a = (burn_amount * reserve_a) / total_shares
            assert!(amount_a > 0, 0);
            assert!(amount_b > 0, 1);
            assert!(amount_b == amount_a * 2, 2); // Maintains 1:2 ratio
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_remove_all_liquidity() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Remove all user shares (not MINIMUM_LIQUIDITY)
            let (amount_a, amount_b) = liquidity_pool::remove_liquidity(&mut pool, shares);
            
            assert!(amount_a > 0, 0);
            assert!(amount_b > 0, 1);
            
            // MINIMUM_LIQUIDITY (1000) remains locked
            assert!(liquidity_pool::total_shares(&pool) == 1000, 2);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = liquidity_pool::E_INSUFFICIENT_LIQUIDITY)]
    fun test_remove_more_than_total_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let total = liquidity_pool::total_shares(&pool);
            
            // Try to remove more than total
            liquidity_pool::remove_liquidity(&mut pool, total + 1);
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // SWAP TESTS - CONSTANT PRODUCT FORMULA (x * y = k)
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_swap_basic_a_to_b() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let k_before = liquidity_pool::get_k(&pool);
            
            let (amount_out, fee) = liquidity_pool::swap(&mut pool, 100_000, true);
            
            assert!(amount_out > 0, 0);
            assert!(fee > 0, 1);
            
            // K should be maintained or increase (due to fees)
            let k_after = liquidity_pool::get_k(&pool);
            assert!(k_after >= k_before, 2);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_swap_basic_b_to_a() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let (amount_out, fee) = liquidity_pool::swap(&mut pool, 100_000, false);
            
            assert!(amount_out > 0, 0);
            assert!(fee > 0, 1);
            
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            // After B->A swap: reserve_a decreases, reserve_b increases
            assert!(reserve_a < 1_000_000, 2);
            assert!(reserve_b > 1_000_000, 3);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_swap_fee_calculation() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx); // 0.3% fee
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let amount_in = 100_000;
            let (_, fee) = liquidity_pool::swap(&mut pool, amount_in, true);
            
            // Fee should be 0.3% of input
            // Expected: 100_000 * 30 / 10_000 = 300
            assert!(fee == 300, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_swap_output_formula() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let amount_in = 100_000;
            let (amount_out, _) = liquidity_pool::get_amount_out(&pool, amount_in, true);
            
            // Manual calculation:
            // fee = 100_000 * 30 / 10_000 = 300
            // amount_in_after_fee = 100_000 - 300 = 99_700
            // amount_out = (99_700 * 1_000_000) / (1_000_000 + 99_700)
            //            = 99_700_000_000 / 1_099_700 ≈ 90_661
            assert!(amount_out > 90_000 && amount_out < 91_000, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_swap_k_constant_maintained() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let k_initial = liquidity_pool::get_k(&pool);
            
            // Perform multiple swaps
            liquidity_pool::swap(&mut pool, 50_000, true);
            let k_after_1 = liquidity_pool::get_k(&pool);
            
            liquidity_pool::swap(&mut pool, 30_000, false);
            let k_after_2 = liquidity_pool::get_k(&pool);
            
            liquidity_pool::swap(&mut pool, 20_000, true);
            let k_after_3 = liquidity_pool::get_k(&pool);
            
            // K should never decrease (fees accumulate)
            assert!(k_after_1 >= k_initial, 0);
            assert!(k_after_2 >= k_after_1, 1);
            assert!(k_after_3 >= k_after_2, 2);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_swap_with_slippage_protection_passes() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let (expected_out, _) = liquidity_pool::get_amount_out(&pool, 100_000, true);
            let min_out = expected_out - 100; // Allow 100 unit slippage
            
            let (actual_out, _) = liquidity_pool::swap_with_slippage(&mut pool, 100_000, min_out, true);
            assert!(actual_out >= min_out, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = liquidity_pool::E_SLIPPAGE_EXCEEDED)]
    fun test_swap_with_slippage_protection_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Set min_out higher than possible output
            liquidity_pool::swap_with_slippage(&mut pool, 100_000, 100_000, true);
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = liquidity_pool::E_ZERO_AMOUNT_IN)]
    fun test_swap_zero_amount_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            liquidity_pool::swap(&mut pool, 0, true);
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PRICE IMPACT TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_price_impact_small_trade() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 10_000_000, 10_000_000);
            
            // Small trade (0.1% of reserves)
            let impact = liquidity_pool::get_price_impact(&pool, 10_000, true);
            
            // Impact should be very small (< 1%)
            assert!(impact < 100, 0); // < 100 bps = 1%
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_price_impact_large_trade() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Large trade (10% of reserves)
            let impact = liquidity_pool::get_price_impact(&pool, 100_000, true);
            
            // Impact should be significant (> 5%)
            assert!(impact > 500, 0); // > 500 bps = 5%
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // SPOT PRICE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_spot_price_equal_reserves() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let price_a_to_b = liquidity_pool::get_spot_price_a_to_b(&pool);
            let price_b_to_a = liquidity_pool::get_spot_price_b_to_a(&pool);
            
            // Both should be 1:1 (scaled by 1e8)
            assert!(price_a_to_b == 100_000_000, 0);
            assert!(price_b_to_a == 100_000_000, 1);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_spot_price_different_reserves() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 2_000_000);
            
            let price_a_to_b = liquidity_pool::get_spot_price_a_to_b(&pool);
            
            // 1 A = 2 B, so price scaled by 1e8 = 200_000_000
            assert!(price_a_to_b == 200_000_000, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FEE ACCRUAL TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_fee_indices_increase_after_swap() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let (idx_a_before, idx_b_before) = liquidity_pool::fee_indices(&pool);
            
            // Swap A to B - fees accrue in token A
            liquidity_pool::swap(&mut pool, 100_000, true);
            
            let (idx_a_after, _) = liquidity_pool::fee_indices(&pool);
            assert!(idx_a_after > idx_a_before, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_protocol_fees_accumulate() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let (proto_a_before, proto_b_before) = liquidity_pool::protocol_fees(&pool);
            assert!(proto_a_before == 0 && proto_b_before == 0, 0);
            
            // Swap A to B
            liquidity_pool::swap(&mut pool, 100_000, true);
            
            let (proto_a_after, _) = liquidity_pool::protocol_fees(&pool);
            // 10% of 0.3% fee = 0.03% = 30 bps of 100_000 = 30 * 0.1 = 3
            assert!(proto_a_after > 0, 1);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_withdraw_protocol_fees() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Generate fees
            liquidity_pool::swap(&mut pool, 100_000, true);
            liquidity_pool::swap(&mut pool, 50_000, false);
            
            let (proto_a, proto_b) = liquidity_pool::withdraw_protocol_fees(&mut pool);
            assert!(proto_a > 0 || proto_b > 0, 0);
            
            // After withdrawal, fees should be zero
            let (proto_a_after, proto_b_after) = liquidity_pool::protocol_fees(&pool);
            assert!(proto_a_after == 0 && proto_b_after == 0, 1);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_very_small_swap() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000_000, 1_000_000_000);
            
            // Very small swap
            let (amount_out, _) = liquidity_pool::swap(&mut pool, 1, true);
            assert!(amount_out == 0 || amount_out == 1, 0); // May round to 0 or 1
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_large_reserves() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            // Large but not overflow-causing reserves
            let large_amount = 1_000_000_000_000; // 1 trillion
            liquidity_pool::provide_initial_liquidity(&mut pool, large_amount, large_amount);
            
            let (amount_out, _) = liquidity_pool::swap(&mut pool, 1_000_000_000, true);
            assert!(amount_out > 0, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_cumulative_volume_tracking() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let (vol_a_before, vol_b_before) = liquidity_pool::cumulative_volume(&pool);
            assert!(vol_a_before == 0 && vol_b_before == 0, 0);
            
            liquidity_pool::swap(&mut pool, 100_000, true);
            let (vol_a_after, _) = liquidity_pool::cumulative_volume(&pool);
            assert!(vol_a_after == 100_000, 1);
            
            liquidity_pool::swap(&mut pool, 50_000, false);
            let (_, vol_b_after) = liquidity_pool::cumulative_volume(&pool);
            assert!(vol_b_after == 50_000, 2);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }
}
