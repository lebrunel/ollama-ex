# Ollama

![Ollama-ex](https://raw.githubusercontent.com/lebrunel/ollama-ex/main/media/poster.webp)

![Hex.pm](https://img.shields.io/hexpm/v/ollama?color=informational)
![License](https://img.shields.io/github/license/lebrunel/ollama-ex?color=informational)
![Build Status](https://img.shields.io/github/actions/workflow/status/lebrunel/ollama-ex/elixir.yml?branch=main)

[Ollama](https://ollama.ai) is a powerful tool for running large language models locally or on your own infrastructure. This library provides an interface for working with Ollama in Elixir.

- 🦙 Full implementation of the Ollama API
- 🛜 Support for streaming requests (to an Enumerable or any Elixir process)
- 🛠️ Tool use (Function calling) capability

## Installation

The package can be installed by adding `ollama` to your list of dependencies in `mix.exs`.

```elixir
def deps do
  [
    {:ollama, "~> 0.7"}
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

Streaming is supported on certain endpoints by setting the `:stream` option to `true` or a `t:pid/0`.

When `:stream` is set to `true`, a lazy `t:Enumerable.t/0` is returned, which can be used with any `Stream` functions.

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

This approach above builds the `t:Enumerable.t/0` by calling `receive`, which may cause issues in `GenServer` callbacks. As an alternative, you can set the `:stream` option to a `t:pid/0`. This returns a `t:Task.t/0` that sends messages to the specified process.

The following example demonstrates a streaming request in a LiveView event, sending each streaming message back to the same LiveView process:

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

Regardless of the streaming approach used, each streaming message is a plain `t:map/0`. For the message schema, refer to the [Ollama API docs](https://github.com/ollama/ollama/blob/main/docs/api.md).

## Function calling

Ollama 0.3 and later versions support tool use and function calling on compatible models. Note that Ollama currently doesn't support tool use with streaming requests, so avoid setting `:stream` to `true`.

Using tools typically involves at least two round-trip requests to the model. Begin by defining one or more tools using a schema similar to ChatGPT's. Provide clear and concise descriptions for the tool and each argument.

```elixir
stock_price_tool = %{
  type: "function",
  function: %{
    name: "get_stock_price",
    description: "Fetches the live stock price for the given ticker.",
    parameters: %{
      type: "object",
      properties: %{
        ticker: %{
          type: "string",
          description: "The ticker symbol of a specific stock."
        }
      },
      required: ["ticker"]
    }
  }
}
```

The first round-trip involves sending a prompt in a chat with the tool definitions. The model should respond with a message containing a list of tool calls.

```elixir
Ollama.chat(client, [
  model: "mistral-nemo",
  messages: [
    %{role: "user", content: "What is the current stock price for Apple?"}
  ],
  tools: [stock_price_tool],
])
# {:ok, %{"message" => %{
#   "role" => "assistant",
#   "content" => "",
#   "tool_calls" => [
#     %{"function" => %{
#       "name" => "get_stock_price",
#       "arguments" => %{"ticker" => "AAPL"}
#     }}
#   ]
# }, ...}}
```

Your implementation must intercept these tool calls and execute a corresponding function in your codebase with the specified arguments. The next round-trip involves passing the function's result back to the model as a message with a `:role` of `"tool"`.

```elixir
Ollama.chat(client, [
  model: "mistral-nemo",
  messages: [
    %{role: "user", content: "What is the current stock price for Apple?"},
    %{role: "assistant", content: "", tool_calls: [%{"function" => %{"name" => "get_stock_price", "arguments" => %{"ticker" => "AAPL"}}}]},
    %{role: "tool", content: "$217.96"},
  ],
  tools: [stock_price_tool],
])
# {:ok, %{"message" => %{
#   "role" => "assistant",
#   "content" => "The current stock price for Apple (AAPL) is approximately $217.96.",
# }, ...}}
```

After receiving the function tool's value, the model will respond to the user's original prompt, incorporating the function result into its response.

## License

This package is open source and released under the [Apache-2 License](https://github.com/lebrunel/ollama/blob/master/LICENSE).

© Copyright 2024 [Push Code Ltd](https://www.pushcode.com/).
