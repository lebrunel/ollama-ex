defmodule Ollama.MixProject do
  use Mix.Project

  def project do
    [
      app: :ollama,
      name: "Ollama",
      description: "A nifty little library for working with Ollama in Elixir.",
      source_url: "https://github.com/lebrunel/ollama-ex",
      version: "0.6.1",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        main: "Ollama"
      ],
      package: [
        name: "ollama",
        files: ~w(lib .formatter.exs mix.exs README.md LICENSE),
        licenses: ["Apache-2.0"],
        links: %{
          "GitHub" => "https://github.com/lebrunel/ollama-ex"
        }
      ]
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
      {:bandit, "~> 1.4", only: :test},
      {:ex_doc, "~> 0.32", only: :dev, runtime: false},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:plug, "~> 1.15"},
      {:req, "~> 0.4"},
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test"]
  defp elixirc_paths(_), do: ["lib"]
end
