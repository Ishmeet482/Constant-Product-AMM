#[allow(unused_const)]
module sui_amm_nft_lp::slippage_protection {
    use sui::tx_context::TxContext;

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════

    const BPS_DENOMINATOR: u64 = 10_000;

    /// Default slippage tolerance (0.5%)
    const DEFAULT_SLIPPAGE_BPS: u64 = 50;

    /// Maximum allowed slippage tolerance (50%)
    const MAX_SLIPPAGE_BPS: u64 = 5_000;

    /// Default price impact limit (5%)
    const DEFAULT_PRICE_IMPACT_BPS: u64 = 500;

    // ═══════════════════════════════════════════════════════════════════════════════
    // ERROR CODES
    // ═══════════════════════════════════════════════════════════════════════════════

    const E_SLIPPAGE_TOO_HIGH: u64 = 1;
    const E_DEADLINE_EXPIRED: u64 = 2;
    const E_PRICE_IMPACT_TOO_HIGH: u64 = 3;
    const E_INVALID_SLIPPAGE_TOLERANCE: u64 = 4;
    const E_ZERO_AMOUNT: u64 = 5;

    // ═══════════════════════════════════════════════════════════════════════════════
    // SLIPPAGE ENFORCEMENT
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Enforce minimum output amount for slippage protection.
    /// Aborts if expected_out < min_out.
    public fun enforce_min_output(expected_out: u64, min_out: u64) {
        assert!(expected_out >= min_out, E_SLIPPAGE_TOO_HIGH);
    }

    /// Enforce maximum input amount for slippage protection.
    /// Aborts if actual_in > max_in.
    public fun enforce_max_input(actual_in: u64, max_in: u64) {
        assert!(actual_in <= max_in, E_SLIPPAGE_TOO_HIGH);
    }

    /// Calculate minimum output given expected output and slippage tolerance.
    /// min_out = expected_out * (1 - slippage_bps / 10000)
    public fun calculate_min_output(expected_out: u64, slippage_bps: u64): u64 {
        assert!(slippage_bps <= MAX_SLIPPAGE_BPS, E_INVALID_SLIPPAGE_TOLERANCE);
        let reduction = (expected_out * slippage_bps) / BPS_DENOMINATOR;
        expected_out - reduction
    }

    /// Calculate maximum input given expected input and slippage tolerance.
    /// max_in = expected_in * (1 + slippage_bps / 10000)
    public fun calculate_max_input(expected_in: u64, slippage_bps: u64): u64 {
        assert!(slippage_bps <= MAX_SLIPPAGE_BPS, E_INVALID_SLIPPAGE_TOLERANCE);
        let addition = (expected_in * slippage_bps) / BPS_DENOMINATOR;
        expected_in + addition
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // DEADLINE ENFORCEMENT
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Enforce transaction deadline (epoch-based).
    /// Aborts if current epoch > deadline_epoch.
    public fun enforce_deadline(deadline_epoch: u64, ctx: &TxContext) {
        let current_epoch = sui::tx_context::epoch(ctx);
        assert!(current_epoch <= deadline_epoch, E_DEADLINE_EXPIRED);
    }

    /// Enforce transaction deadline with explicit current time.
    /// For use with Sui Clock object in production.
    public fun enforce_deadline_timestamp(deadline_ms: u64, current_time_ms: u64) {
        assert!(current_time_ms <= deadline_ms, E_DEADLINE_EXPIRED);
    }

    /// Calculate deadline epoch from current epoch plus buffer.
    public fun calculate_deadline_epoch(current_epoch: u64, buffer_epochs: u64): u64 {
        current_epoch + buffer_epochs
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // PRICE IMPACT CHECKS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Calculate price impact in basis points.
    /// Returns the percentage difference between spot price and execution price.
    /// Formula: impact = |1 - (amount_out/amount_in) / (reserve_out/reserve_in)| * 10000
    public fun calculate_price_impact(
        reserve_in: u64,
        reserve_out: u64,
        amount_in: u64,
        amount_out: u64,
    ): u64 {
        if (reserve_in == 0 || amount_in == 0) return 0;

        // Spot price = reserve_out / reserve_in (scaled)
        // Exec price = amount_out / amount_in (scaled)
        // Using cross multiplication to avoid division precision loss:
        // spot_price = reserve_out * amount_in
        // exec_price = amount_out * reserve_in
        let spot_cross = (reserve_out as u128) * (amount_in as u128);
        let exec_cross = (amount_out as u128) * (reserve_in as u128);

        if (spot_cross == 0) return 0;

        // Impact = |spot_cross - exec_cross| / spot_cross * 10000
        let diff = if (spot_cross > exec_cross) {
            spot_cross - exec_cross
        } else {
            exec_cross - spot_cross
        };

        ((diff * (BPS_DENOMINATOR as u128) / spot_cross) as u64)
    }

    /// Check price impact and abort if too high.
    public fun check_price_impact(
        reserve_in: u64,
        reserve_out: u64,
        amount_in: u64,
        amount_out: u64,
        max_impact_bps: u64,
    ) {
        let impact = calculate_price_impact(reserve_in, reserve_out, amount_in, amount_out);
        assert!(impact <= max_impact_bps, E_PRICE_IMPACT_TOO_HIGH);
    }

    /// Check price impact using default maximum (5%)
    public fun check_price_impact_default(
        reserve_in: u64,
        reserve_out: u64,
        amount_in: u64,
        amount_out: u64,
    ) {
        check_price_impact(reserve_in, reserve_out, amount_in, amount_out, DEFAULT_PRICE_IMPACT_BPS);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Get default slippage tolerance
    public fun default_slippage(): u64 {
        DEFAULT_SLIPPAGE_BPS
    }

    /// Get maximum allowed slippage
    public fun max_slippage(): u64 {
        MAX_SLIPPAGE_BPS
    }

    /// Get default price impact limit
    public fun default_price_impact_limit(): u64 {
        DEFAULT_PRICE_IMPACT_BPS
    }

    /// Validate slippage tolerance is within bounds
    public fun validate_slippage(slippage_bps: u64): bool {
        slippage_bps <= MAX_SLIPPAGE_BPS
    }

    /// Combined slippage and deadline check for swap operations
    public fun validate_swap_params(
        expected_out: u64,
        min_out: u64,
        deadline_epoch: u64,
        ctx: &TxContext,
    ) {
        enforce_min_output(expected_out, min_out);
        enforce_deadline(deadline_epoch, ctx);
    }
}
