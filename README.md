# Ollama

![Ollama-ex](https://raw.githubusercontent.com/lebrunel/ollama-ex/main/media/poster.webp)

![Hex.pm](https://img.shields.io/hexpm/v/ollama?color=informational)
![License](https://img.shields.io/github/license/lebrunel/ollama-ex?color=informational)
![Build Status](https://img.shields.io/github/actions/workflow/status/lebrunel/ollama-ex/elixir.yml?branch=main)

[Ollama](https://ollama.ai) is a nifty little tool for running large language models locally, and this is a nifty little library for working with Ollama in Elixir.

## Highlights

- API client fully implementing the Ollama API - see `Ollama.API`.
- Stream API responses to any Elixir process.
- OpenAI API to Ollama API proxy plug - *COMING SOON*

## Installation

The package can be installed by adding `ollama` to your list of dependencies in `mix.exs`.

```elixir
def deps do
  [
    {:ollama, "~> 0.3"}
  ]
end
```

## Quickstart

For more examples, refer to the [`Ollama.API`](https://hexdocs.pm/ollama/Ollama.API.html) documentation.

### 1. Generate a completion

```elixir
iex> api = Ollama.API.new

iex> Ollama.API.completion(api, [
...>   model: "llama2",
...>   prompt: "Why is the sky blue?",
...> ])
{:ok, %{"response" => "The sky is blue because it is the color of the sky.", ...}}
```

### 2. Generate the next message in a chat

```elixir
iex> api = Ollama.API.new
iex> messages = [
...>   %{role: "system", content: "You are a helpful assistant."},
...>   %{role: "user", content: "Why is the sky blue?"},
...>   %{role: "assistant", content: "Due to rayleigh scattering."},
...>   %{role: "user", content: "How is that different than mie scattering?"},
...> ]

iex> Ollama.API.chat(api, [
...>   model: "llama2",
...>   messages: messages,
...> ])
{:ok, %{"message" => %{
  "role" => "assistant",
  "content" => "Mie scattering affects all wavelengths similarly, while Rayleigh favors shorter ones."
}, ...}}
```

### 3. Stream response to any Elixir process

Both the completion and chat endpoints support streaming. Passing the `:stream`
options as `true` will return a `t:Task.t/0` that streams messages back to the
calling process. Alteratively, passing a `t:pid/0` will stream messages to that
process.

```elixir
iex> Ollama.API.completion(api, [
...>   model: "llama2",
...>   prompt: "Why is the sky blue?",
...>   stream: true,
...> ])
{:ok, %Task{pid: current_message_pid}}

iex> Ollama.API.chat(api, [
...>   model: "llama2",
...>   messages: messages,
...>   stream: true,
...> ])
{:ok, %Task{pid: current_message_pid}}
```

You could manually create a `receive` block to handle messages.

```elixir
iex> receive do
...>   {^current_message_pid, {:data, %{"done" => true} = data}} ->
...>     # handle last message
...>   {^current_message_pid, {:data, data}} ->
...>     # handle message
...>   {_pid, _data_} ->
...>     # this message was not expected!
...>  end
```

In most cases you will probably use `c:GenServer.handle_info/2`. See the
[section on Streaming](https://hexdocs.pm/ollama/Ollama.API.html#module-streaming) for more examples.

## License

This package is open source and released under the [Apache-2 License](https://github.com/lebrunel/ollama/blob/master/LICENSE).

© Copyright 2024 [Push Code Ltd](https://www.pushcode.com/).
