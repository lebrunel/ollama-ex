defmodule Ollama do
  @version Keyword.fetch!(Mix.Project.config(), :version)
  @moduledoc """
  ![Ollama-ex](https://raw.githubusercontent.com/lebrunel/ollama-ex/main/media/poster.webp)

  ![License](https://img.shields.io/github/license/lebrunel/ollama-ex?color=informational)

  [Ollama](https://ollama.ai) is a powerful tool for running large language
  models locally or on your own infrastructure. This library provides an
  interface for working with Ollama in Elixir.

  - 🦙 Full implementation of the Ollama API
  - 🛜 Support for streaming requests (to an Enumerable or any Elixir process)
  - 🛠️ Tool use (Function calling) capability

  ## Installation

  The package can be installed by adding `ollama` to your list of dependencies
  in `mix.exs`.

  ```elixir
  def deps do
    [
      {:ollama, "#{@version}"}
    ]
  end
  ```

  ## Quickstart

  Assuming you have Ollama running on localhost, and that you have installed a
  model, use `completion/2` or `chat/2` interact with the model.

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

  Streaming is supported on certain endpoints by setting the `:stream` option to
  `true` or a `t:pid/0`.

  When `:stream` is set to `true`, a lazy `t:Enumerable.t/0` is returned, which
  can be used with any `Stream` functions.

  ```elixir
  iex> Ollama.completion(client, [
  ...>   model: "llama2",
  ...>   prompt: "Why is the sky blue?",
  ...>   stream: true,
  ...> ])
  {:ok, stream}

  iex> is_function(stream, 2)
  true

  iex> stream
  ...> |> Stream.each(& Process.send(pid, &1, [])
  ...> |> Stream.run()
  :ok
  ```

  This approach above builds the `t:Enumerable.t/0` by calling `receive`, which
  may cause issues in `GenServer` callbacks. As an alternative, you can set the
  `:stream` option to a `t:pid/0`. This returns a `t:Task.t/0` that sends
  messages to the specified process.

  The following example demonstrates a streaming request in a LiveView event,
  sending each streaming message back to the same LiveView process:

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

  Regardless of the streaming approach used, each streaming message is a plain
  `t:map/0`. For the message schema, refer to the
  [Ollama API docs](https://github.com/ollama/ollama/blob/main/docs/api.md).

  ## Function calling

  Ollama 0.3 and later versions support tool use and function calling on
  compatible models. Note that Ollama currently doesn't support tool use with
  streaming requests, so avoid setting `:stream` to `true`.

  Using tools typically involves at least two round-trip requests to the model.
  Begin by defining one or more tools using a schema similar to ChatGPT's.
  Provide clear and concise descriptions for the tool and each argument.

  ```elixir
  iex> stock_price_tool = %{
  ...>   type: "function",
  ...>   function: %{
  ...>     name: "get_stock_price",
  ...>     description: "Fetches the live stock price for the given ticker.",
  ...>     parameters: %{
  ...>       type: "object",
  ...>       properties: %{
  ...>         ticker: %{
  ...>           type: "string",
  ...>           description: "The ticker symbol of a specific stock."
  ...>         }
  ...>       },
  ...>       required: ["ticker"]
  ...>     }
  ...>   }
  ...> }
  ```

  The first round-trip involves sending a prompt in a chat with the tool
  definitions. The model should respond with a message containing a list of tool
  calls.

  ```elixir
  iex> Ollama.chat(client, [
  ...>   model: "mistral-nemo",
  ...>   messages: [
  ...>     %{role: "user", content: "What is the current stock price for Apple?"}
  ...>   ],
  ...>   tools: [stock_price_tool],
  ...> ])
  {:ok, %{"message" => %{
    "role" => "assistant",
    "content" => "",
    "tool_calls" => [
      %{"function" => %{
        "name" => "get_stock_price",
        "arguments" => %{"ticker" => "AAPL"}
      }}
    ]
  }, ...}}
  ```

  Your implementation must intercept these tool calls and execute a
  corresponding function in your codebase with the specified arguments. The next
  round-trip involves passing the function's result back to the model as a
  message with a `:role` of `"tool"`.

  ```elixir
  iex> Ollama.chat(client, [
  ...>   model: "mistral-nemo",
  ...>   messages: [
  ...>     %{role: "user", content: "What is the current stock price for Apple?"},
  ...>     %{role: "assistant", content: "", tool_calls: [%{"function" => %{"name" => "get_stock_price", "arguments" => %{"ticker" => "AAPL"}}}]},
  ...>     %{role: "tool", content: "$217.96"},
  ...>   ],
  ...>   tools: [stock_price_tool],
  ...> ])
  {:ok, %{"message" => %{
    "role" => "assistant",
    "content" => "The current stock price for Apple (AAPL) is approximately $217.96.",
  }, ...}}
  ```

  After receiving the function tool's value, the model will respond to the
  user's original prompt, incorporating the function result into its response.
  """
  use Ollama.Schemas
  alias Ollama.Blob
  defstruct [:req]

  @typedoc "Client struct"
  @type client() :: %__MODULE__{
    req: Req.Request.t()
  }


  schema :chat_message, [
    role: [
      type: {:in, ["system", "user", "assistant", "tool"]},
      required: true,
      doc: "The role of the message, either `system`, `user`, `assistant` or `tool`."
    ],
    content: [
      type: :string,
      required: true,
      doc: "The content of the message.",
    ],
    images: [
      type: {:list, :string},
      doc: "*(optional)* List of Base64 encoded images (for multimodal models only).",
    ],
    tool_calls: [
      type: {:list, {:map, :any, :any}},
      doc: "*(optional)* List of tools the model wants to use."
    ]
  ]

  @typedoc """
  Chat message

  A chat message is a `t:map/0` with the following fields:

  #{doc(:chat_message)}
  """
  @type message() :: unquote(NimbleOptions.option_typespec(schema(:chat_message)))


  schema :tool_def, [
    type: [
      type: {:in, ["function"]},
      required: true,
      doc: "Type of tool. (Currently only `\"function\"` supported)."
    ],
    function: [
      type: :map,
      keys: [
        name: [
          type: :string,
          required: true,
          doc: "The name of the function to be called.",
        ],
        description: [
          type: :string,
          doc: "A description of what the function does."
        ],
        parameters: [
          type: :map,
          required: true,
          doc: "The parameters the functions accepts.",
        ],
      ],
      required: true,
    ]
  ]

  @typedoc """
  Tool definition

  A tool definition is a `t:map/0` with the following fields:

  #{doc(:tool_def)}
  """
  @type tool() :: unquote(NimbleOptions.option_typespec(schema(:tool_def)))


  @typedoc "Client response"
  @type response() ::
    {:ok, map() | boolean() | Enumerable.t() | Task.t()} |
    {:error, term()}

  @typep req_response() ::
    {:ok, Req.Response.t() | Task.t() | Enumerable.t()} |
    {:error, term()}


  @default_req_opts [
    base_url: "http://localhost:11434/api",
    headers: [
      {"user-agent", "ollama-ex/#{@version}"}
    ],
    receive_timeout: 60_000,
  ]

  @doc """
  Creates a new Ollama API client. Accepts either a base URL for the Ollama API,
  a keyword list of options passed to `Req.new/1`, or an existing `t:Req.Request.t/0`
  struct.

  If no arguments are given, the client is initiated with the default options:

  ```elixir
  @default_req_opts [
    base_url: "http://localhost:11434/api",
    receive_timeout: 60_000,
  ]
  ```

  ## Examples

      iex> client = Ollama.init("https://ollama.service.ai:11434/api")
      %Ollama{}
  """
  @spec init(Req.url() | keyword() | Req.Request.t()) :: client()
  def init(opts \\ [])

  def init(url) when is_binary(url),
    do: struct(__MODULE__, req: init_req(base_url: url))

  def init(%URI{} = url),
    do: struct(__MODULE__, req: init_req(base_url: url))

  def init(opts) when is_list(opts),
    do: struct(__MODULE__, req: init_req(opts))

  def init(%Req.Request{} = req),
    do: struct(__MODULE__, req: req)

  @spec init_req(keyword()) :: Req.Request.t()
  defp init_req(opts) do
    {headers, opts} = Keyword.pop(opts, :headers, [])
    @default_req_opts
    |> Keyword.merge(opts)
    |> Req.new()
    |> Req.merge(headers: headers)
  end


  schema :chat, [
    model: [
      type: :string,
      required: true,
      doc: "The ollama model name.",
    ],
    messages: [
      type: {:list, {:map, schema(:chat_message).schema}},
      required: true,
      doc: "List of messages - used to keep a chat memory.",
    ],
    tools: [
      type: {:list, {:map, schema(:tool_def).schema}},
      doc: "Tools for the model to use if supported (requires `stream` to be `false`)",
    ],
    format: [
      type: :string,
      doc: "Set the expected format of the response (`json`).",
    ],
    stream: [
      type: {:or, [:boolean, :pid]},
      default: false,
      doc: "See [section on streaming](#module-streaming).",
    ],
    keep_alive: [
      type: {:or, [:integer, :string]},
      doc: "How long to keep the model loaded.",
    ],
    options: [
      type: {:map, {:or, [:atom, :string]}, :any},
      doc: "Additional advanced [model parameters](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values).",
    ],
  ]

  @doc """
  Generates the next message in a chat using the specified model. Optionally
  streamable.

  ## Options

  #{doc(:chat)}

  ## Message structure

  Each message is a map with the following fields:

  #{doc(:chat_message)}

  ## Tool definitions

  #{doc(:tool_def)}

  ## Examples

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

      # Passing true to the :stream option initiates an async streaming request.
      iex> Ollama.chat(client, [
      ...>   model: "llama2",
      ...>   messages: messages,
      ...>   stream: true,
      ...> ])
      {:ok, Ollama.Streaming{}}
  """
  @spec chat(client(), keyword()) :: response()
  def chat(%__MODULE__{} = client, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:chat)) do
      client
      |> req(:post, "/chat", json: Enum.into(params, %{}))
      |> res()
    end
  end


  schema :completion, [
    model: [
      type: :string,
      required: true,
      doc: "The ollama model name.",
    ],
    prompt: [
      type: :string,
      required: true,
      doc: "Prompt to generate a response for.",
    ],
    images: [
      type: {:list, :string},
      doc: "A list of Base64 encoded images to be included with the prompt (for multimodal models only).",
    ],
    system: [
      type: :string,
      doc: "System prompt, overriding the model default.",
    ],
    template: [
      type: :string,
      doc: "Prompt template, overriding the model default.",
    ],
    context: [
      type: {:list, {:or, [:integer, :float]}},
      doc: "The context parameter returned from a previous `f:completion/2` call (enabling short conversational memory).",
    ],
    format: [
      type: :string,
      doc: "Set the expected format of the response (`json`).",
    ],
    raw: [
      type: :boolean,
      doc: "Set `true` if specifying a fully templated prompt. (`:template` is ingored)",
    ],
    stream: [
      type: {:or, [:boolean, :pid]},
      default: false,
      doc: "See [section on streaming](#module-streaming).",
    ],
    keep_alive: [
      type: {:or, [:integer, :string]},
      doc: "How long to keep the model loaded.",
    ],
    options: [
      type: {:map, {:or, [:atom, :string]}, :any},
      doc: "Additional advanced [model parameters](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values).",
    ],
  ]

  @doc """
  Generates a completion for the given prompt using the specified model.
  Optionally streamable.

  ## Options

  #{doc(:completion)}

  ## Examples

      iex> Ollama.completion(client, [
      ...>   model: "llama2",
      ...>   prompt: "Why is the sky blue?",
      ...> ])
      {:ok, %{"response": "The sky is blue because it is the color of the sky.", ...}}

      # Passing true to the :stream option initiates an async streaming request.
      iex> Ollama.completion(client, [
      ...>   model: "llama2",
      ...>   prompt: "Why is the sky blue?",
      ...>   stream: true,
      ...> ])
      {:ok, %Ollama.Streaming{}}
  """
  @spec completion(client(), keyword()) :: response()
  def completion(%__MODULE__{} = client, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:completion)) do
      client
      |> req(:post, "/generate", json: Enum.into(params, %{}))
      |> res()
    end
  end


  schema :create_model, [
    name: [
      type: :string,
      required: true,
      doc: "Name of the model to create.",
    ],
    modelfile: [
      type: :string,
      required: true,
      doc: "Contents of the Modelfile.",
    ],
    quantize: [
      type: :string,
      doc: "Quantize f16 and f32 models when importing them.",
    ],
    stream: [
      type: {:or, [:boolean, :pid]},
      default: false,
      doc: "See [section on streaming](#module-streaming).",
    ],
  ]

  @doc """
  Creates a model using the given name and model file. Optionally
  streamable.

  Any dependent blobs reference in the modelfile, such as `FROM` and `ADAPTER`
  instructions, must exist first. See `check_blob/2` and `create_blob/2`.

  ## Options

  #{doc(:create_model)}

  ## Example

      iex> modelfile = "FROM llama2\\nSYSTEM \\"You are mario from Super Mario Bros.\\""
      iex> Ollama.create_model(client, [
      ...>   name: "mario",
      ...>   modelfile: modelfile,
      ...>   stream: true,
      ...> ])
      {:ok, Ollama.Streaming{}}
  """
  @spec create_model(client(), keyword()) :: response()
  def create_model(%__MODULE__{} = client, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:create_model)) do
      client
      |> req(:post, "/create", json: Enum.into(params, %{}))
      |> res()
    end
  end


  @doc """
  Lists all models that Ollama has available.

  ## Example

      iex> Ollama.list_models(client)
      {:ok, %{"models" => [
        %{"name" => "codellama:13b", ...},
        %{"name" => "llama2:latest", ...},
      ]}}
  """
  @spec list_models(client()) :: response()
  def list_models(%__MODULE__{} = client) do
    client
    |> req(:get, "/tags")
    |> res()
  end


  @doc """
  Lists currently running models, their memory footprint, and process details.

  ## Example

      iex> Ollama.list_running(client)
      {:ok, %{"models" => [
        %{"name" => "nomic-embed-text:latest", ...},
      ]}}
  """
  @spec list_running(client()) :: response()
  def list_running(%__MODULE__{} = client) do
    client
    |> req(:get, "/ps")
    |> res()
  end


  schema :show_model, [
    name: [
      type: :string,
      required: true,
      doc: "Name of the model to show.",
    ]
  ]

  @doc """
  Shows all information for a specific model.

  ## Options

  #{doc(:show_model)}

  ## Example

      iex> Ollama.show_model(client, name: "llama2")
      {:ok, %{
        "details" => %{
          "families" => ["llama", "clip"],
          "family" => "llama",
          "format" => "gguf",
          "parameter_size" => "7B",
          "quantization_level" => "Q4_0"
        },
        "modelfile" => "...",
        "parameters" => "...",
        "template" => "..."
      }}
  """
  @spec show_model(client(), keyword()) :: response()
  def show_model(%__MODULE__{} = client, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:show_model)) do
      client
      |> req(:post, "/show", json: Enum.into(params, %{}))
      |> res()
    end
  end

  schema :copy_model, [
    source: [
      type: :string,
      required: true,
      doc: "Name of the model to copy from.",
    ],
    destination: [
      type: :string,
      required: true,
      doc: "Name of the model to copy to.",
    ],
  ]

  @doc """
  Creates a model with another name from an existing model.

  ## Options

  #{doc(:copy_model)}

  ## Example

      iex> Ollama.copy_model(client, [
      ...>   source: "llama2",
      ...>   destination: "llama2-backup"
      ...> ])
      {:ok, true}
  """
  @spec copy_model(client(), keyword()) :: response()
  def copy_model(%__MODULE__{} = client, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:copy_model)) do
      client
      |> req(:post, "/copy", json: Enum.into(params, %{}))
      |> res_bool()
    end
  end


  schema :delete_model, [
    name: [
      type: :string,
      required: true,
      doc: "Name of the model to delete.",
    ]
  ]

  @doc """
  Deletes a model and its data.

  ## Options

  #{doc(:copy_model)}

  ## Example

      iex> Ollama.delete_model(client, name: "llama2")
      {:ok, true}
  """
  @spec delete_model(client(), keyword()) :: response()
  def delete_model(%__MODULE__{} = client, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:delete_model)) do
      client
      |> req(:delete, "/delete", json: Enum.into(params, %{}))
      |> res_bool()
    end
  end


  schema :pull_model, [
    name: [
      type: :string,
      required: true,
      doc: "Name of the model to pull.",
    ],
    stream: [
      type: {:or, [:boolean, :pid]},
      default: false,
      doc: "See [section on streaming](#module-streaming).",
    ],
  ]

  @doc """
  Downloads a model from the ollama library. Optionally streamable.

  ## Options

  #{doc(:pull_model)}

  ## Example

      iex> Ollama.pull_model(client, name: "llama2")
      {:ok, %{"status" => "success"}}

      # Passing true to the :stream option initiates an async streaming request.
      iex> Ollama.pull_model(client, name: "llama2", stream: true)
      {:ok, %Ollama.Streaming{}}
  """
  @spec pull_model(client(), keyword()) :: response()
  def pull_model(%__MODULE__{} = client, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:pull_model)) do
      client
      |> req(:post, "/pull", json: Enum.into(params, %{}))
      |> res()
    end
  end


  schema :push_model, [
    name: [
      type: :string,
      required: true,
      doc: "Name of the model to pull.",
    ],
    stream: [
      type: {:or, [:boolean, :pid]},
      default: false,
      doc: "See [section on streaming](#module-streaming).",
    ],
  ]

  @doc """
  Upload a model to a model library. Requires registering for
  [ollama.ai](https://ollama.ai) and adding a public key first. Optionally streamable.

  ## Options

  #{doc(:push_model)}

  ## Example

      iex> Ollama.push_model(client, name: "mattw/pygmalion:latest")
      {:ok, %{"status" => "success"}}

      # Passing true to the :stream option initiates an async streaming request.
      iex> Ollama.push_model(client, name: "mattw/pygmalion:latest", stream: true)
      {:ok, %Ollama.Streaming{}}
  """
  @spec push_model(client(), keyword()) :: response()
  def push_model(%__MODULE__{} = client, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:push_model)) do
      client
      |> req(:post, "/push", json: Enum.into(params, %{}))
      |> res()
    end
  end


  @doc """
  Checks a blob exists in ollama by its digest or binary data.

  ## Examples

      iex> Ollama.check_blob(client, "sha256:fe938a131f40e6f6d40083c9f0f430a515233eb2edaa6d72eb85c50d64f2300e")
      {:ok, true}

      iex> Ollama.check_blob(client, "this should not exist")
      {:ok, false}
  """
  @spec check_blob(client(), Blob.digest() | binary()) :: response()
  def check_blob(%__MODULE__{} = client, "sha256:" <> _ = digest),
    do: req(client, :head, "/blobs/#{digest}") |> res_bool()
  def check_blob(%__MODULE__{} = client, blob) when is_binary(blob),
    do: check_blob(client, Blob.digest(blob))


  @doc """
  Creates a blob from its binary data.

  ## Example

      iex> Ollama.create_blob(client, data)
      {:ok, true}
  """
  @spec create_blob(client(), binary()) :: response()
  def create_blob(%__MODULE__{} = client, blob) when is_binary(blob) do
    client
    |> req(:post, "/blobs/#{Blob.digest(blob)}", body: blob)
    |> res_bool()
  end


schema :embeddings, [
  model: [
    type: :string,
    required: true,
    doc: "The name of the model used to generate the embeddings.",
  ],
  prompt: [
    type: :string,
    required: true,
    doc: "The prompt used to generate the embedding.",
  ],
  keep_alive: [
    type: {:or, [:integer, :string]},
    doc: "How long to keep the model loaded.",
  ],
  options: [
    type: {:map, {:or, [:atom, :string]}, :any},
    doc: "Additional advanced [model parameters](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values).",
  ],
]

  @doc """
  Generate embeddings from a model for the given prompt.

  ## Options

  #{doc(:embeddings)}

  ## Example

      iex> Ollama.embeddings(client, [
      ...>   model: "llama2",
      ...>   prompt: "Here is an article about llamas..."
      ...> ])
      {:ok, %{"embedding" => [
        0.5670403838157654, 0.009260174818336964, 0.23178744316101074, -0.2916173040866852, -0.8924556970596313,
        0.8785552978515625, -0.34576427936553955, 0.5742510557174683, -0.04222835972905159, -0.137906014919281
      ]}}
  """
  @spec embeddings(client(), keyword()) :: response()
  def embeddings(%__MODULE__{} = client, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:embeddings)) do
      client
      |> req(:post, "/embeddings", json: Enum.into(params, %{}))
      |> res()
    end
  end


schema :embed, [
  model: [
    type: :string,
    required: true,
    doc: "The name of the model used to generate the embeddings.",
  ],
  input: [
    type: {:or, [:string, {:list, :string}]},
    required: true,
    doc: "The text or list of texts to generate embeddings for.",
  ],
  keep_alive: [
    type: {:or, [:integer, :string]},
    doc: "How long to keep the model loaded.",
  ],
  options: [
    type: {:map, {:or, [:atom, :string]}, :any},
    doc: "Additional advanced [model parameters](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values).",
  ],
]

  @doc """
  Generate embeddings from a model for the given input or list of inputs.

  ## Options

  #{doc(:embeddings)}

  ## Returns

    - model: string
    - embeddings: list of floats or a list of list of floats
    - total_duration: integer,
    - load_duration: integer,
    - prompt_eval_count: integer

  ## Example

      iex> Ollama.embed(client, [
      ...>   model: "nomic-embed-text",
      ...>   input: ["Here is an article about llamas...", "And an article about guanacos"]
      ...> ])
      {:ok,
        %{
          "embeddings" => [
            [0.025707057, 0.05995968, -0.18906593, -0.028224105, 0.024518937, -0.018712264, -0.05936412,
              -0.027677963, -0.02655216, -0.0055157566, 0.012669619, 0.012822967, 0.0737529, 0.0018657907,
              0.0514689, -0.044939682, -0.032578424, -0.0143272225, 0.009716135, 0.027503505, -0.08524467,
              0.0033925518, -0.008260408, -0.029071465, 0.0614533, -2.971343e-4, -0.07822173, 0.04677405,
              -0.013675912, -0.042665306, 0.077197336, -0.0069978028, -0.05529147, -0.00885516, -0.01875029,
              -0.012202057, 0.08162492, -0.001560734, 0.0104923, -0.015027088, 0.06869281, -0.004169374,
              -0.003136883, -0.0034486335, 0.032203086, -0.0067093694, ...],
            [-0.012278048, 0.08758286, -0.19281594, -9.596305e-4, 0.052421615, -0.013487989, -0.04341169,
              -0.04910143, -0.030368308, -0.053659562, 0.04601163, -0.0036999173, 0.06349225, 0.02332796,
              0.070661716, -0.0535382, -0.012952875, -0.020421932, 0.01872197, 0.074180625, -0.04329144,
              -0.009214826, 0.004547367, 0.008833901, 0.073498674, -0.009349158, -0.059823982, 0.04068651,
              -0.022621924, -0.043966107, 5.263723e-4, -0.026195815, -0.04643947, 0.027842415, -0.036027674,
              -1.2721235e-4, 0.063953005, -0.004438271, 0.010704825, -0.03306255, 0.07427176, 0.039013054,
              -0.012652882, -0.045378733, 0.015488261, ...]
          ],
          "load_duration" => 10725400,
          "model" => "nomic-embed-text:latest",
          "prompt_eval_count" => 22,
          "total_duration" => 75792700
        }}
  """
  @spec embed(client(), keyword()) :: response()
  def embed(%__MODULE__{} = client, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:embed)) do
      client
      |> req(:post, "/embed", json: Enum.into(params, %{}))
      |> res()
    end
  end


  # Builds the request from the given params
  @spec req(client(), atom(), Req.url(), keyword()) :: req_response()
  defp req(%__MODULE__{req: req}, method, url, opts \\ []) do
    opts = Keyword.merge(opts, method: method, url: url)
    stream_opt = get_in(opts, [:json, :stream])
    dest = if is_pid(stream_opt), do: stream_opt, else: self()

    cond do
      stream_opt ->
        opts =
          opts
          |> Keyword.update!(:json, & Map.put(&1, :stream, true))
          |> Keyword.put(:into, stream_handler(dest))

        task = Task.async(fn -> req |> Req.request(opts) |> res() end)

        case stream_opt do
          true -> {:ok, Stream.resource(fn -> task end, &stream_next/1, &stream_end/1)}
          _ -> {:ok, task}
        end

      Keyword.get(opts, :json) |> is_map() ->
        opts = Keyword.update!(opts, :json, & Map.put(&1, :stream, false))
        Req.request(req, opts)

      true ->
        Req.request(req, opts)
    end
  end

  # Normalizes the response returned from the request
  @spec res(req_response()) :: response()
  defp res({:ok, %Task{} = task}), do: {:ok, task}
  defp res({:ok, enum}) when is_function(enum), do: {:ok, enum}

  defp res({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp res({:ok, %{status: status}}) do
    {:error, Ollama.HTTPError.exception(status)}
  end

  defp res({:error, error}), do: {:error, error}

  # Normalizes the response returned from the request into a boolean
  @spec res_bool(req_response()) :: response()
  defp res_bool({:ok, %{status: status}}) when status in 200..299, do: {:ok, true}
  defp res_bool({:ok, _res}), do: {:ok, false}
  defp res_bool({:error, error}), do: {:error, error}

  # Returns a callback to handle streaming responses
  @spec stream_handler(pid()) :: fun()
  defp stream_handler(pid) do
    fn {:data, data}, {req, res} ->
      with {:ok, data} <- Jason.decode(data) do
        Process.send(pid, {self(), {:data, data}}, [])
        {:cont, {req, stream_merge(res, data)}}
      else
        _ -> {:cont, {req, res}}
      end
    end
  end

  # Conditionally merges streaming responses for chat and completion endpoints
  @spec stream_merge(Req.Response.t(), map()) :: Req.Response.t()
  defp stream_merge(%Req.Response{body: body} = res, %{"done" => _} = data)
    when is_map(body)
  do
    update_in(res.body, fn body ->
      Map.merge(body, data, fn
        "response", prev, next -> prev <> next
        "message", prev, next ->
          update_in(prev, ["content"], & &1 <> next["content"])
        _key, _prev, next -> next
      end)
    end)
  end

  defp stream_merge(res, data), do: put_in(res.body, data)

  # Recieve messages into a stream
  defp stream_next(%Task{pid: pid, ref: ref} = task) do
    receive do
      {^pid, {:data, data}} ->
        {[data], task}

      {^ref, {:ok, %Req.Response{status: status}}} when status in 200..299 ->
        {:halt, task}

      {^ref, {:ok, %Req.Response{status: status}}} ->
        raise Ollama.HTTPError.exception(status)

      {^ref, {:error, error}} ->
        raise error

      {:DOWN, _ref, _, _pid, _reason} ->
        {:halt, task}
    after
      30_000 -> {:halt, task}
    end
  end

  # Tidy up when the streaming request is finished
  defp stream_end(%Task{ref: ref}), do: Process.demonitor(ref, [:flush])

end
