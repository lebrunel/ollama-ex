# Ollama

![Ollama-ex](https://raw.githubusercontent.com/lebrunel/ollama-ex/main/media/poster.webp)

![Hex.pm](https://img.shields.io/hexpm/v/ollama?color=informational)
![License](https://img.shields.io/github/license/lebrunel/ollama-ex?color=informational)
![Build Status](https://img.shields.io/github/actions/workflow/status/lebrunel/ollama-ex/elixir.yml?branch=main)

[Ollama](https://ollama.ai) is a nifty little tool for running large language models locally, and this is a nifty little library for working with Ollama in Elixir.

- 🦙 API client fully implementing the Ollama API
  - 🛜 Streaming API requests
    - Stream to an Enumerable
    - Or stream messages to any Elixir process

## Installation

The package can be installed by adding `ollama` to your list of dependencies in `mix.exs`.

```elixir
def deps do
  [
    {:ollama, "~> 0.5.1"}
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

On endpoints where streaming is supported, a streaming request can be initiated by setting the `:stream` option to `true` or a `t:pid/0`.

When `:stream` is `true` a lazy `t:Enumerable.t/0` is returned which can be used with any `Stream` functions.

```elixir
{:ok, stream} = Ollama.completion(client, [
  model: "llama2",
  prompt: "Why is the sky blue?",
  stream: true,
])

stream
|> Stream.each(& Process.send(pid, &1, [])
|> Stream.run()
# :ok
```

Because the above approach builds the `t:Enumerable.t/0` by calling `receive`, using this approach inside `GenServer` callbacks may cause the GenServer to misbehave. Instead of setting the `:stream` option to `true`, you can set it to a `t:pid/0`. A `t:Task.t/0` is returned which will send messages to the specified process.

The example below demonstrates making a streaming request in a LiveView event, and sends each of the streaming messages back to the same LiveView process.

```elixir
defmodule MyApp.ChatLive do
  use Phoenix.LiveView

  # When the client invokes the "prompt" event, create a streaming request and
  # asynchronously send messages back to self.
  def handle_event("prompt", %{"message" => prompt}, socket) do
    {:ok, task} = Ollama.completion(Ollama.init(), [
      model: "llama2",
      prompt: prompt,
      stream: self(),
    ])

    {:noreply, assign(socket, current_request: task)}
  end

  # The streaming request sends messages back to the LiveView process.
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

  # Tidy up when the request is finished
  def handle_info({ref, {:ok, %Req.Response{status: 200}}}, socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, assign(socket, current_request: nil)}
  end
end
```

Regardless of which approach to streaming you use, each of the streaming messages are a plain `t:map/0`. Refer to the [Ollama API docs](https://github.com/ollama/ollama/blob/main/docs/api.md) for the schema.

## License

This package is open source and released under the [Apache-2 License](https://github.com/lebrunel/ollama/blob/master/LICENSE).

© Copyright 2024 [Push Code Ltd](https://www.pushcode.com/).
