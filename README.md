# Murray

An efficient Elixir port of Solana swap logic, enabling seamless token swaps via the Jupiter aggregator. This project provides a robust foundation for building Solana-based DeFi applications using the power of the Erlang VM.

## Features

- **Jupiter V6 Integration**: High-performance quote fetching and swap transaction generation.
- **Smart Wallet Loading**: Support for both Base58 encoded private keys and byte array formats.
- **Native Ed25519 Signing**: Secure transaction signing using Elixir's `:ed25519` library.
- **Automated Environment Management**: Integrated with `Dotenvy` for secure configuration.
- **Transaction Monitoring**: Built-in support for sending and monitoring transaction status.

## Tech Stack

- **Language**: Elixir 1.19+
- **HTTP Client**: [Req](https://github.com/wojtekmach/req)
- **JSON Parser**: [Jason](https://github.com/michalmuskala/jason)
- **Crypto**: [Ed25519](https://github.com/ex-crypto/ed25519)
- **Encoding**: [B58](https://github.com/mwylde/b58)

## Getting Started

### Prerequisites

- Elixir and Erlang installed.
- A Solana wallet with some USDC and SOL for gas.
- (Optional) A Jupiter API key for higher rate limits.

### Configuration

Create a `.env` file in the root directory:

```env
SOLANA_PRIVATE_KEY="your_private_key_here"
JUPITER_API_KEY="your_optional_api_key"
```

### Installation

1. Install dependencies:
   ```bash
   mix deps.get
   ```

2. Run the swap logic:
   ```bash
   mix run -e "Murray.run()"
   ```

## Development

The core logic resides in `lib/murray.ex`. The application handles the full lifecycle:
1. Load environment variables.
2. Derive wallet keys.
3. Fetch a quote from Jupiter.
4. Generate and sign the versioned transaction.
5. Broadcast and track the transaction status.

---
*Disclaimer: This software is for educational purposes. Use it at your own risk when handling real assets on the Solana network.*
