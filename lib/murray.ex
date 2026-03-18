defmodule Murray do
  @moduledoc """
  Solana swap logic ported from Python.
  """

  require Logger
  
  # --- CONFIGURATION ---
  @rpc_url "https://api.mainnet-beta.solana.com"
  @jupiter_base_url "https://api.jup.ag/swap/v1"
  
  # Mints
  @usdc_mint "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
  @memecoin_mint "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
  @amount_usdc_raw 1_000_000 # 1 USDC

  def run do
    Dotenvy.source!(".env")
    |> System.put_env()

    execute_swap()
  end

  def execute_swap do
    case get_wallet() do
      nil ->
        Logger.error("Failed to load wallet")
      wallet ->
        Logger.info("Wallet Public Key: #{Base58.encode(wallet.public_key)}")
        Logger.info("Swapping #{@amount_usdc_raw / 1_000_000} USDC for Memecoin...")

        # 1. Get Quote
        case get_quote(@usdc_mint, @memecoin_mint, @amount_usdc_raw) do
          {:ok, quote} ->
            Logger.info("Quote received:")
            Logger.info("Out Amount: #{String.to_integer(quote["outAmount"]) / 100_000.0} (approx)")
            if quote["priceImpactPct"], do: Logger.info("Price Impact: #{quote["priceImpactPct"]}%")

            # 2. Get Transaction
            case get_swap_transaction(quote, wallet.public_key) do
              {:ok, swap_response} ->
                swap_transaction_buf = swap_response["swapTransaction"]
                
                # Deserialize, Sign and Serialize
                case sign_transaction(swap_transaction_buf, wallet) do
                  {:ok, signed_tx_base64} ->
                    Logger.info("Transaction signed successfully")
                    
                    # 4. Send Transaction
                    send_and_confirm_transaction(signed_tx_base64)

                  other ->
                    Logger.error("Unexpected error signing transaction: #{inspect(other)}")
                end

              {:error, reason} ->
                Logger.error("Failed to get swap transaction: #{inspect(reason)}")
            end

          {:error, reason} ->
            Logger.error("Failed to get quote: #{inspect(reason)}")
        end
    end
  end

  def get_wallet do
    private_key_string = System.get_env("SOLANA_PRIVATE_KEY")
    if is_nil(private_key_string) do
      Logger.error("SOLANA_PRIVATE_KEY environment variable not set")
      nil
    else
      try do
        bytes =
          if String.contains?(private_key_string, "[") do
            private_key_string
            |> Jason.decode!()
            |> :erlang.list_to_binary()
          else
            Base58.decode(private_key_string)
          end

        # Solana keys are usually 64 bytes (secret + public) 
        # but ed25519 lib often just needs the 32-byte secret.
        case byte_size(bytes) do
          64 ->
            <<secret_key::binary-size(32), public_key::binary-size(32)>> = bytes
            %{secret_key: secret_key, public_key: public_key}
          32 ->
            secret_key = bytes
            public_key = Ed25519.derive_public_key(secret_key)
            %{secret_key: secret_key, public_key: public_key}
          other ->
            Logger.error("Invalid private key size: #{other} bytes")
            nil
        end
      rescue
        e ->
          Logger.error("Error loading wallet: #{inspect(e)}")
          nil
      end
    end
  end

  def get_quote(input_mint, output_mint, amount, slippage_bps \\ 50) do
    params = [
      inputMint: input_mint,
      outputMint: output_mint,
      amount: amount,
      slippageBps: slippage_bps
    ]
    
    headers = jupiter_headers()
    
    Req.get("#{@jupiter_base_url}/quote", params: params, headers: headers)
    |> case do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, response} -> {:error, "Status #{response.status}: #{inspect(response.body)}"}
      {:error, error} -> {:error, error}
    end
  end

  def get_swap_transaction(quote_response, wallet_pubkey) do
    payload = %{
      "quoteResponse" => quote_response,
      "userPublicKey" => Base58.encode(wallet_pubkey),
      "wrapAndUnwrapSol" => true,
      "dynamicComputeUnitLimit" => true,
      "prioritizationFeeLamports" => "auto"
    }
    
    headers = jupiter_headers()
    
    Req.post("#{@jupiter_base_url}/swap", json: payload, headers: headers)
    |> case do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, response} -> {:error, "Status #{response.status}: #{inspect(response.body)}"}
      {:error, error} -> {:error, error}
    end
  end

  defp jupiter_headers do
    case System.get_env("JUPITER_API_KEY") do
      nil -> []
      key -> [{"x-api-key", key}]
    end
  end

  def sign_transaction(swap_transaction_b64, wallet) do
    # Jupiter returns base64
    raw_tx = Base.decode64!(swap_transaction_b64)
    
    # Versioned Transaction:
    # [compact-u16 signatures_count]
    # [signatures...]
    # [message]
    
    {sig_count, rest} = decode_compact_u16(raw_tx)
    
    # Each signature is 64 bytes
    sig_size = sig_count * 64
    <<_existing_sigs::binary-size(sig_size), message::binary>> = rest
    
    # Sign the message
    # Solana signing uses ed25519
    signature = Ed25519.signature(message, wallet.secret_key, wallet.public_key)
    
    # Re-assemble the transaction
    # Since we are the only signer (usually), we replace the first signature
    # In some cases Jupiter might return more signers, but for basic swap it's 1.
    
    # Let's assume sig_count is 1 for now.
    if sig_count != 1 do
      Logger.warning("Transaction has #{sig_count} signers, only signing as first")
    end
    
    # New signatures list: [new_sig, ...other_sigs_as_zeros?]
    # Actually, we should only replace our signature.
    # But usually Jupiter provides a transaction where we are the only signature needed.
    
    signed_tx = 
      encode_compact_u16(sig_count) <> 
      signature <> 
      (if sig_count > 1, do: <<0::size((sig_count - 1) * 64 * 8)>>, else: <<>>) <>
      message
      
    {:ok, Base.encode64(signed_tx)}
  end

  def send_and_confirm_transaction(signed_tx_base64) do
    Logger.info("Sending transaction...")
    
    payload = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "sendTransaction",
      "params" => [
        signed_tx_base64,
        %{"encoding" => "base64", "skipPreflight" => true}
      ]
    }
    
    case Req.post(@rpc_url, json: payload) do
      {:ok, %{status: 200, body: %{"result" => signature}}} ->
        Logger.info("Transaction Signature: #{signature}")
        Logger.info("View on Solscan: https://solscan.io/tx/#{signature}")
        
        # Wait for confirmation (simplified)
        confirm_transaction(signature)
        
      {:ok, %{body: body}} ->
        Logger.error("Failed to send transaction: #{inspect(body)}")
      {:error, error} ->
        Logger.error("RPC Error: #{inspect(error)}")
    end
  end

  defp confirm_transaction(signature) do
    Logger.info("Waiting for confirmation...")

    payload = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "getSignatureStatuses",
      "params" => [[signature]]
    }

    case Req.post(@rpc_url, json: payload) do
      {:ok, %{status: 200, body: %{"result" => %{"value" => [status]}}}} ->
        Logger.info("Status: #{inspect(status)}")
      {:ok, %{body: body}} ->
        Logger.error("Failed to get status: #{inspect(body)}")
      {:error, error} ->
        Logger.error("RPC Error: #{inspect(error)}")
    end
  end

  import Bitwise

  # Helper for compact-u16 (Solana's VarInt)
  defp decode_compact_u16(<<0::1, val::7, rest::binary>>), do: {val, rest}
  defp decode_compact_u16(<<1::1, val_low::7, 0::1, val_high::7, rest::binary>>) do
    {val_low + (val_high <<< 7), rest}
  end
  # Add more cases if needed, but signatures count is usually small.
  defp decode_compact_u16(bin), do: {0, bin} # Fallback

  defp encode_compact_u16(val) when val < 128, do: <<val>>
  defp encode_compact_u16(val) when val < 16384 do
    <<1::1, band(val, 127)::7, 0::1, bsr(val, 7)::7>>
  end

end
