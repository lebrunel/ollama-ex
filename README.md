# Ollama

![Hex.pm](https://img.shields.io/hexpm/v/ollama?color=informational)
![License](https://img.shields.io/github/license/lebrunel/ollama-ex?color=informational)
![Build Status](https://img.shields.io/github/actions/workflow/status/lebrunel/ollama-ex/elixir.yml?branch=main)

[Ollama](https://ollama.ai) is a nifty little tool for running large language models locally, and this is a nifty little library for working with Ollama in Elixir.

## Highlights

- API client fully implementing the Ollama API - `Ollama.API`
- Server module implementing OpenAI compatible completion and chat endpoints,
proxying through to Ollama - *COMING SOON*

## Installation

The package can be installed by adding `ollama` to your list of dependencies in `mix.exs`.

```elixir
def deps do
  [
    {:ollama, "~> 0.1"}
  ]
end
```

## License

This package is open source and released under the [Apache-2 License](https://github.com/lebrunel/ollama/blob/master/LICENSE).

© Copyright 2023 [Push Code Ltd](https://www.pushcode.com/).