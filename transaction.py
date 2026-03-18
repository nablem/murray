import base64
import json
import os
import requests
from dotenv import load_dotenv

load_dotenv()

from solders.keypair import Keypair
from solders.transaction import VersionedTransaction
from solders.message import to_bytes_versioned
from solana.rpc.api import Client
from solana.rpc.types import TxOpts

# --- CONFIGURATION ---
RPC_URL = "https://api.mainnet-beta.solana.com"

PRIVATE_KEY_STRING = os.getenv("SOLANA_PRIVATE_KEY")
JUPITER_BASE_URL = "https://api.jup.ag/swap/v1"
JUPITER_API_KEY = os.getenv("JUPITER_API_KEY")

# Mints
USDC_MINT = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
MEMECOIN_MINT = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"

AMOUNT_USDC_RAW = 1_000_000  # 1 USDC


def get_wallet():
    """Load wallet from private key string."""
    try:
        if "[" in PRIVATE_KEY_STRING:
            return Keypair.from_bytes(json.loads(PRIVATE_KEY_STRING))
        else:
            return Keypair.from_base58_string(PRIVATE_KEY_STRING)
    except Exception as e:
        print(f"Error loading wallet: {e}")
        return None


def get_quote(input_mint, output_mint, amount, slippage_bps=50):
    """Get a quote from Jupiter."""
    url = f"{JUPITER_BASE_URL}/quote"
    headers = {}
    if JUPITER_API_KEY:
        headers["x-api-key"] = JUPITER_API_KEY
    
    params = {
        "inputMint": input_mint,
        "outputMint": output_mint,
        "amount": amount,
        "slippageBps": slippage_bps
    }
    
    response = requests.get(url, params=params, headers=headers)
    response.raise_for_status()
    return response.json()


def get_swap_transaction(quote_response, wallet_pubkey):
    """Get the serialized swap transaction from Jupiter."""
    url = f"{JUPITER_BASE_URL}/swap"
    headers = {"Content-Type": "application/json"}
    if JUPITER_API_KEY:
        headers["x-api-key"] = JUPITER_API_KEY
    
    payload = {
        "quoteResponse": quote_response,
        "userPublicKey": str(wallet_pubkey),
        "wrapAndUnwrapSol": True,
        "dynamicComputeUnitLimit": True,
        "prioritizationFeeLamports": "auto"
    }
    
    response = requests.post(url, json=payload, headers=headers)
    response.raise_for_status()
    return response.json()


def execute_swap():
    wallet = get_wallet()
    if not wallet:
        return
    
    client = Client(RPC_URL)
    
    print(f"Wallet Public Key: {wallet.pubkey()}")
    print(f"Swapping {AMOUNT_USDC_RAW / 1e6} USDC for Memecoin...")
    
    # 1. Get Quote
    try:
        quote = get_quote(USDC_MINT, MEMECOIN_MINT, AMOUNT_USDC_RAW)
        print("Quote received:")
        print(f"Out Amount: {int(quote['outAmount']) / 1e5} (approx)")
        if 'priceImpactPct' in quote:
            print(f"Price Impact: {quote['priceImpactPct']}%")
    except Exception as e:
        print(f"Failed to get quote: {e}")
        return
    
    # 2. Get Transaction
    try:
        swap_response = get_swap_transaction(quote, wallet.pubkey())
        swap_transaction_buf = swap_response['swapTransaction']
        
        # Deserialize the transaction
        raw_tx = base64.b64decode(swap_transaction_buf)
        versioned_tx = VersionedTransaction.from_bytes(raw_tx)
        
        print(f"Transaction deserialized successfully")
        
    except Exception as e:
        print(f"Failed to get swap transaction: {e}")
        import traceback
        traceback.print_exc()
        return
    
    # 3. Sign Transaction - UPDATED METHOD
    try:
        # Convert message to bytes using the proper method
        message_bytes = to_bytes_versioned(versioned_tx.message)
        
        # Sign the message bytes
        signature = wallet.sign_message(message_bytes)
        
        # Create signed transaction with the signature
        signed_tx = VersionedTransaction.populate(versioned_tx.message, [signature])
        
        print(f"Transaction signed successfully")
        print(f"Signature: {signature}")
        
    except Exception as e:
        print(f"Failed to sign transaction: {e}")
        import traceback
        traceback.print_exc()
        return
    
    # 4. Send Transaction
    print("Sending transaction...")
    try:
        serialized_tx = bytes(signed_tx)
        
        # Try with skip_preflight=True first for debugging
        opts = client.send_raw_transaction(
            serialized_tx,
            opts=TxOpts(skip_preflight=True)
        )
        
        print(f"Transaction Signature: {opts.value}")
        print(f"View on Solscan: https://solscan.io/tx/{opts.value}")
        
        # Wait for confirmation
        print("Waiting for confirmation...")
        confirmation = client.confirm_transaction(opts.value, commitment="confirmed")
        print(f"Confirmation: {confirmation}")
        
    except Exception as e:
        print(f"Transaction failed: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    execute_swap()