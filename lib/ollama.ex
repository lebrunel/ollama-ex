defmodule Ollama do
  @moduledoc """
  ![Ollama-ex](https://raw.githubusercontent.com/lebrunel/ollama-ex/main/media/poster.webp)

  ![License](https://img.shields.io/github/license/lebrunel/ollama-ex?color=informational)

  [Ollama](https://ollama.ai) is a nifty little tool for running large language
  models locally, and this is a nifty little library for working with Ollama in
  Elixir.

  - API client fully implementing the Ollama API.
  - Stream API responses to any Elixir process.

  ## Installation

  The package can be installed by adding `ollama` to your list of dependencies
  in `mix.exs`.

  ```elixir
  def deps do
    [
      {:ollama, "#{Keyword.fetch!(Mix.Project.config(), :version)}"}
    ]
  end
  ```

  ## Quickstart

  > #### API change {: .warning}
  >
  > The `Ollama.API` module has been deprecated in favour of the top level
  `Ollama` module. Apologies for the namespace change. `Ollama.API` will be
  removed in version 1.

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

  By default, all endpoints are called with streaming disabled, blocking until
  the HTTP request completes and the response body is returned. For endpoints
  where streaming is supported, the `:stream` option can be set to `true`, and
  the function returns a `t:Ollama.Streaming.t/0` struct.

  ```elixir
  iex> Ollama.completion(client, [
  ...>   model: "llama2",
  ...>   prompt: "Why is the sky blue?",
  ...>   stream: true,
  ...> ])
  {:ok, %Ollama.Streaming{}}

  iex> Ollama.chat(client, [
  ...>   model: "llama2",
  ...>   messages: messages,
  ...>   stream: true,
  ...> ])
  {:ok, %Ollama.Streaming{}}
  ```

  `Ollama.Streaming` implements the `Enumerable` protocol, so can be used
  directly with `Stream` functions. Most of the time, you'll just want to
  asynchronously call `Ollama.Streaming.send_to/2`, which will run the stream
  and send each message to a process of your chosing.

  Messages are sent in the following format, allowing the receiving process
  to pattern match against the `t:reference/0` of the streaming request:

  ```elixir
  {request_ref, {:data, data}}
  ```

  Each data chunk is a map. For its schema, Refer to the
  [Ollama API docs](https://github.com/ollama/ollama/blob/main/docs/api.md).

  A typical example is to make a streaming request as part of a LiveView event,
  and send each of the streaming messages back to the same LiveView process.

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
  """
  use Ollama.Schemas
  alias Ollama.{Blob, Streaming}
  defstruct [:req]

  @typedoc "Client struct"
  @type client() :: %__MODULE__{
    req: Req.Request.t()
  }


  schema :chat_message, [
    role: [
      type: :string,
      required: true,
      doc: "The role of the message, either `system`, `user` or `assistant`."
    ],
    content: [
      type: :string,
      required: true,
      doc: "The content of the message.",
    ],
    images: [
      type: {:list, :string},
      doc: "*(optional)* List of Base64 encoded images (for multimodal models only).",
    ]
  ]

  @typedoc """
  Chat message

  A chat message is a `t:map/0` with the following fields:

  #{doc(:chat_message)}
  """
  @type message() :: map()

  @typedoc "Client response"
  @type response() :: {:ok, Streaming.t() | map() | boolean()} | {:error, term()}

  @typep req_response() :: {:ok, Req.Response.t() | Streaming.t()} | {:error, term()}


  @default_req_opts [
    base_url: "http://localhost:11434/api",
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
    @default_req_opts
    |> Keyword.merge(opts)
    |> Req.new()
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
    template: [
      type: :string,
      doc: "Prompt template, overriding the model default.",
    ],
    format: [
      type: :string,
      doc: "Set the expected format of the response (`json`).",
    ],
    stream: [
      type: :boolean,
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
    stream: [
      type: :boolean,
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
    stream: [
      type: :boolean,
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
      type: :boolean,
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
      type: :boolean,
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


  # Builds the request from the given params
  @spec req(client(), atom(), Req.url(), keyword()) :: req_response()
  defp req(%__MODULE__{req: req}, method, url, opts \\ []) do
    opts = Keyword.merge(opts, method: method, url: url)

    cond do
      get_in(opts, [:json, :stream]) ->
        opts = opts
        |> Keyword.update!(:json, & Map.put(&1, :stream, true))
        |> Keyword.put(:into, streamer(self()))
        {:ok, Streaming.init(Req, :request, [req, opts])}

      Keyword.get(opts, :json) |> is_map() ->
        opts = Keyword.update!(opts, :json, & Map.put(&1, :stream, false))
        Req.request(req, opts)

      true ->
        Req.request(req, opts)
    end
  end

  # Normalizes the response returned from the request
  @spec res(req_response()) :: response()
  defp res({:ok, %Streaming{} = stream}), do: {:ok, stream}

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

  # TODO Returns a callback to handle streaming responses
  @spec streamer(pid) :: fun()
  defp streamer(pid) when is_pid(pid) do
    fn {:data, data}, acc ->
      Process.send(pid, {self(), {:data, data}}, [])
      {:cont, acc}
    end
  end

end
