defmodule Ollama do
  @moduledoc """
  ![License](https://img.shields.io/github/license/lebrunel/ollama-ex?color=informational)

  [Ollama](https://ollama.ai) is a nifty little tool for running large language
  models locally, and this is a nifty little library for working with Ollama in
  Elixir.

  ## Highlights

  - API client fully implementing the Ollama API - `Ollama.API`
  - Stream API responses to any Elixir process.
  - Server module implementing OpenAI compatible completion and chat endpoints,
  proxying through to Ollama - *COMING SOON*

  ## Installation

  The package can be installed by adding `ollama` to your list of dependencies
  in `mix.exs`.

  ```elixir
  def deps do
    [
      {:ollama, "~> 0.2"}
    ]
  end
  ```
  """
end
