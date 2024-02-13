# Ollama

![Ollama-ex](https://raw.githubusercontent.com/lebrunel/ollama-ex/main/media/poster.webp)

![Hex.pm](https://img.shields.io/hexpm/v/ollama?color=informational)
![License](https://img.shields.io/github/license/lebrunel/ollama-ex?color=informational)
![Build Status](https://img.shields.io/github/actions/workflow/status/lebrunel/ollama-ex/elixir.yml?branch=main)

[Ollama](https://ollama.ai) is a nifty little tool for running large language models locally, and this is a nifty little library for working with Ollama in Elixir.

- API client fully implementing the Ollama API.
- Stream API responses to any Elixir process.

## Installation

The package can be installed by adding `ollama` to your list of dependencies in `mix.exs`.

```elixir
def deps do
  [
    {:ollama, "~> 0.4"}
  ]
end
```

## Quickstart

For more examples, refer to the [Ollama documentation](https://hexdocs.pm/ollama).

### 1. Generate a completion

```elixir
iex> client = Ollama.init()

iex> Ollama.completion(client, [
...>   model: "llama2",
...>   prompt: "Why is the sky blue?",
...> ])
{:ok, %{"response" => "The sky is blue because it is the color of the sky.", ...}}
```

### 2. Generate the next message in a chat

```elixir
iex> client = Ollama.init()
iex> messages = [
...>   %{role: "system", content: "You are a helpful assistant."},
...>   %{role: "user", content: "Why is the sky blue?"},
...>   %{role: "assistant", content: "Due to rayleigh scattering."},
...>   %{role: "user", content: "How is that different than mie scattering?"},
...> ]

iex> Ollama.chat(client, [
...>   model: "llama2",
...>   messages: messages,
...> ])
{:ok, %{"message" => %{
  "role" => "assistant",
  "content" => "Mie scattering affects all wavelengths similarly, while Rayleigh favors shorter ones."
}, ...}}
```

## Streaming

By default, all endpoints are called with streaming disabled, blocking unti the HTTP request completes and the response body is returned. For endpoints where streaming is supported, the `:stream` option can be set to `true` or a `t:pid/0`. When streaming is enabled, the function returns a `t:Task.t/0`, which asynchronously sends messages back to either the calling process, or the process associated with the given `t:pid/0`.

```elixir
iex> Ollama.completion(client, [
...>   model: "llama2",
...>   prompt: "Why is the sky blue?",
...>   stream: true,
...> ])
{:ok, %Task{}}

iex> Ollama.chat(client, [
...>   model: "llama2",
...>   messages: messages,
...>   stream: true,
...> ])
{:ok, %Task{}}
```

Messages will be sent in the following format, allowing the receiving process to pattern match against the pid of the async task if known:

```elixir
{request_pid, {:data, data}}
```

The data is a map from the Ollama JSON message. See [Ollama API docs](https://github.com/ollama/ollama/blob/main/docs/api.md).

You could manually create a `receive` block to handle messages.

```elixir
receive do
  {^current_message_pid, {:data, %{"done" => true} = data}} ->
    # handle last message
  {^current_message_pid, {:data, data}} ->
    # handle message
  {_pid, _data_} ->
    # this message was not expected!
end
```

In most cases you will probably use `c:GenServer.handle_info/2`. The following example show's how a LiveView process may by constructed to both create the streaming request and receive the streaming messages.

```elixir
defmodule Ollama.ChatLive do
  use Phoenix.LiveView

  # When the client invokes the "prompt" event, create a streaming request
  # and optionally store the request task into the assigns
  def handle_event("prompt", %{"message" => prompt}, socket) do
    client = Ollama.init()
    {:ok, task} = Ollama.completion(client, [
      model: "llama2",
      prompt: prompt,
      stream: true,
    ])

    {:noreply, assign(socket, current_request: task)}
  end

  # The request task streams messages back to the LiveView process
  def handle_info({_request_pid, {:data, _data}} = message, socket) do
    pid = socket.assigns.current_request.pid
    case message do
      {^pid, {:data, %{"done" => false} = data}} ->
        # handle each streaming chunk

      {^pid, {:data, %{"done" => true} = data}} ->
        # handle the final streaming chunk

      {_pid, _data} ->
        # this message was not expected!
    end
  end
end
```

## License

This package is open source and released under the [Apache-2 License](https://github.com/lebrunel/ollama/blob/master/LICENSE).

© Copyright 2024 [Push Code Ltd](https://www.pushcode.com/).
