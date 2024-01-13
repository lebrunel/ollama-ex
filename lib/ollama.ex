defmodule Ollama do
  @moduledoc """
  [Ollama](https://ollama.ai) is a nifty little tool for running large language
  models locally, and this is a nifty little library for working with Ollama in
  Elixir.

  ## Highlights

  - API client fully implementing the Ollama API - `Ollama.API`
  - Server module implementing OpenAI compatible completion and chat endpoints,
  proxying through to Ollama - *COMING SOON*

  ## Installation

  The package can be installed by adding `ollama` to your list of dependencies
  in `mix.exs`.

  ```elixir
  def deps do
    [
      {:ollama, "~> 0.1"}
    ]
  end
  ```
  """
end
