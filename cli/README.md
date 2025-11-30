# Sui AMM Demo CLI

This is a small local CLI that simulates the AMM behavior defined in the Move modules. It does **not** talk to a Sui node yet, but it mirrors the constant-product math and fee basis points.

## Usage

From the project root:

```bash
cd cli
npm install  # no dependencies, but prepares the package
npm run start
```

Then follow the prompts to:

- Create a pool with token symbols, fee bps, and initial reserves.
- List existing pools and see reserves.
- Request a swap quote and optionally execute the swap.

This helps you experiment with pool creation and swaps before wiring a full on-chain or web UI.
