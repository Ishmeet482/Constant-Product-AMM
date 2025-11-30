/// Comprehensive unit tests for slippage_protection module
/// Tests: Slippage enforcement, deadline validation, price impact checks
#[test_only]
module sui_amm_nft_lp::slippage_protection_tests {
    use sui::test_scenario::{Self as ts};
    use sui_amm_nft_lp::slippage_protection;

    const ADMIN: address = @0xAD;
    const BPS_DENOMINATOR: u64 = 10_000;

    // ═══════════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_default_slippage() {
        let default = slippage_protection::default_slippage();
        assert!(default == 50, 0); // 0.5%
    }

    #[test]
    fun test_max_slippage() {
        let max = slippage_protection::max_slippage();
        assert!(max == 5_000, 0); // 50%
    }

    #[test]
    fun test_default_price_impact_limit() {
        let limit = slippage_protection::default_price_impact_limit();
        assert!(limit == 500, 0); // 5%
    }

    #[test]
    fun test_validate_slippage_valid() {
        assert!(slippage_protection::validate_slippage(0), 0);
        assert!(slippage_protection::validate_slippage(50), 1);
        assert!(slippage_protection::validate_slippage(100), 2);
        assert!(slippage_protection::validate_slippage(5_000), 3);
    }

    #[test]
    fun test_validate_slippage_invalid() {
        assert!(!slippage_protection::validate_slippage(5_001), 0);
        assert!(!slippage_protection::validate_slippage(10_000), 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // MINIMUM OUTPUT ENFORCEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_enforce_min_output_passes() {
        // Expected >= min should pass
        slippage_protection::enforce_min_output(1000, 900);
        slippage_protection::enforce_min_output(1000, 1000);
        slippage_protection::enforce_min_output(1_000_000, 0);
    }

    #[test]
    #[expected_failure(abort_code = slippage_protection::E_SLIPPAGE_TOO_HIGH)]
    fun test_enforce_min_output_fails() {
        // Expected < min should fail
        slippage_protection::enforce_min_output(900, 1000);
    }

    #[test]
    fun test_enforce_min_output_edge_cases() {
        // Exact match
        slippage_protection::enforce_min_output(0, 0);
        slippage_protection::enforce_min_output(1, 1);
        slippage_protection::enforce_min_output(18_446_744_073_709_551_615, 18_446_744_073_709_551_615); // max u64
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // MAXIMUM INPUT ENFORCEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_enforce_max_input_passes() {
        // Actual <= max should pass
        slippage_protection::enforce_max_input(900, 1000);
        slippage_protection::enforce_max_input(1000, 1000);
        slippage_protection::enforce_max_input(0, 1_000_000);
    }

    #[test]
    #[expected_failure(abort_code = slippage_protection::E_SLIPPAGE_TOO_HIGH)]
    fun test_enforce_max_input_fails() {
        // Actual > max should fail
        slippage_protection::enforce_max_input(1001, 1000);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CALCULATE MINIMUM OUTPUT TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_calculate_min_output_zero_slippage() {
        let min = slippage_protection::calculate_min_output(1_000_000, 0);
        assert!(min == 1_000_000, 0); // No reduction
    }

    #[test]
    fun test_calculate_min_output_half_percent() {
        // 0.5% slippage = 50 bps
        let min = slippage_protection::calculate_min_output(1_000_000, 50);
        // min = 1_000_000 * (1 - 0.005) = 1_000_000 - 5000 = 995_000
        assert!(min == 995_000, 0);
    }

    #[test]
    fun test_calculate_min_output_one_percent() {
        // 1% slippage = 100 bps
        let min = slippage_protection::calculate_min_output(1_000_000, 100);
        // min = 1_000_000 - 10_000 = 990_000
        assert!(min == 990_000, 0);
    }

    #[test]
    fun test_calculate_min_output_ten_percent() {
        // 10% slippage = 1000 bps
        let min = slippage_protection::calculate_min_output(1_000_000, 1000);
        // min = 1_000_000 - 100_000 = 900_000
        assert!(min == 900_000, 0);
    }

    #[test]
    fun test_calculate_min_output_max_slippage() {
        // 50% slippage = 5000 bps (max allowed)
        let min = slippage_protection::calculate_min_output(1_000_000, 5000);
        // min = 1_000_000 - 500_000 = 500_000
        assert!(min == 500_000, 0);
    }

    #[test]
    #[expected_failure(abort_code = slippage_protection::E_INVALID_SLIPPAGE_TOLERANCE)]
    fun test_calculate_min_output_exceeds_max_fails() {
        // 51% slippage exceeds max
        slippage_protection::calculate_min_output(1_000_000, 5100);
    }

    #[test]
    fun test_calculate_min_output_small_amount() {
        // Small amount with slippage
        let min = slippage_protection::calculate_min_output(100, 100);
        // min = 100 - 1 = 99
        assert!(min == 99, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CALCULATE MAXIMUM INPUT TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_calculate_max_input_zero_slippage() {
        let max = slippage_protection::calculate_max_input(1_000_000, 0);
        assert!(max == 1_000_000, 0); // No increase
    }

    #[test]
    fun test_calculate_max_input_half_percent() {
        // 0.5% tolerance
        let max = slippage_protection::calculate_max_input(1_000_000, 50);
        // max = 1_000_000 + 5000 = 1_005_000
        assert!(max == 1_005_000, 0);
    }

    #[test]
    fun test_calculate_max_input_ten_percent() {
        let max = slippage_protection::calculate_max_input(1_000_000, 1000);
        // max = 1_000_000 + 100_000 = 1_100_000
        assert!(max == 1_100_000, 0);
    }

    #[test]
    #[expected_failure(abort_code = slippage_protection::E_INVALID_SLIPPAGE_TOLERANCE)]
    fun test_calculate_max_input_exceeds_max_fails() {
        slippage_protection::calculate_max_input(1_000_000, 5100);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // DEADLINE ENFORCEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_enforce_deadline_passes() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let current_epoch = sui::tx_context::epoch(ctx);
            
            // Deadline in the future
            slippage_protection::enforce_deadline(current_epoch + 10, ctx);
            
            // Deadline is current epoch (exact)
            slippage_protection::enforce_deadline(current_epoch, ctx);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = slippage_protection::E_DEADLINE_EXPIRED)]
    fun test_enforce_deadline_expired_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            // Deadline is 0, but epoch is likely > 0 in test
            // We need to force a past deadline
            // Since we can't control epoch in test, we'll test with timestamp instead
            slippage_protection::enforce_deadline_timestamp(100, 200);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_enforce_deadline_timestamp_passes() {
        // Current time before deadline
        slippage_protection::enforce_deadline_timestamp(1000, 500);
        
        // Current time exactly at deadline
        slippage_protection::enforce_deadline_timestamp(1000, 1000);
    }

    #[test]
    #[expected_failure(abort_code = slippage_protection::E_DEADLINE_EXPIRED)]
    fun test_enforce_deadline_timestamp_fails() {
        // Current time after deadline
        slippage_protection::enforce_deadline_timestamp(1000, 1001);
    }

    #[test]
    fun test_calculate_deadline_epoch() {
        let deadline = slippage_protection::calculate_deadline_epoch(10, 5);
        assert!(deadline == 15, 0);
        
        let deadline2 = slippage_protection::calculate_deadline_epoch(0, 100);
        assert!(deadline2 == 100, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PRICE IMPACT CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_calculate_price_impact_no_impact() {
        // Perfect execution at spot price
        // Spot price = 2M / 1M = 2
        // Exec price = 200_000 / 100_000 = 2
        let impact = slippage_protection::calculate_price_impact(
            1_000_000,   // reserve_in
            2_000_000,   // reserve_out
            100_000,     // amount_in
            200_000      // amount_out (perfect execution)
        );
        
        assert!(impact == 0, 0);
    }

    #[test]
    fun test_calculate_price_impact_with_slippage() {
        // Spot price = 1M / 1M = 1
        // Exec price = 90_000 / 100_000 = 0.9
        // Impact = |1 - 0.9| / 1 * 10000 = 1000 bps = 10%
        let impact = slippage_protection::calculate_price_impact(
            1_000_000,   // reserve_in
            1_000_000,   // reserve_out
            100_000,     // amount_in
            90_000       // amount_out (worse than spot)
        );
        
        // Impact should be ~1000 bps (10%)
        assert!(impact == 1000, 0);
    }

    #[test]
    fun test_calculate_price_impact_small() {
        // Small impact ~1%
        let impact = slippage_protection::calculate_price_impact(
            1_000_000,
            1_000_000,
            100_000,
            99_000      // 1% worse
        );
        
        // Impact should be ~100 bps (1%)
        assert!(impact == 100, 0);
    }

    #[test]
    fun test_calculate_price_impact_zero_inputs() {
        // Zero reserve_in
        let impact1 = slippage_protection::calculate_price_impact(0, 1_000_000, 100, 100);
        assert!(impact1 == 0, 0);
        
        // Zero amount_in
        let impact2 = slippage_protection::calculate_price_impact(1_000_000, 1_000_000, 0, 0);
        assert!(impact2 == 0, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PRICE IMPACT CHECK TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_check_price_impact_passes() {
        // Impact of 1000 bps (10%), max allowed is 1500 bps
        slippage_protection::check_price_impact(
            1_000_000, 1_000_000,
            100_000, 90_000,
            1500  // 15% max impact allowed
        );
    }

    #[test]
    #[expected_failure(abort_code = slippage_protection::E_PRICE_IMPACT_TOO_HIGH)]
    fun test_check_price_impact_fails() {
        // Impact of 1000 bps (10%), but max is 500 bps (5%)
        slippage_protection::check_price_impact(
            1_000_000, 1_000_000,
            100_000, 90_000,
            500  // Only 5% allowed
        );
    }

    #[test]
    fun test_check_price_impact_default_passes() {
        // Default is 5% (500 bps)
        // Impact of ~2%
        slippage_protection::check_price_impact_default(
            1_000_000, 1_000_000,
            100_000, 98_000
        );
    }

    #[test]
    #[expected_failure(abort_code = slippage_protection::E_PRICE_IMPACT_TOO_HIGH)]
    fun test_check_price_impact_default_fails() {
        // Impact of 10% exceeds default 5%
        slippage_protection::check_price_impact_default(
            1_000_000, 1_000_000,
            100_000, 90_000
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // COMBINED VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_validate_swap_params_passes() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let current_epoch = sui::tx_context::epoch(ctx);
            
            slippage_protection::validate_swap_params(
                100_000,         // expected_out
                95_000,          // min_out
                current_epoch + 10,  // deadline
                ctx
            );
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = slippage_protection::E_SLIPPAGE_TOO_HIGH)]
    fun test_validate_swap_params_slippage_fails() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let current_epoch = sui::tx_context::epoch(ctx);
            
            slippage_protection::validate_swap_params(
                90_000,          // expected_out (less than min)
                95_000,          // min_out
                current_epoch + 10,
                ctx
            );
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_slippage_calculation_precision() {
        // Test precision with various amounts
        
        // Large amount, small slippage
        let min1 = slippage_protection::calculate_min_output(1_000_000_000, 1); // 0.01%
        assert!(min1 == 999_900_000, 0);
        
        // Small amount, large slippage
        let min2 = slippage_protection::calculate_min_output(100, 2500); // 25%
        assert!(min2 == 75, 1);
    }

    #[test]
    fun test_price_impact_asymmetric_reserves() {
        // Unequal reserves
        let impact = slippage_protection::calculate_price_impact(
            500_000,     // Small reserve_in
            2_000_000,   // Large reserve_out
            100_000,     // amount_in
            350_000      // amount_out (should be 400K at spot)
        );
        
        // Spot price = 4, exec price = 3.5
        // Impact = |4 - 3.5| / 4 * 10000 = 1250 bps = 12.5%
        assert!(impact == 1250, 0);
    }
}
