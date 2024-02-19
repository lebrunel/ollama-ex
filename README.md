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
client = Ollama.init()

Ollama.completion(client, [
  model: "llama2",
  prompt: "Why is the sky blue?",
])
# {:ok, %{"response" => "The sky is blue because it is the color of the sky.", ...}}
```

### 2. Generate the next message in a chat

```elixir
client = Ollama.init()
messages = [
  %{role: "system", content: "You are a helpful assistant."},
  %{role: "user", content: "Why is the sky blue?"},
  %{role: "assistant", content: "Due to rayleigh scattering."},
  %{role: "user", content: "How is that different than mie scattering?"},
]

Ollama.chat(client, [
  model: "llama2",
  messages: messages,
])
# {:ok, %{"message" => %{
#   "role" => "assistant",
#   "content" => "Mie scattering affects all wavelengths similarly, while Rayleigh favors shorter ones."
# }, ...}}
```

## Streaming

When an Ollama endpoint is called with the `:stream` option set to `true`, a `t:Ollama.Streaming.t/0` struct is returned providing a unqiue `t:reference/0` for the streaming request, and a lazy enumerable that generates messages as they are received from the streaming request.

```elixir
Ollama.completion(client, [
  model: "llama2",
  prompt: "Why is the sky blue?",
  stream: true,
])
# {:ok, %Ollama.Streaming{}}

Ollama.chat(client, [
  model: "llama2",
  messages: messages,
  stream: true,
])
# {:ok, %Ollama.Streaming{}}
```

`Ollama.Streaming` implements the `Enumerable` protocol, so can be used directly with `Stream` functions. Most of the time, you'll just want to asynchronously call `Ollama.Streaming.send_to/2`, which will run the stream and send each message to a process of your chosing.

Messages are sent in the following format, allowing the receiving process to pattern match against the `t:reference/0` of the streaming request:

```elixir
{request_pid, {:data, data}}
```

Each data chunk is a map. For its schema, Refer to the [Ollama API docs](https://github.com/ollama/ollama/blob/main/docs/api.md).

A typical example is to make a streaming request as part of a LiveView event, and send each of the streaming messages back to the same LiveView process.

```elixir
defmodule MyApp.ChatLive do
  use Phoenix.LiveView
  alias Ollama.Streaming

  # When the client invokes the "prompt" event, create a streaming request and
  # asynchronously send messages back to self.
  def handle_event("prompt", %{"message" => prompt}, socket) do
    client = Ollama.init()
    {:ok, streamer} = Ollama.completion(client, [
      model: "llama2",
      prompt: prompt,
      stream: true,
    ])

    pid = self()
    {:noreply,
      socket
      |> assign(current_request: streamer.ref)
      |> start_async(:streaming, fn -> Streaming.send_to(streaming, pid) end)
    }
  end

  # The streaming request sends messages back to the LiveView process
  def handle_info({_request_ref, {:data, _data}} = message, socket) do
    ref = socket.assigns.current_request
    case message do
      {^ref, {:data, %{"done" => false} = data}} ->
        # handle each streaming chunk

      {^ref, {:data, %{"done" => true} = data}} ->
        # handle the final streaming chunk

      {_ref, _data} ->
        # this message was not expected!
    end
  end

  # The streaming request is finished
  def handle_async(:streaming, :ok, socket) do
    {:noreply, assign(socket, current_request: nil)}
  end
end
```

## License

This package is open source and released under the [Apache-2 License](https://github.com/lebrunel/ollama/blob/master/LICENSE).

© Copyright 2024 [Push Code Ltd](https://www.pushcode.com/).
