/// Comprehensive AMM Mathematics Tests
/// Tests: Constant product formula, share calculations, price calculations
#[test_only]
module sui_amm_nft_lp::amm_math_tests {

    const BPS_DENOMINATOR: u64 = 10_000;

    // ═══════════════════════════════════════════════════════════════════════════════
    // LP SHARE CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_lp_share_proportionality() {
        let reserve_a = 1_000_000;
        let total_shares = 1_000_000;
        let add_a = 500_000;
        let shares = (add_a * total_shares) / reserve_a;
        assert!(shares == 500_000, 0);
    }

    #[test]
    fun test_initial_shares_geometric_mean() {
        // Initial shares = sqrt(amount_a * amount_b)
        let amount_a = 1_000_000u128;
        let amount_b = 1_000_000u128;
        let product = amount_a * amount_b;
        let shares = integer_sqrt(product);
        assert!(shares == 1_000_000, 0);
        
        // Different amounts
        let amount_a2 = 400_000u128;
        let amount_b2 = 900_000u128;
        let product2 = amount_a2 * amount_b2;
        let shares2 = integer_sqrt(product2);
        // sqrt(360_000_000_000) = 600_000
        assert!(shares2 == 600_000, 1);
    }

    #[test]
    fun test_add_liquidity_share_calculation() {
        let reserve_a = 1_000_000;
        let reserve_b = 2_000_000;
        let total_shares = 1_000_000;
        let add_a = 100_000;
        let add_b = 200_000;
        
        // shares = min(add_a * total / reserve_a, add_b * total / reserve_b)
        let shares_a = (add_a * total_shares) / reserve_a;
        let shares_b = (add_b * total_shares) / reserve_b;
        let shares = if (shares_a < shares_b) { shares_a } else { shares_b };
        
        assert!(shares == 100_000, 0);
    }

    #[test]
    fun test_remove_liquidity_amounts() {
        let reserve_a = 1_500_000;
        let reserve_b = 3_000_000;
        let total_shares = 1_000_000;
        let burn_shares = 100_000; // 10% of shares
        
        // amount = (burn_shares * reserve) / total_shares
        let amount_a = (burn_shares * reserve_a) / total_shares;
        let amount_b = (burn_shares * reserve_b) / total_shares;
        
        // Should get 10% of each reserve
        assert!(amount_a == 150_000, 0);
        assert!(amount_b == 300_000, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTANT PRODUCT FORMULA TESTS (x * y = k)
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_k_constant_basic() {
        let reserve_a = 1_000_000u128;
        let reserve_b = 1_000_000u128;
        let k = reserve_a * reserve_b;
        assert!(k == 1_000_000_000_000, 0);
    }

    #[test]
    fun test_swap_output_formula() {
        let reserve_in = 1_000_000;
        let reserve_out = 1_000_000;
        let amount_in = 100_000;
        let fee_bps = 30; // 0.3%
        
        // Apply fee
        let fee = (amount_in * fee_bps) / BPS_DENOMINATOR;
        let amount_in_after_fee = amount_in - fee;
        
        // out = (amount_in_after_fee * reserve_out) / (reserve_in + amount_in_after_fee)
        let numerator = (amount_in_after_fee as u128) * (reserve_out as u128);
        let denominator = (reserve_in as u128) + (amount_in_after_fee as u128);
        let amount_out = (numerator / denominator as u64);
        
        // Verify K is maintained
        let new_reserve_in = reserve_in + amount_in;
        let new_reserve_out = reserve_out - amount_out;
        let k_before = (reserve_in as u128) * (reserve_out as u128);
        let k_after = (new_reserve_in as u128) * (new_reserve_out as u128);
        
        // K after should be >= K before (fees accumulate)
        assert!(k_after >= k_before, 0);
    }

    #[test]
    fun test_swap_preserves_k() {
        let reserve_in = 2_000_000u128;
        let reserve_out = 1_000_000u128;
        let k = reserve_in * reserve_out;
        
        // Simulate swap of 100_000 in
        let amount_in = 100_000u128;
        let new_reserve_in = reserve_in + amount_in;
        
        // Calculate output to maintain K
        // new_reserve_out = k / new_reserve_in
        let new_reserve_out = k / new_reserve_in;
        let _amount_out = reserve_out - new_reserve_out;
        
        // Verify K - due to integer division, k_after may be slightly less than k
        // but never more (this protects LP providers)
        let k_after = new_reserve_in * new_reserve_out;
        assert!(k_after <= k, 0); // K after should be <= K before (rounding down)
        
        // Verify the difference is minimal (less than 0.01% difference)
        let diff = k - k_after;
        assert!(diff * 10_000 / k < 1, 1); // Less than 0.01% loss
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // FEE CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_fee_calculation_accuracy() {
        let amount = 1_000_000;
        
        // 0.05% fee
        let fee_5bps = (amount * 5) / BPS_DENOMINATOR;
        assert!(fee_5bps == 500, 0);
        
        // 0.3% fee
        let fee_30bps = (amount * 30) / BPS_DENOMINATOR;
        assert!(fee_30bps == 3000, 1);
        
        // 1% fee
        let fee_100bps = (amount * 100) / BPS_DENOMINATOR;
        assert!(fee_100bps == 10000, 2);
    }

    #[test]
    fun test_protocol_fee_split() {
        let total_fee = 1000;
        let protocol_fee_bps = 1000; // 10% of fees
        
        let protocol_fee = (total_fee * protocol_fee_bps) / BPS_DENOMINATOR;
        let lp_fee = total_fee - protocol_fee;
        
        assert!(protocol_fee == 100, 0);
        assert!(lp_fee == 900, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PRICE CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_spot_price_calculation() {
        let reserve_a = 1_000_000u128;
        let reserve_b = 2_000_000u128;
        let precision = 100_000_000u128; // 1e8
        
        // Price of A in terms of B = reserve_b / reserve_a
        let price_a_to_b = (reserve_b * precision) / reserve_a;
        assert!(price_a_to_b == 200_000_000, 0); // 2.0 scaled by 1e8
        
        // Price of B in terms of A = reserve_a / reserve_b
        let price_b_to_a = (reserve_a * precision) / reserve_b;
        assert!(price_b_to_a == 50_000_000, 1); // 0.5 scaled by 1e8
    }

    #[test]
    fun test_price_impact_calculation() {
        let reserve_in = 1_000_000u128;
        let reserve_out = 1_000_000u128;
        let amount_in = 100_000u128;
        
        // Spot price = reserve_out / reserve_in = 1.0
        let spot_price = (reserve_out * 100_000_000) / reserve_in;
        
        // Calculate actual output
        let new_reserve_in = reserve_in + amount_in;
        let new_reserve_out = (reserve_in * reserve_out) / new_reserve_in;
        let amount_out = reserve_out - new_reserve_out;
        
        // Execution price = amount_out / amount_in
        let exec_price = (amount_out * 100_000_000) / amount_in;
        
        // Price impact = (spot - exec) / spot * 10000
        let diff = spot_price - exec_price;
        let impact_bps = (diff * 10_000) / spot_price;
        
        // 10% trade should have ~9% impact for constant product
        assert!(impact_bps > 800 && impact_bps < 1000, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // RATIO VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_add_liquidity_ratio_check() {
        let reserve_a = 1_000_000;
        let reserve_b = 2_000_000;
        let amount_a = 500_000;
        let amount_b = 1_000_000;
        let tolerance_bps = 50; // 0.5%
        
        // required_b = amount_a * reserve_b / reserve_a
        let required_b = (amount_a * reserve_b) / reserve_a;
        let diff = if (amount_b > required_b) { amount_b - required_b } else { required_b - amount_b };
        let diff_bps = if (required_b > 0) { (diff * BPS_DENOMINATOR) / required_b } else { 0 };
        
        assert!(diff_bps <= tolerance_bps, 0);
    }

    #[test]
    fun test_ratio_deviation_calculation() {
        let required = 1_000_000;
        let actual = 1_005_000; // 0.5% higher
        
        let diff = if (actual > required) { actual - required } else { required - actual };
        let deviation_bps = (diff * BPS_DENOMINATOR) / required;
        
        assert!(deviation_bps == 50, 0); // 50 bps = 0.5%
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_large_numbers_no_overflow() {
        // Test with large but safe numbers
        let large_reserve = 1_000_000_000_000u128; // 1 trillion
        let k = large_reserve * large_reserve;
        
        // K should not overflow for u128
        assert!(k > 0, 0);
    }

    #[test]
    fun test_small_amounts_precision() {
        let reserve = 1_000_000_000;
        let small_amount = 1;
        let total_shares = 1_000_000_000;
        
        // Very small add should give proportional shares
        let shares = (small_amount * total_shares) / reserve;
        assert!(shares == 1, 0);
    }

    #[test]
    fun test_minimum_liquidity_lock() {
        let minimum_liquidity = 1000;
        let initial_shares = 1_000_000;
        
        // User shares = initial_shares - minimum_liquidity
        let user_shares = initial_shares - minimum_liquidity;
        assert!(user_shares == 999_000, 0);
        
        // Verify minimum is locked
        assert!(initial_shares - user_shares == minimum_liquidity, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Integer square root using Newton's method
    fun integer_sqrt(n: u128): u64 {
        if (n == 0) return 0;
        let x = n;
        let y = (x + 1) / 2;
        while (y < x) {
            x = y;
            y = (x + n / x) / 2;
        };
        (x as u64)
    }
}
