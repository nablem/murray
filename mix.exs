defmodule Murray.MixProject do
  use Mix.Project

  def project do
    [
      app: :murray,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5.0"},
      {:jason, "~> 1.4"},
      {:ed25519, "~> 1.5"},
      {:b58, "~> 1.0.3"},
      {:dotenvy, "~> 0.8.0"}
    ]
  end
end
