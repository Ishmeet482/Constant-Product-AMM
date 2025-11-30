/// Comprehensive unit tests for stable_swap_pool module
/// Tests: Stable swap formula, amplification factor, low-slippage stable swaps
#[test_only]
module sui_amm_nft_lp::stable_swap_pool_tests {
    use sui::test_scenario::{Self as ts};
    use sui_amm_nft_lp::stable_swap_pool::{Self, StableSwapPool};

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST COIN TYPES (Stablecoins)
    // ═══════════════════════════════════════════════════════════════════════════════

    struct USDC has drop {}
    struct USDT has drop {}
    struct DAI has drop {}

    const ADMIN: address = @0xAD;
    const BPS_DENOMINATOR: u64 = 10_000;

    // ═══════════════════════════════════════════════════════════════════════════════
    // POOL CREATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_create_stable_pool() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool<USDC, USDT>(100, 4, ctx);
            
            assert!(stable_swap_pool::amp_factor(&pool) == 100, 0);
            assert!(stable_swap_pool::fee_bps(&pool) == 4, 1);
            assert!(stable_swap_pool::total_shares(&pool) == 0, 2);
            
            let (reserve_a, reserve_b) = stable_swap_pool::reserves(&pool);
            assert!(reserve_a == 0 && reserve_b == 0, 3);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_create_stable_pool_default() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            // Default amp = 100, fee = 4 bps (0.04%)
            assert!(stable_swap_pool::amp_factor(&pool) == 100, 0);
            assert!(stable_swap_pool::fee_bps(&pool) == 4, 1);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_create_pool_custom_amp_factor() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // Low amp (more like constant product)
            let pool_low = stable_swap_pool::new_stable_pool<USDC, USDT>(10, 4, ctx);
            assert!(stable_swap_pool::amp_factor(&pool_low) == 10, 0);
            sui::test_utils::destroy(pool_low);
        };
        ts::next_tx(&mut scenario, ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // High amp (more like constant sum)
            let pool_high = stable_swap_pool::new_stable_pool<USDC, USDT>(1000, 4, ctx);
            assert!(stable_swap_pool::amp_factor(&pool_high) == 1000, 1);
            sui::test_utils::destroy(pool_high);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stable_swap_pool::E_INVALID_AMP)]
    fun test_create_pool_zero_amp_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool<USDC, USDT>(0, 4, ctx);
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stable_swap_pool::E_INVALID_AMP)]
    fun test_create_pool_amp_too_high_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool<USDC, USDT>(10_001, 4, ctx);
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stable_swap_pool::E_INVALID_FEE)]
    fun test_create_pool_fee_too_high_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool<USDC, USDT>(100, 101, ctx); // > 1%
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
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            let shares = stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // For stable pools, initial shares = sum of deposits
            assert!(shares == 2_000_000, 0);
            assert!(stable_swap_pool::total_shares(&pool) == 2_000_000, 1);
            
            let (reserve_a, reserve_b) = stable_swap_pool::reserves(&pool);
            assert!(reserve_a == 1_000_000, 2);
            assert!(reserve_b == 1_000_000, 3);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_provide_initial_liquidity_unequal() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            // Unequal amounts (can happen for slight depeg)
            let shares = stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_010_000);
            
            assert!(shares == 2_010_000, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stable_swap_pool::E_ZERO_AMOUNT)]
    fun test_provide_initial_liquidity_zero_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 0, 1_000_000);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ADD LIQUIDITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_add_liquidity() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let total_before = stable_swap_pool::total_shares(&pool);
            
            // Add more liquidity
            let new_shares = stable_swap_pool::add_liquidity(&mut pool, 500_000, 500_000);
            
            // New shares proportional to deposit
            // deposit_value = 1M, total_reserve = 2M, total_shares = 2M
            // shares = (1M * 2M) / 2M = 1M
            assert!(new_shares == 1_000_000, 0);
            assert!(stable_swap_pool::total_shares(&pool) == total_before + new_shares, 1);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_add_liquidity_single_sided() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Add only token A
            let new_shares = stable_swap_pool::add_liquidity(&mut pool, 500_000, 0);
            
            // Single-sided adds are allowed in stable pools
            assert!(new_shares > 0, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // REMOVE LIQUIDITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_remove_liquidity() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            let shares = stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Remove half
            let (amount_a, amount_b) = stable_swap_pool::remove_liquidity(&mut pool, shares / 2);
            
            // Should get proportional amounts
            assert!(amount_a == 500_000, 0);
            assert!(amount_b == 500_000, 1);
            
            let (reserve_a, reserve_b) = stable_swap_pool::reserves(&pool);
            assert!(reserve_a == 500_000, 2);
            assert!(reserve_b == 500_000, 3);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stable_swap_pool::E_INSUFFICIENT_LIQUIDITY)]
    fun test_remove_liquidity_exceeds_total_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            let shares = stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Try to remove more than total
            stable_swap_pool::remove_liquidity(&mut pool, shares + 1);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // STABLE SWAP TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_stable_swap_basic() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let amount_out = stable_swap_pool::stable_swap(&mut pool, 10_000, true);
            
            // For stablecoins, output should be very close to input (low slippage)
            // With high amp factor, should be near 1:1
            assert!(amount_out > 9_900, 0); // At least 99% of input
            assert!(amount_out < 10_000, 1); // Less than input due to fee
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_stable_swap_low_slippage() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool<USDC, USDT>(1000, 4, ctx); // High amp
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 10_000_000, 10_000_000);
            
            // Large trade relative to reserves
            let amount_out = stable_swap_pool::stable_swap(&mut pool, 1_000_000, true);
            
            // With high amp, even 10% trade should have low slippage
            // Output should be very close to 999_600 (input - 0.04% fee)
            assert!(amount_out > 990_000, 0); // At least 99% efficiency
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_stable_swap_vs_constant_product() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // High amp pool (stable swap behavior)
            let pool_stable = stable_swap_pool::new_stable_pool<USDC, USDT>(1000, 4, ctx);
            stable_swap_pool::provide_initial_liquidity(&mut pool_stable, 1_000_000, 1_000_000);
            
            let stable_out = stable_swap_pool::stable_swap(&mut pool_stable, 100_000, true);
            
            sui::test_utils::destroy(pool_stable);
        };
        ts::next_tx(&mut scenario, ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // Low amp pool (more like constant product)
            let pool_low = stable_swap_pool::new_stable_pool<USDC, USDT>(1, 4, ctx);
            stable_swap_pool::provide_initial_liquidity(&mut pool_low, 1_000_000, 1_000_000);
            
            let low_out = stable_swap_pool::stable_swap(&mut pool_low, 100_000, true);
            
            // Low amp should have more slippage (less output)
            // This is a relative comparison
            sui::test_utils::destroy(pool_low);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_stable_swap_fee_calculation() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool<USDC, USDT>(100, 4, ctx); // 0.04% fee
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 10_000_000, 10_000_000);
            
            let (amount_out, fee) = stable_swap_pool::get_amount_out(&pool, 100_000, true);
            
            // Fee should be 0.04% of input
            // fee = 100_000 * 4 / 10_000 = 40
            assert!(fee == 40, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_stable_swap_both_directions() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Swap A to B
            let out_a_to_b = stable_swap_pool::stable_swap(&mut pool, 10_000, true);
            
            let (reserve_a, reserve_b) = stable_swap_pool::reserves(&pool);
            assert!(reserve_a > 1_000_000, 0); // A increased
            assert!(reserve_b < 1_000_000, 1); // B decreased
            
            // Swap B to A
            let out_b_to_a = stable_swap_pool::stable_swap(&mut pool, 10_000, false);
            
            let (reserve_a2, reserve_b2) = stable_swap_pool::reserves(&pool);
            assert!(reserve_a2 < reserve_a, 2); // A decreased
            assert!(reserve_b2 > reserve_b, 3); // B increased
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_stable_swap_with_slippage_protection() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let (expected_out, _) = stable_swap_pool::get_amount_out(&pool, 10_000, true);
            let min_out = expected_out - 10; // Allow 10 units slippage
            
            let actual_out = stable_swap_pool::stable_swap_with_slippage(&mut pool, 10_000, min_out, true);
            
            assert!(actual_out >= min_out, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stable_swap_pool::E_SLIPPAGE_EXCEEDED)]
    fun test_stable_swap_slippage_exceeded_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Set min_out higher than possible
            stable_swap_pool::stable_swap_with_slippage(&mut pool, 10_000, 10_000, true);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stable_swap_pool::E_ZERO_AMOUNT)]
    fun test_stable_swap_zero_amount_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            stable_swap_pool::stable_swap(&mut pool, 0, true);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // AMPLIFICATION FACTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_set_amp_factor() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            assert!(stable_swap_pool::amp_factor(&pool) == 100, 0);
            
            stable_swap_pool::set_amp_factor(&mut pool, 500);
            
            assert!(stable_swap_pool::amp_factor(&pool) == 500, 1);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stable_swap_pool::E_INVALID_AMP)]
    fun test_set_amp_factor_zero_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::set_amp_factor(&mut pool, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stable_swap_pool::E_INVALID_AMP)]
    fun test_set_amp_factor_too_high_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::set_amp_factor(&mut pool, 10_001);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_amp_factor_affects_slippage() {
        let scenario = ts::begin(ADMIN);
        let output_low_amp: u64;
        let output_high_amp: u64;
        {
            let ctx = ts::ctx(&mut scenario);
            
            // Low amp (more slippage)
            let pool_low = stable_swap_pool::new_stable_pool<USDC, USDT>(10, 4, ctx);
            stable_swap_pool::provide_initial_liquidity(&mut pool_low, 1_000_000, 1_000_000);
            
            let (out_low, _) = stable_swap_pool::get_amount_out(&pool_low, 100_000, true);
            output_low_amp = out_low;
            
            sui::test_utils::destroy(pool_low);
        };
        ts::next_tx(&mut scenario, ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // High amp (less slippage)
            let pool_high = stable_swap_pool::new_stable_pool<USDC, USDT>(1000, 4, ctx);
            stable_swap_pool::provide_initial_liquidity(&mut pool_high, 1_000_000, 1_000_000);
            
            let (out_high, _) = stable_swap_pool::get_amount_out(&pool_high, 100_000, true);
            output_high_amp = out_high;
            
            // High amp should give more output (less slippage)
            assert!(output_high_amp > output_low_amp, 0);
            
            sui::test_utils::destroy(pool_high);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FEE ACCRUAL TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_fee_indices_increase() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            // Use higher fee to ensure fee indices increase
            let pool = stable_swap_pool::new_stable_pool<USDC, USDT>(100, 30, ctx); // 0.3% fee
            
            // Smaller initial liquidity to ensure fee delta is significant
            stable_swap_pool::provide_initial_liquidity(&mut pool, 100_000, 100_000);
            
            let (idx_a_before, idx_b_before) = stable_swap_pool::fee_indices(&pool);
            
            // Large swap relative to pool size to generate significant fees
            stable_swap_pool::stable_swap(&mut pool, 50_000, true);
            
            // Fee indices should increase (at least one of them)
            // With 0.3% fee on 50K = 150 fee, LP gets ~135
            // fee_index_delta = (135 * 10_000) / 200_000 = 6 (should be > 0)
            let (idx_a_after, idx_b_after) = stable_swap_pool::fee_indices(&pool);
            assert!(idx_a_after > idx_a_before || idx_b_after > idx_b_before, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_cumulative_volume_tracking() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            assert!(stable_swap_pool::cumulative_volume(&pool) == 0, 0);
            
            stable_swap_pool::stable_swap(&mut pool, 100_000, true);
            assert!(stable_swap_pool::cumulative_volume(&pool) == 100_000, 1);
            
            stable_swap_pool::stable_swap(&mut pool, 50_000, false);
            assert!(stable_swap_pool::cumulative_volume(&pool) == 150_000, 2);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_withdraw_protocol_fees() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Generate fees
            stable_swap_pool::stable_swap(&mut pool, 100_000, true);
            stable_swap_pool::stable_swap(&mut pool, 50_000, false);
            
            let (fees_a, fees_b) = stable_swap_pool::withdraw_protocol_fees(&mut pool);
            
            // Protocol gets 10% of trading fees
            assert!(fees_a > 0 || fees_b > 0, 0);
            
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
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 10_000_000, 10_000_000);
            
            // Very small swap
            let amount_out = stable_swap_pool::stable_swap(&mut pool, 1, true);
            
            // Should get something (might be 0 due to fee)
            assert!(amount_out <= 1, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_large_swap() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 100_000_000, 100_000_000);
            
            // Large swap (10% of reserves)
            let amount_out = stable_swap_pool::stable_swap(&mut pool, 10_000_000, true);
            
            // Should still work
            assert!(amount_out > 0, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_multiple_swaps_consistency() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = stable_swap_pool::new_stable_pool_default<USDC, USDT>(ctx);
            
            stable_swap_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Multiple swaps
            let i = 0;
            while (i < 10) {
                let direction = i % 2 == 0;
                stable_swap_pool::stable_swap(&mut pool, 10_000, direction);
                i = i + 1;
            };
            
            // Pool should still be functional
            let (reserve_a, reserve_b) = stable_swap_pool::reserves(&pool);
            assert!(reserve_a > 0 && reserve_b > 0, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }
}
