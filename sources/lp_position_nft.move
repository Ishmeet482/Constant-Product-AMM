#[allow(unused_const, lint(custom_state_change))]
module sui_amm_nft_lp::lp_position_nft {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::event;
    use sui::package;
    use sui::display;
    use std::string;

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════

    const BPS_DENOMINATOR: u64 = 10_000;

    // ═══════════════════════════════════════════════════════════════════════════════
    // ERROR CODES
    // ═══════════════════════════════════════════════════════════════════════════════

    const E_ZERO_SHARES: u64 = 1;
    const E_INSUFFICIENT_SHARES: u64 = 2;
    const E_POOL_MISMATCH: u64 = 3;

    // ═══════════════════════════════════════════════════════════════════════════════
    // ONE-TIME WITNESS (for Display)
    // ═══════════════════════════════════════════════════════════════════════════════

    /// One-Time Witness for initializing Display
    struct LP_POSITION_NFT has drop {}

    // ═══════════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// NFT representing a liquidity provider's position in a pool.
    /// Contains all metadata needed for fee tracking, value display, and IL calculation.
    struct LPPosition has key, store {
        id: UID,
        /// ID of the pool this position belongs to
        pool_id: ID,
        /// Number of LP shares owned
        lp_shares: u64,
        /// Last observed global fee index for token A (for fee calculation)
        last_fee_index_a: u64,
        /// Last observed global fee index for token B (for fee calculation)
        last_fee_index_b: u64,
        /// Cumulative claimed fees in token A (for display)
        claimed_fees_a: u64,
        /// Cumulative claimed fees in token B (for display)
        claimed_fees_b: u64,
        /// Initial deposit amounts (for IL calculation)
        initial_amount_a: u64,
        initial_amount_b: u64,
        /// Timestamp of position creation (epoch)
        created_at: u64,
        /// Position name/label (user-customizable)
        name: vector<u8>,
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Emitted when a new LP position NFT is minted
    struct PositionMinted has copy, drop {
        position_id: ID,
        pool_id: ID,
        lp_shares: u64,
        owner: address,
    }

    /// Emitted when an LP position NFT is burned
    struct PositionBurned has copy, drop {
        position_id: ID,
        pool_id: ID,
        final_shares: u64,
    }

    /// Emitted when fees are claimed from a position
    struct FeesClaimed has copy, drop {
        position_id: ID,
        amount_a: u64,
        amount_b: u64,
    }

    /// Emitted when position shares are updated
    struct SharesUpdated has copy, drop {
        position_id: ID,
        old_shares: u64,
        new_shares: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // DISPLAY INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Initialize Display for LPPosition NFT when the module is published.
    /// This enables wallets to properly render the NFT metadata.
    fun init(otw: LP_POSITION_NFT, ctx: &mut TxContext) {
        let keys = vector[
            string::utf8(b"name"),
            string::utf8(b"description"),
            string::utf8(b"image_url"),
            string::utf8(b"project_url"),
            string::utf8(b"lp_shares"),
            string::utf8(b"pool_id"),
            string::utf8(b"initial_deposit_a"),
            string::utf8(b"initial_deposit_b"),
            string::utf8(b"claimed_fees_a"),
            string::utf8(b"claimed_fees_b"),
            string::utf8(b"created_at"),
        ];

        let values = vector[
            // Name: Uses the customizable name field
            string::utf8(b"{name}"),
            // Description: Dynamic description with key metrics
            string::utf8(b"Liquidity Provider Position NFT representing {lp_shares} LP shares in an AMM pool. This NFT tracks your liquidity position, accumulated fees, and enables fee claiming."),
            // Image URL: Placeholder - can be updated to a dynamic SVG generator or IPFS image
            string::utf8(b"https://sui-amm.io/nft/lp-position.svg"),
            // Project URL
            string::utf8(b"https://sui-amm.io"),
            // LP Shares
            string::utf8(b"{lp_shares}"),
            // Pool ID
            string::utf8(b"{pool_id}"),
            // Initial deposit amounts
            string::utf8(b"{initial_amount_a}"),
            string::utf8(b"{initial_amount_b}"),
            // Claimed fees
            string::utf8(b"{claimed_fees_a}"),
            string::utf8(b"{claimed_fees_b}"),
            // Creation timestamp
            string::utf8(b"{created_at}"),
        ];

        // Create the Publisher capability
        let publisher = package::claim(otw, ctx);

        // Create the Display with the defined fields
        let display = display::new_with_fields<LPPosition>(
            &publisher,
            keys,
            values,
            ctx
        );

        // Commit the Display (makes it active)
        display::update_version(&mut display);

        // Transfer Publisher and Display to the sender (deployer)
        transfer::public_transfer(publisher, sui::tx_context::sender(ctx));
        transfer::public_transfer(display, sui::tx_context::sender(ctx));
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // MINTING & BURNING
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Mint a new LP position NFT when providing liquidity
    public fun mint(
        pool_id: ID,
        lp_shares: u64,
        curr_fee_index_a: u64,
        curr_fee_index_b: u64,
        initial_amount_a: u64,
        initial_amount_b: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        assert!(lp_shares > 0, E_ZERO_SHARES);

        let nft = LPPosition {
            id: object::new(ctx),
            pool_id,
            lp_shares,
            last_fee_index_a: curr_fee_index_a,
            last_fee_index_b: curr_fee_index_b,
            claimed_fees_a: 0,
            claimed_fees_b: 0,
            initial_amount_a,
            initial_amount_b,
            created_at: sui::tx_context::epoch(ctx),
            name: b"LP Position",
        };

        let position_id = object::id(&nft);
        event::emit(PositionMinted {
            position_id,
            pool_id,
            lp_shares,
            owner: recipient,
        });

        transfer::transfer(nft, recipient)
    }

    /// Burn an LP position NFT when fully removing liquidity
    public fun burn(position: LPPosition) {
        let LPPosition {
            id,
            pool_id,
            lp_shares,
            last_fee_index_a: _,
            last_fee_index_b: _,
            claimed_fees_a: _,
            claimed_fees_b: _,
            initial_amount_a: _,
            initial_amount_b: _,
            created_at: _,
            name: _,
        } = position;

        event::emit(PositionBurned {
            position_id: object::uid_to_inner(&id),
            pool_id,
            final_shares: lp_shares,
        });

        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Get the position's unique ID
    public fun id(position: &LPPosition): ID {
        object::id(position)
    }

    /// Get the pool ID this position belongs to
    public fun pool(position: &LPPosition): ID {
        position.pool_id
    }

    /// Get the number of LP shares
    public fun shares(position: &LPPosition): u64 {
        position.lp_shares
    }

    /// Get the last observed fee indices
    public fun last_fee_indices(position: &LPPosition): (u64, u64) {
        (position.last_fee_index_a, position.last_fee_index_b)
    }

    /// Get cumulative claimed fees
    public fun claimed_fees(position: &LPPosition): (u64, u64) {
        (position.claimed_fees_a, position.claimed_fees_b)
    }

    /// Get initial deposit amounts (for IL calculation)
    public fun initial_amounts(position: &LPPosition): (u64, u64) {
        (position.initial_amount_a, position.initial_amount_b)
    }

    /// Get position creation timestamp
    public fun created_at(position: &LPPosition): u64 {
        position.created_at
    }

    /// Get position name
    public fun name(position: &LPPosition): &vector<u8> {
        &position.name
    }

    /// Calculate current position value given pool reserves and total shares.
    /// Returns (value_a, value_b) representing the underlying token amounts.
    public fun calculate_position_value(
        position: &LPPosition,
        pool_reserve_a: u64,
        pool_reserve_b: u64,
        pool_total_shares: u64,
    ): (u64, u64) {
        if (pool_total_shares == 0) return (0, 0);

        let value_a = ((position.lp_shares as u128) * (pool_reserve_a as u128) / (pool_total_shares as u128) as u64);
        let value_b = ((position.lp_shares as u128) * (pool_reserve_b as u128) / (pool_total_shares as u128) as u64);

        (value_a, value_b)
    }

    /// Calculate impermanent loss in basis points.
    /// IL = 2 * sqrt(price_ratio) / (1 + price_ratio) - 1
    /// Returns the IL percentage scaled by BPS_DENOMINATOR (10000 = 100%)
    /// Positive value means loss, negative means gain vs holding.
    public fun calculate_impermanent_loss(
        position: &LPPosition,
        current_value_a: u64,
        current_value_b: u64,
    ): (u64, bool) {
        let (init_a, init_b) = (position.initial_amount_a, position.initial_amount_b);
        if (init_a == 0 || init_b == 0) return (0, false);

        // Calculate value if held (HODL value)
        // For simplicity, we compare total value in terms of token A
        // HODL value = init_a + init_b * (current_price_b_in_a)
        // LP value = current_value_a + current_value_b * (current_price_b_in_a)

        // Simplified: just compare sum of values
        let hodl_value = init_a + init_b;
        let lp_value = current_value_a + current_value_b;

        if (lp_value >= hodl_value) {
            // No impermanent loss (gain)
            let gain_bps = ((lp_value - hodl_value) * BPS_DENOMINATOR) / hodl_value;
            (gain_bps, false) // false = no loss
        } else {
            // Impermanent loss
            let loss_bps = ((hodl_value - lp_value) * BPS_DENOMINATOR) / hodl_value;
            (loss_bps, true) // true = loss
        }
    }

    /// Calculate pending fees that can be claimed.
    /// Returns (pending_a, pending_b).
    public fun calculate_pending_fees(
        position: &LPPosition,
        current_fee_index_a: u64,
        current_fee_index_b: u64,
    ): (u64, u64) {
        let delta_index_a = current_fee_index_a - position.last_fee_index_a;
        let delta_index_b = current_fee_index_b - position.last_fee_index_b;

        let pending_a = (delta_index_a * position.lp_shares) / BPS_DENOMINATOR;
        let pending_b = (delta_index_b * position.lp_shares) / BPS_DENOMINATOR;

        (pending_a, pending_b)
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // MUTATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Update the last observed indices and cumulative claimed fees.
    /// Used by the FeeDistributor when an LP claims.
    public fun update_metadata(
        position: &mut LPPosition,
        new_last_index_a: u64,
        new_last_index_b: u64,
        claimed_delta_a: u64,
        claimed_delta_b: u64,
    ) {
        position.last_fee_index_a = new_last_index_a;
        position.last_fee_index_b = new_last_index_b;
        position.claimed_fees_a = position.claimed_fees_a + claimed_delta_a;
        position.claimed_fees_b = position.claimed_fees_b + claimed_delta_b;

        if (claimed_delta_a > 0 || claimed_delta_b > 0) {
            event::emit(FeesClaimed {
                position_id: object::id(position),
                amount_a: claimed_delta_a,
                amount_b: claimed_delta_b,
            });
        };
    }

    /// Increase LP shares for a position (when adding more liquidity).
    public fun add_shares(position: &mut LPPosition, delta: u64) {
        let old_shares = position.lp_shares;
        position.lp_shares = position.lp_shares + delta;

        event::emit(SharesUpdated {
            position_id: object::id(position),
            old_shares,
            new_shares: position.lp_shares,
        });
    }

    /// Decrease LP shares for a position (when removing liquidity).
    /// Caller must ensure delta <= current shares.
    public fun reduce_shares(position: &mut LPPosition, delta: u64) {
        assert!(position.lp_shares >= delta, E_INSUFFICIENT_SHARES);

        let old_shares = position.lp_shares;
        position.lp_shares = position.lp_shares - delta;

        event::emit(SharesUpdated {
            position_id: object::id(position),
            old_shares,
            new_shares: position.lp_shares,
        });
    }

    /// Update position name (user customization)
    public fun set_name(position: &mut LPPosition, new_name: vector<u8>) {
        position.name = new_name;
    }

    /// Update initial amounts (used when adding to existing position)
    public fun update_initial_amounts(
        position: &mut LPPosition,
        additional_a: u64,
        additional_b: u64,
    ) {
        position.initial_amount_a = position.initial_amount_a + additional_a;
        position.initial_amount_b = position.initial_amount_b + additional_b;
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // TRANSFER HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// Transfer position to a new owner
    public fun transfer_position(position: LPPosition, recipient: address) {
        transfer::transfer(position, recipient);
    }
}
