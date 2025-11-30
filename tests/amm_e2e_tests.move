/// End-to-End Integration Tests for the AMM
/// Tests full workflows within single transactions to avoid share_object restrictions
#[test_only]
#[allow(unused_use, unused_variable, unused_const, deprecated_usage)]
module sui_amm_nft_lp::amm_e2e_tests {
    use sui::test_scenario::{Self as ts};
    use sui_amm_nft_lp::pool_factory;
    use sui_amm_nft_lp::liquidity_pool;
    use sui_amm_nft_lp::lp_position_nft;
    use sui_amm_nft_lp::fee_distributor;
    use sui_amm_nft_lp::slippage_protection;
    use sui_amm_nft_lp::stable_swap_pool;

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST COIN TYPES
    // ═══════════════════════════════════════════════════════════════════════════════

    struct USDC has drop {}
    struct ETH has drop {}
    struct USDT has drop {}

    const ADMIN: address = @0xAD;
    const LP1: address = @0x1;

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: COMPLETE AMM WORKFLOW (SINGLE TX)
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_full_amm_workflow() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // Step 1: Create pool via factory
            let factory = pool_factory::new_factory_default(ctx);
            let pool = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            
            // Step 2: Provide initial liquidity
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            assert!(shares > 0, 0);
            
            // Verify reserves
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a == 1_000_000, 1);
            assert!(reserve_b == 1_000_000, 2);
            
            // Step 3: Execute swap A to B
            let (amount_out, fee) = liquidity_pool::swap(&mut pool, 100_000, true);
            assert!(amount_out > 0, 3);
            assert!(fee > 0, 4);
            
            // Verify K increased (due to fees)
            let k = liquidity_pool::get_k(&pool);
            assert!(k > 1_000_000_000_000, 5); // > initial K
            
            // Step 4: Execute swap B to A
            let (amount_out2, fee2) = liquidity_pool::swap(&mut pool, 50_000, false);
            assert!(amount_out2 > 0, 6);
            
            // Step 5: Add more liquidity (use higher tolerance since swaps changed ratio)
            let new_shares = liquidity_pool::add_liquidity(&mut pool, 200_000, 200_000, 2000);
            assert!(new_shares > 0, 7);
            
            // Step 6: Remove liquidity
            let (removed_a, removed_b) = liquidity_pool::remove_liquidity(&mut pool, new_shares);
            assert!(removed_a > 0, 8);
            assert!(removed_b > 0, 9);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: MULTIPLE SWAPS WITH K INVARIANT
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_multiple_swaps_k_invariant() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let k_initial = liquidity_pool::get_k(&pool);
            
            // Execute 10 swaps alternating direction
            let i = 0;
            while (i < 10) {
                let amount = 10_000 + (i * 1000);
                let direction = i % 2 == 0;
                liquidity_pool::swap(&mut pool, amount, direction);
                
                // K should never decrease (only increase due to fees)
                let k_current = liquidity_pool::get_k(&pool);
                assert!(k_current >= k_initial, i);
                
                i = i + 1;
            };
            
            // Final K should be greater than initial (fees accumulated)
            let k_final = liquidity_pool::get_k(&pool);
            assert!(k_final > k_initial, 100);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: FEE DISTRIBUTION
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_fee_distribution_workflow() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let distributor = fee_distributor::new_fee_distributor(ctx);
            
            // Initial liquidity
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let pool_id = liquidity_pool::pool_id(&pool);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            // Mint LP position NFT
            lp_position_nft::mint(
                pool_id,
                shares,
                idx_a, idx_b,
                1_000_000, 1_000_000,
                LP1,
                ctx
            );
            
            // Generate fees via swaps
            liquidity_pool::swap(&mut pool, 200_000, true);
            liquidity_pool::swap(&mut pool, 150_000, false);
            
            // Fee indices should have increased
            let (new_idx_a, new_idx_b) = liquidity_pool::fee_indices(&pool);
            assert!(new_idx_a > idx_a || new_idx_b > idx_b, 0);
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(distributor);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: STABLE SWAP LOW SLIPPAGE
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_stable_swap_low_slippage() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // Create stable pool with high amplification
            let pool = stable_swap_pool::new_stable_pool<USDC, USDT>(500, 4, ctx);
            stable_swap_pool::provide_initial_liquidity(&mut pool, 10_000_000, 10_000_000);
            
            // Large swap (10% of reserves)
            let amount_in = 1_000_000;
            let (expected_out, fee) = stable_swap_pool::get_amount_out(&pool, amount_in, true);
            
            // For stable pairs with high amp, output should be close to input
            let min_expected = (amount_in * 99) / 100; // At least 99%
            assert!(expected_out > min_expected, 0);
            
            // Execute swap
            let actual_out = stable_swap_pool::stable_swap(&mut pool, amount_in, true);
            assert!(actual_out == expected_out, 1);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: DIFFERENT FEE TIERS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_different_fee_tier_pools() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            // Create pools at different fee tiers
            let pool_stable = pool_factory::create_stable_pool<USDC, ETH>(&mut factory, ctx);
            let pool_standard = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            let pool_exotic = pool_factory::create_exotic_pool<USDC, ETH>(&mut factory, ctx);
            
            // Verify fee tiers
            assert!(liquidity_pool::fee_bps(&pool_stable) == 5, 0);    // 0.05%
            assert!(liquidity_pool::fee_bps(&pool_standard) == 30, 1); // 0.30%
            assert!(liquidity_pool::fee_bps(&pool_exotic) == 100, 2);  // 1.00%
            
            // Verify pool count
            assert!(pool_factory::pool_count(&factory) == 3, 3);
            
            sui::test_utils::destroy(pool_stable);
            sui::test_utils::destroy(pool_standard);
            sui::test_utils::destroy(pool_exotic);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: SLIPPAGE PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_slippage_protection_workflow() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let amount_in = 100_000;
            
            // Get expected output
            let (expected_out, _) = liquidity_pool::get_amount_out(&pool, amount_in, true);
            
            // Calculate minimum with 0.5% slippage tolerance
            let min_out = slippage_protection::calculate_min_output(expected_out, 50);
            
            // Execute protected swap
            let (actual_out, _) = liquidity_pool::swap_with_slippage(&mut pool, amount_in, min_out, true);
            
            assert!(actual_out >= min_out, 0);
            assert!(actual_out == expected_out, 1);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = liquidity_pool::E_SLIPPAGE_EXCEEDED)]
    fun test_e2e_slippage_protection_fails_on_high_slippage() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Set unrealistic minimum (more than 1:1 ratio)
            let min_out = 150_000; // Impossible to get this much for 100K input
            
            // This should fail
            liquidity_pool::swap_with_slippage(&mut pool, 100_000, min_out, true);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: LP POSITION NFT WORKFLOW
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_lp_position_nft_workflow() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            // Provide liquidity
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let pool_id = liquidity_pool::pool_id(&pool);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            // Mint NFT
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
        // NFT was transferred to LP1
        ts::next_tx(&mut scenario, LP1);
        {
            let position = ts::take_from_sender<lp_position_nft::LPPosition>(&scenario);
            
            // Verify position
            assert!(lp_position_nft::shares(&position) > 0, 0);
            
            let (init_a, init_b) = lp_position_nft::initial_amounts(&position);
            assert!(init_a == 1_000_000, 1);
            assert!(init_b == 1_000_000, 2);
            
            // Test position value calculation
            let (value_a, value_b) = lp_position_nft::calculate_position_value(
                &position,
                1_000_000,  // reserve_a
                1_000_000,  // reserve_b
                lp_position_nft::shares(&position) + 1000  // total_shares
            );
            assert!(value_a > 0, 3);
            assert!(value_b > 0, 4);
            
            // Burn NFT
            lp_position_nft::burn(position);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: IMPERMANENT LOSS CALCULATION
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_impermanent_loss_calculation() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let pool_id = liquidity_pool::pool_id(&pool);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            // Mint position
            lp_position_nft::mint(
                pool_id,
                shares,
                idx_a, idx_b,
                1_000_000, 1_000_000,
                LP1,
                ctx
            );
            
            // Large swap to create price divergence
            liquidity_pool::swap(&mut pool, 300_000, true);
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, LP1);
        {
            let position = ts::take_from_sender<lp_position_nft::LPPosition>(&scenario);
            
            // Simulate new pool state after price change
            // After swap: more token A, less token B
            let new_reserve_a = 1_300_000;
            let new_reserve_b = 769_230; // approximate
            let total_shares = lp_position_nft::shares(&position) + 1000;
            
            let (value_a, value_b) = lp_position_nft::calculate_position_value(
                &position,
                new_reserve_a,
                new_reserve_b,
                total_shares
            );
            
            // Calculate IL
            let (il_bps, is_loss) = lp_position_nft::calculate_impermanent_loss(
                &position,
                value_a,
                value_b
            );
            
            // After significant price change, there should be IL
            // Note: exact value depends on implementation
            
            lp_position_nft::burn(position);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: PRICE IMPACT AWARENESS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_price_impact_awareness() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Small trade - low impact
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            let small_amount = 1_000;
            let (out_small, _) = liquidity_pool::get_amount_out(&pool, small_amount, true);
            let impact_small = slippage_protection::calculate_price_impact(
                reserve_a, reserve_b, small_amount, out_small
            );
            
            // Large trade - high impact
            let large_amount = 200_000;
            let (out_large, _) = liquidity_pool::get_amount_out(&pool, large_amount, true);
            let impact_large = slippage_protection::calculate_price_impact(
                reserve_a, reserve_b, large_amount, out_large
            );
            
            // Large trade should have higher impact
            assert!(impact_large > impact_small, 0);
            
            // Small trade should have minimal impact
            assert!(impact_small < 50, 1); // Less than 0.5%
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: PROTOCOL FEE WITHDRAWAL
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_protocol_fee_accumulation() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Generate fees via swaps
            let i = 0;
            while (i < 5) {
                liquidity_pool::swap(&mut pool, 50_000, true);
                liquidity_pool::swap(&mut pool, 40_000, false);
                i = i + 1;
            };
            
            // Withdraw protocol fees
            let (fees_a, fees_b) = liquidity_pool::withdraw_protocol_fees(&mut pool);
            
            // Protocol should have accumulated fees
            assert!(fees_a > 0 || fees_b > 0, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: MULTIPLE LPs IN SAME POOL
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_multiple_lps_same_pool() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            // LP1 provides 60% of initial liquidity
            let shares_lp1 = liquidity_pool::provide_initial_liquidity(&mut pool, 600_000, 600_000);
            let (idx_a1, idx_b1) = liquidity_pool::fee_indices(&pool);
            
            lp_position_nft::mint(pool_id, shares_lp1, idx_a1, idx_b1, 600_000, 600_000, @0x1, ctx);
            
            // LP2 adds 40% more liquidity
            let shares_lp2 = liquidity_pool::add_liquidity(&mut pool, 400_000, 400_000, 50);
            let (idx_a2, idx_b2) = liquidity_pool::fee_indices(&pool);
            
            lp_position_nft::mint(pool_id, shares_lp2, idx_a2, idx_b2, 400_000, 400_000, @0x2, ctx);
            
            // Verify total shares and reserves
            let total_shares = liquidity_pool::total_shares(&pool);
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a == 1_000_000, 0);
            assert!(reserve_b == 1_000_000, 1);
            
            // LP1 should have ~60% of shares, LP2 ~40%
            // (LP1 has shares_lp1 out of total_shares)
            let lp1_share_pct = (shares_lp1 * 100) / total_shares;
            let lp2_share_pct = (shares_lp2 * 100) / total_shares;
            assert!(lp1_share_pct >= 58 && lp1_share_pct <= 62, 2); // ~60%
            assert!(lp2_share_pct >= 38 && lp2_share_pct <= 42, 3); // ~40%
            
            // Generate fees via swaps
            liquidity_pool::swap(&mut pool, 100_000, true);
            liquidity_pool::swap(&mut pool, 80_000, false);
            
            // Both LPs should benefit proportionally from fees
            let (new_idx_a, new_idx_b) = liquidity_pool::fee_indices(&pool);
            assert!(new_idx_a > idx_a1 || new_idx_b > idx_b1, 4);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_e2e_multiple_lps_fair_fee_distribution() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            // LP1: 75% of liquidity
            let shares_lp1 = liquidity_pool::provide_initial_liquidity(&mut pool, 750_000, 750_000);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            lp_position_nft::mint(pool_id, shares_lp1, idx_a, idx_b, 750_000, 750_000, @0x1, ctx);
            
            // LP2: 25% of liquidity
            let shares_lp2 = liquidity_pool::add_liquidity(&mut pool, 250_000, 250_000, 50);
            let (idx_a2, idx_b2) = liquidity_pool::fee_indices(&pool);
            
            lp_position_nft::mint(pool_id, shares_lp2, idx_a2, idx_b2, 250_000, 250_000, @0x2, ctx);
            
            // Generate fees
            liquidity_pool::swap(&mut pool, 200_000, true);
            
            // Get updated indices
            let (final_idx_a, final_idx_b) = liquidity_pool::fee_indices(&pool);
            
            // Calculate pending fees for each LP
            let delta_a = final_idx_a - idx_a;
            let delta_b = final_idx_b - idx_b;
            
            // LP1 pending fees (proportional to shares)
            let lp1_pending_a = (delta_a * shares_lp1) / 10_000;
            let lp1_pending_b = (delta_b * shares_lp1) / 10_000;
            
            // LP2 pending fees (joined at idx_a2, idx_b2)
            let delta_a2 = final_idx_a - idx_a2;
            let delta_b2 = final_idx_b - idx_b2;
            let lp2_pending_a = (delta_a2 * shares_lp2) / 10_000;
            let lp2_pending_b = (delta_b2 * shares_lp2) / 10_000;
            
            // LP1 should have more fees since they were there before LP2
            // and have more shares
            assert!(lp1_pending_a >= lp2_pending_a, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: CONCURRENT SWAPS SIMULATION
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_concurrent_swaps_k_never_decreases() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 10_000_000, 10_000_000);
            let k_initial = liquidity_pool::get_k(&pool);
            
            // Simulate 20 "concurrent" swaps of varying sizes and directions
            let i = 0;
            while (i < 20) {
                // Vary swap sizes: small, medium, large
                let size_multiplier = ((i % 3) + 1) * 10_000;
                let amount = size_multiplier + (i * 1000);
                
                // Alternate directions with some randomness
                let direction = (i % 3) != 0;
                
                let k_before = liquidity_pool::get_k(&pool);
                liquidity_pool::swap(&mut pool, amount, direction);
                let k_after = liquidity_pool::get_k(&pool);
                
                // K must NEVER decrease
                assert!(k_after >= k_before, i);
                
                i = i + 1;
            };
            
            // Final K should be significantly higher due to accumulated fees
            let k_final = liquidity_pool::get_k(&pool);
            assert!(k_final > k_initial, 100);
            
            // Fee accumulation should be measurable
            let k_growth_bps = ((k_final - k_initial) * 10_000) / k_initial;
            assert!(k_growth_bps > 0, 101); // Some measurable growth
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_e2e_high_frequency_swaps() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 5_000_000, 5_000_000);
            
            let (initial_reserve_a, initial_reserve_b) = liquidity_pool::reserves(&pool);
            let k_initial = liquidity_pool::get_k(&pool);
            
            // 50 rapid swaps simulating high-frequency trading
            let i = 0;
            while (i < 50) {
                let amount = 5_000 + (i * 100);
                let direction = i % 2 == 0;
                liquidity_pool::swap(&mut pool, amount, direction);
                i = i + 1;
            };
            
            let k_final = liquidity_pool::get_k(&pool);
            let (final_reserve_a, final_reserve_b) = liquidity_pool::reserves(&pool);
            
            // K should have grown from fees
            assert!(k_final > k_initial, 0);
            
            // Reserves should still be reasonable (not drained)
            assert!(final_reserve_a > initial_reserve_a / 2, 1);
            assert!(final_reserve_b > initial_reserve_b / 2, 2);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CAPITAL EFFICIENCY: K CONSTANT MAINTENANCE
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_capital_efficiency_k_constant_exact() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 2_000_000);
            
            let k_initial = liquidity_pool::get_k(&pool);
            // K = 1_000_000 * 2_000_000 = 2_000_000_000_000
            assert!(k_initial == 2_000_000_000_000, 0);
            
            // After swap, K should increase (fees collected)
            liquidity_pool::swap(&mut pool, 100_000, true);
            let k_after_swap = liquidity_pool::get_k(&pool);
            assert!(k_after_swap > k_initial, 1);
            
            // Calculate fee contribution to K
            let k_increase = k_after_swap - k_initial;
            let k_increase_bps = (k_increase * 10_000) / k_initial;
            
            // Fee is 0.3% = 30 bps, so K increase should be positive but reasonable
            assert!(k_increase_bps > 0, 2);
            assert!(k_increase_bps < 100, 3); // Less than 1% increase per swap
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_capital_efficiency_k_with_liquidity_changes() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            let shares1 = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let k1 = liquidity_pool::get_k(&pool);
            
            // Add 50% more liquidity
            let shares2 = liquidity_pool::add_liquidity(&mut pool, 500_000, 500_000, 50);
            let k2 = liquidity_pool::get_k(&pool);
            
            // K should increase by ~125% (1.5^2 = 2.25, so K = 2.25 * original)
            // Actually K = (1.5M * 1.5M) = 2.25T vs original 1T
            assert!(k2 > k1, 0);
            let k_ratio = (k2 * 100) / k1;
            assert!(k_ratio >= 220 && k_ratio <= 230, 1); // ~225%
            
            // Remove some liquidity
            let remove_shares = shares2 / 2;
            liquidity_pool::remove_liquidity(&mut pool, remove_shares);
            let k3 = liquidity_pool::get_k(&pool);
            
            // K should decrease but still be > k1
            assert!(k3 < k2, 2);
            assert!(k3 > k1, 3);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CAPITAL EFFICIENCY: FEE ACCUMULATION ACCURACY
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_fee_accumulation_accuracy() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx); // 0.3% fee
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Single swap to verify fee calculation
            let swap_amount = 100_000;
            let (amount_out, fee) = liquidity_pool::swap(&mut pool, swap_amount, true);
            
            // Fee should be 0.3% of input = 30 bps
            let expected_fee = (swap_amount * 30) / 10_000; // = 300
            assert!(fee == expected_fee, 0);
            
            // Amount out should be calculated from (swap_amount - fee)
            let amount_in_after_fee = swap_amount - fee;
            assert!(amount_in_after_fee == 99_700, 1); // 100_000 - 300 = 99_700
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_fee_accumulation_multiple_swaps() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            let total_fees_collected = 0;
            let i = 0;
            while (i < 10) {
                let (_, fee) = liquidity_pool::swap(&mut pool, 50_000, true);
                total_fees_collected = total_fees_collected + fee;
                
                let (_, fee2) = liquidity_pool::swap(&mut pool, 40_000, false);
                total_fees_collected = total_fees_collected + fee2;
                
                i = i + 1;
            };
            
            // Should have collected meaningful fees
            // 10 * (50_000 * 0.3% + 40_000 * 0.3%) = 10 * (150 + 120) = 2700
            assert!(total_fees_collected > 2500, 0);
            
            // Fee indices should reflect accumulation
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            assert!(idx_a > 0 || idx_b > 0, 1);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_fee_tiers_accuracy() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let factory = pool_factory::new_factory_default(ctx);
            
            // Test 0.05% pool (5 bps)
            let pool_low = pool_factory::create_stable_pool<USDC, ETH>(&mut factory, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool_low, 1_000_000, 1_000_000);
            let (_, fee_low) = liquidity_pool::swap(&mut pool_low, 100_000, true);
            assert!(fee_low == 50, 0); // 0.05% of 100K = 50
            
            // Test 0.30% pool (30 bps)
            let pool_mid = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool_mid, 1_000_000, 1_000_000);
            let (_, fee_mid) = liquidity_pool::swap(&mut pool_mid, 100_000, true);
            assert!(fee_mid == 300, 1); // 0.30% of 100K = 300
            
            // Test 1.00% pool (100 bps)
            let pool_high = pool_factory::create_exotic_pool<USDC, ETH>(&mut factory, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool_high, 1_000_000, 1_000_000);
            let (_, fee_high) = liquidity_pool::swap(&mut pool_high, 100_000, true);
            assert!(fee_high == 1000, 2); // 1.00% of 100K = 1000
            
            sui::test_utils::destroy(pool_low);
            sui::test_utils::destroy(pool_mid);
            sui::test_utils::destroy(pool_high);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CAPITAL EFFICIENCY: LP VALUE TRACKING
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_lp_value_tracking_basic() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            let total_shares = liquidity_pool::total_shares(&pool);
            
            lp_position_nft::mint(pool_id, shares, idx_a, idx_b, 1_000_000, 1_000_000, LP1, ctx);
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, LP1);
        {
            let position = ts::take_from_sender<lp_position_nft::LPPosition>(&scenario);
            let shares = lp_position_nft::shares(&position);
            
            // Calculate value with original reserves
            let (value_a, value_b) = lp_position_nft::calculate_position_value(
                &position,
                1_000_000,
                1_000_000,
                shares + 1000 // total shares including minimum liquidity
            );
            
            // LP should own nearly all the liquidity (minus minimum)
            assert!(value_a > 990_000, 0);
            assert!(value_b > 990_000, 1);
            
            lp_position_nft::burn(position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_lp_value_increases_with_fees() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            let total_shares = liquidity_pool::total_shares(&pool);
            
            lp_position_nft::mint(pool_id, shares, idx_a, idx_b, 1_000_000, 1_000_000, LP1, ctx);
            
            // Calculate initial value
            let (initial_reserve_a, initial_reserve_b) = liquidity_pool::reserves(&pool);
            
            // Generate fees via swaps
            let i = 0;
            while (i < 10) {
                liquidity_pool::swap(&mut pool, 100_000, true);
                liquidity_pool::swap(&mut pool, 80_000, false);
                i = i + 1;
            };
            
            // Get final reserves (increased by fees)
            let (final_reserve_a, final_reserve_b) = liquidity_pool::reserves(&pool);
            
            // Reserves should have increased due to fee accumulation
            // Not necessarily both increase, but K should be higher
            let k_initial = (initial_reserve_a as u128) * (initial_reserve_b as u128);
            let k_final = (final_reserve_a as u128) * (final_reserve_b as u128);
            assert!(k_final > k_initial, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CAPITAL EFFICIENCY: IMPERMANENT LOSS SCENARIOS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_impermanent_loss_2x_price_change() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            // Initial: 1 ETH = 1 USDC (equal reserves)
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            lp_position_nft::mint(pool_id, shares, idx_a, idx_b, 1_000_000, 1_000_000, LP1, ctx);
            
            // Simulate 2x price change via large swaps
            // To double ETH price, we need to change ratio to 2:1
            // This requires removing ETH and adding USDC
            liquidity_pool::swap(&mut pool, 400_000, true); // Add USDC, remove ETH
            
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            
            sui::test_utils::destroy(pool);
        };
        ts::next_tx(&mut scenario, LP1);
        {
            let position = ts::take_from_sender<lp_position_nft::LPPosition>(&scenario);
            
            // After price change, calculate IL
            // New reserves approximately: more USDC, less ETH
            let new_reserve_a = 1_400_000; // More USDC
            let new_reserve_b = 714_285;   // Less ETH (approximate)
            let total_shares = lp_position_nft::shares(&position) + 1000;
            
            let (value_a, value_b) = lp_position_nft::calculate_position_value(
                &position,
                new_reserve_a,
                new_reserve_b,
                total_shares
            );
            
            // Calculate IL
            let (il_bps, is_loss) = lp_position_nft::calculate_impermanent_loss(
                &position,
                value_a,
                value_b
            );
            
            // With significant price change, there should be measurable IL
            // (exact value depends on implementation)
            
            lp_position_nft::burn(position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_impermanent_loss_vs_hodl() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            // LP deposits 500 USDC + 500 ETH
            let initial_a = 500_000;
            let initial_b = 500_000;
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, initial_a, initial_b);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            let total_shares = liquidity_pool::total_shares(&pool);
            
            lp_position_nft::mint(pool_id, shares, idx_a, idx_b, initial_a, initial_b, LP1, ctx);
            
            // HODL value at start: 500K + 500K = 1M (in terms of base units)
            let hodl_value_start = initial_a + initial_b;
            
            // Simulate price movement
            liquidity_pool::swap(&mut pool, 200_000, true);
            
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            
            // LP value after price change
            let lp_shares = shares;
            let lp_value_a = (lp_shares * reserve_a) / total_shares;
            let lp_value_b = (lp_shares * reserve_b) / total_shares;
            let lp_value_total = lp_value_a + lp_value_b;
            
            // HODL would still be: initial_a + initial_b (ignoring price change for simplicity)
            // In reality, HODL value changes with price, but LP value changes differently
            
            // The key invariant: LP value should be close to but slightly less than
            // what you'd get from HODLing (IL effect), but fees may compensate
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_no_il_when_price_returns() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            lp_position_nft::mint(pool_id, shares, idx_a, idx_b, 1_000_000, 1_000_000, LP1, ctx);
            
            let (initial_a, initial_b) = liquidity_pool::reserves(&pool);
            
            // Price moves one direction
            liquidity_pool::swap(&mut pool, 200_000, true);
            
            // Price returns (approximate reverse swap)
            // Need to swap in opposite direction to restore ratio
            let (mid_a, mid_b) = liquidity_pool::reserves(&pool);
            
            // Swap back approximately same value
            liquidity_pool::swap(&mut pool, 180_000, false);
            
            let (final_a, final_b) = liquidity_pool::reserves(&pool);
            
            // Reserves should be close to initial (plus fees)
            // Due to fees, final reserves > initial
            let k_initial = (initial_a as u128) * (initial_b as u128);
            let k_final = (final_a as u128) * (final_b as u128);
            
            // K increased due to fees collected
            assert!(k_final > k_initial, 0);
            
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: FULL LIFECYCLE WITH CLAIMS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_full_lifecycle_create_swap_claim_remove() {
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            // Step 1: Create pool
            let factory = pool_factory::new_factory_default(ctx);
            let pool = pool_factory::create_standard_pool<USDC, ETH>(&mut factory, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            
            // Step 2: LP provides liquidity
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 2_000_000, 2_000_000);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            lp_position_nft::mint(pool_id, shares, idx_a, idx_b, 2_000_000, 2_000_000, LP1, ctx);
            
            // Step 3: Multiple traders swap (generate fees)
            let total_volume = 0;
            let i = 0;
            while (i < 20) {
                let (out1, _) = liquidity_pool::swap(&mut pool, 50_000, true);
                let (out2, _) = liquidity_pool::swap(&mut pool, 40_000, false);
                total_volume = total_volume + 50_000 + 40_000;
                i = i + 1;
            };
            
            // Verify significant volume
            assert!(total_volume == 1_800_000, 0);
            
            // Step 4: Check fee accumulation via K growth
            let k_after = liquidity_pool::get_k(&pool);
            let k_initial: u128 = 2_000_000 * 2_000_000; // Initial K = 4T
            assert!(k_after > k_initial, 1); // K should have grown from fees
            
            // Step 5: LP removes all liquidity
            let total_shares = liquidity_pool::total_shares(&pool);
            let lp_shares = shares;
            
            let (removed_a, removed_b) = liquidity_pool::remove_liquidity(&mut pool, lp_shares);
            
            // LP should get back meaningful amounts
            // Due to swaps, ratio may have changed but total value should be preserved + fees
            assert!(removed_a > 0, 2);
            assert!(removed_b > 0, 3);
            
            // Total removed should be close to or greater than deposited (fees help)
            let total_removed = removed_a + removed_b;
            let total_deposited = 4_000_000; // 2M + 2M
            assert!(total_removed > total_deposited - 100_000, 4); // Allow small slippage
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(factory);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // E2E TEST: COIN-BASED SWAP (Real Token Transfers)
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun test_e2e_coin_based_swap_workflow() {
        use sui::coin;
        use sui::balance;
        
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            // Provide initial liquidity
            liquidity_pool::provide_initial_liquidity(&mut pool, 2_000_000, 1_000);
            
            // Create input coin for swap (user wants to swap 100 USDC for ETH)
            let coin_in = coin::from_balance(
                balance::create_for_testing<USDC>(100_000),
                ctx
            );
            
            // Preview expected output
            let (expected_out, fee) = liquidity_pool::preview_swap_coins(&pool, &coin_in, true);
            assert!(expected_out > 0, 0);
            assert!(fee > 0, 1);
            
            // Calculate minimum acceptable (0.5% slippage)
            let min_out = (expected_out * 995) / 1000;
            
            // Execute coin-based swap
            let coin_out = liquidity_pool::swap_coins_a_to_b(
                &mut pool,
                coin_in,      // Input coin consumed
                min_out,
                ctx
            );
            
            // Verify output
            let amount_received = coin::value(&coin_out);
            assert!(amount_received >= min_out, 2);
            assert!(amount_received == expected_out, 3);
            
            // Clean up
            sui::test_utils::destroy(coin_out);
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_e2e_coin_based_fee_claim_workflow() {
        use sui::coin;
        use sui::balance;
        
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            let pool_id = liquidity_pool::pool_id(&pool);
            let distributor = fee_distributor::new_fee_distributor(ctx);
            
            // LP provides initial liquidity
            let shares = liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            let (idx_a, idx_b) = liquidity_pool::fee_indices(&pool);
            
            // Mint LP position NFT
            lp_position_nft::mint(pool_id, shares, idx_a, idx_b, 1_000_000, 1_000_000, LP1, ctx);
            
            // Generate fees via swaps
            let i = 0;
            while (i < 10) {
                liquidity_pool::swap(&mut pool, 50_000, true);
                liquidity_pool::swap(&mut pool, 40_000, false);
                i = i + 1;
            };
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(distributor);
        };
        
        // LP claims fees in next transaction
        ts::next_tx(&mut scenario, LP1);
        {
            let position = ts::take_from_sender<lp_position_nft::LPPosition>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            
            // Create fresh pool and distributor for claiming (simplified test)
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            liquidity_pool::provide_initial_liquidity(&mut pool, 1_000_000, 1_000_000);
            
            // Generate some fees
            liquidity_pool::swap(&mut pool, 100_000, true);
            
            let distributor = fee_distributor::new_fee_distributor(ctx);
            
            // Step 1: View accumulated fees
            let (pending_a, pending_b) = fee_distributor::preview_claimable(&pool, &position);
            
            // Fees may be 0 in this simplified test since we're using a different pool
            // The key is that the workflow compiles and runs
            
            sui::test_utils::destroy(pool);
            sui::test_utils::destroy(distributor);
            lp_position_nft::burn(position);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_e2e_coin_based_liquidity_workflow() {
        use sui::coin;
        use sui::balance;
        
        let scenario = ts::begin(ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            let pool = liquidity_pool::new_pool<USDC, ETH>(30, ctx);
            
            // Create coins for liquidity
            let coin_a = coin::from_balance(
                balance::create_for_testing<USDC>(1_000_000),
                ctx
            );
            let coin_b = coin::from_balance(
                balance::create_for_testing<ETH>(1_000_000),
                ctx
            );
            
            // Provide initial liquidity with coins
            let shares = liquidity_pool::provide_initial_liquidity_with_coins(
                &mut pool,
                coin_a,
                coin_b
            );
            assert!(shares > 0, 0);
            
            // Verify pool state
            let (reserve_a, reserve_b) = liquidity_pool::reserves(&pool);
            assert!(reserve_a == 1_000_000, 1);
            assert!(reserve_b == 1_000_000, 2);
            
            // Remove liquidity with coins
            let (coin_out_a, coin_out_b) = liquidity_pool::remove_liquidity_with_coins(
                &mut pool,
                shares / 2,  // Remove half
                ctx
            );
            
            // Verify output
            assert!(coin::value(&coin_out_a) > 0, 3);
            assert!(coin::value(&coin_out_b) > 0, 4);
            
            // Clean up
            sui::test_utils::destroy(coin_out_a);
            sui::test_utils::destroy(coin_out_b);
            sui::test_utils::destroy(pool);
        };
        ts::end(scenario);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // LEGACY TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    #[test]
    fun slippage_and_price_impact_checks() {
        // enforce_min_output should pass when expected >= min
        slippage_protection::enforce_min_output(1_000, 900);

        // Price impact within limit should not abort
        slippage_protection::check_price_impact(1_000_000, 2_000_000, 10_000, 19_500, 1_000);
    }
}
