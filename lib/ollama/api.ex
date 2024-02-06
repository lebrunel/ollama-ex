defmodule Ollama.API do
  @moduledoc """
  Client module for interacting with the Ollama API.

  Currently supporting all Ollama API endpoints except pushing models (`/api/push`),
  which is coming soon.

  ## Usage

  Assuming you have Ollama running on localhost, and that you have installed a
  model, use `completion/2` or `chat/2` interact with the model.

      iex> api = Ollama.API.new

      iex> Ollama.API.completion(api, [
      ...>   model: "llama2",
      ...>   prompt: "Why is the sky blue?",
      ...> ])
      {:ok, %{"response" => "The sky is blue because it is the color of the sky.", ...}}

      iex> Ollama.API.chat(api, [
      ...>   model: "llama2",
      ...>   messages: [
      ...>     %{role: "system", content: "You are a helpful assistant."},
      ...>     %{role: "user", content: "Why is the sky blue?"},
      ...>     %{role: "assistant", content: "Due to rayleigh scattering."},
      ...>     %{role: "user", content: "How is that different than mie scattering?"},
      ...>   ],
      ...> ])
      {:ok, %{"message" => %{
        "role" => "assistant",
        "content" => "Mie scattering affects all wavelengths similarly, while Rayleigh favors shorter ones."
      }, ...}}

  ## Streaming

  By default, all endpoints are called with streaming disabled, blocking until
  the HTTP request completes and the response body is returned. For endpoints
  where streaming is supported, the `:stream` option can be set to `true` or a
  `t:pid/0`. When streaming is enabled, the function returns a `t:Task.t/0`,
  which asynchronously sends messages back to either the calling process, or the
  process associated with the given `t:pid/0`.

  Messages will be sent in the following format, allowing the receiving process
  to pattern match against the pid of the async task if known:

      {request_pid, {:data, data}}

  The data is a map from the Ollama JSON message. See
  [Ollama API docs](https://github.com/ollama/ollama/blob/main/docs/api.md).

  The following example show's how a LiveView process may by constructed to both
  create the streaming request and receive the streaming messages.

      defmodule Ollama.ChatLive do
        use Phoenix.LiveView

        # When the client invokes the "prompt" event, create a streaming request
        # and optionally store the request task into the assigns
        def handle_event("prompt", %{"message" => prompt}, socket) do
          api = Ollama.API.new()
          {:ok, task} = Ollama.API.completion(api, [
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
  """
  use Ollama.Schemas
  alias Ollama.Blob
  defstruct [:req]

  @typedoc "Client struct"
  @type t() :: %__MODULE__{
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

  @typedoc "API function response"
  @type response() :: {:ok, Task.t() | map() | boolean()} | {:error, term()}

  @typep req_response() :: {:ok, Req.Response.t()} | {:error, term()} | Task.t()


  @doc """
  Creates a new API client with the provided URL. If no URL is given, it
  defaults to `"http://localhost:11434/api"`.

  ## Examples

      iex> api = Ollama.API.new("https://ollama.service.ai:11434")
      %Ollama.API{}
  """
  @spec new(Req.url() | Req.Request.t()) :: t()
  def new(url \\ "http://localhost:11434/api")

  def new(url) when is_binary(url),
    do: struct(__MODULE__, req: Req.new(base_url: url))

  def new(%URI{} = url),
    do: struct(__MODULE__, req: Req.new(base_url: url))

  def new(%Req.Request{} = req),
    do: struct(__MODULE__, req: req)

  @doc false
  @spec mock(module() | fun()) :: t()
  def mock(plug) when is_atom(plug) or is_function(plug, 1),
    do: new(Req.new(plug: plug))


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

  ## Examples

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

      # Passing true to the :stream option initiates an async streaming request.
      iex> Ollama.API.chat(api, [
      ...>   model: "llama2",
      ...>   messages: messages,
      ...>   stream: true,
      ...> ])
      {:ok, Task{}}
  """
  @spec chat(t(), keyword()) :: response()
  def chat(%__MODULE__{} = api, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:chat)) do
      req(api, :post, "/chat", json: Enum.into(params, %{})) |> res()
    end
  end

  @doc false
  @deprecated "Use Ollama.API.chat/2"
  @spec chat(t(), String.t(), list(message()), keyword()) :: response()
  def chat(%__MODULE__{} = api, model, messages, opts \\ [])
    when is_binary(model) and is_list(messages),
    do: chat(api, [{:model, model}, {:messages, messages} | opts])


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

      iex> Ollama.API.completion(api, [
      ...>   model: "llama2",
      ...>   prompt: "Why is the sky blue?",
      ...> ])
      {:ok, %{"response": "The sky is blue because it is the color of the sky.", ...}}

      # Passing true to the :stream option initiates an async streaming request.
      iex> Ollama.API.completion(api, [
      ...>   model: "llama2",
      ...>   prompt: "Why is the sky blue?",
      ...>   stream: true,
      ...> ])
      {:ok, %Task{}}
  """
  @spec completion(t(), keyword()) :: response()
  def completion(%__MODULE__{} = api, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:completion)) do
      req(api, :post, "/generate", json: Enum.into(params, %{})) |> res()
    end
  end

  @doc false
  @deprecated "Use Ollama.API.completion/2"
  @spec completion(t(), String.t(), String.t(), keyword()) :: response()
  def completion(%__MODULE__{} = api, model, prompt, opts \\ [])
    when is_binary(model) and is_binary(prompt),
    do: completion(api, [{:model, model}, {:prompt, prompt} | opts])


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
      iex> Ollama.API.create_model(api, [
      ...>   name: "mario",
      ...>   modelfile: modelfile,
      ...>   stream: true,
      ...> ])
      {:ok, Task{}}
  """
  @spec create_model(t(), keyword()) :: response()
  def create_model(%__MODULE__{} = api, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:create_model)) do
      req(api, :post, "/create", json: Enum.into(params, %{})) |> res()
    end
  end

  @doc false
  @deprecated "Use Ollama.API.create_model/2"
  @spec create_model(t(), String.t(), String.t(), keyword()) :: response()
  def create_model(%__MODULE__{} = api, model, modelfile, opts \\ [])
    when is_binary(model) and is_binary(modelfile),
    do: create_model(api, [{:name, model}, {:modelfile, modelfile} | opts])


  @doc """
  Lists all models that Ollama has available.

  ## Example

      iex> Ollama.API.list_models(api)
      {:ok, %{"models" => [
        %{"name" => "codellama:13b", ...},
        %{"name" => "llama2:latest", ...},
      ]}}
  """
  @spec list_models(t()) :: response()
  def list_models(%__MODULE__{} = api),
    do: req(api, :get, "/tags") |> res()


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

      iex> Ollama.API.show_model(api, name: "llama2")
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
  @spec show_model(t(), keyword()) :: response()
  def show_model(%__MODULE__{} = api, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:show_model)) do
      req(api, :post, "/show", json: Enum.into(params, %{})) |> res()
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

      iex> Ollama.API.copy_model(api, [
      ...>   source: "llama2",
      ...>   destination: "llama2-backup"
      ...> ])
      {:ok, true}
  """
  @spec copy_model(t(), keyword()) :: response()
  def copy_model(%__MODULE__{} = api, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:copy_model)) do
      req(api, :post, "/copy", json: Enum.into(params, %{})) |> res_bool()
    end
  end

  @doc false
  @deprecated "Use Ollama.API.copy_model/2"
  @spec copy_model(t(), String.t(), String.t()) :: response()
  def copy_model(%__MODULE__{} = api, from, to)
    when is_binary(from) and is_binary(to),
    do: copy_model(api, source: from, destination: to)


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

      iex> Ollama.API.delete_model(api, name: "llama2")
      {:ok, true}
  """
  @spec delete_model(t(), keyword()) :: response()
  def delete_model(%__MODULE__{} = api, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:delete_model)) do
      req(api, :delete, "/delete", json: Enum.into(params, %{})) |> res_bool()
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

      iex> Ollama.API.pull_model(api, name: "llama2")
      {:ok, %{"status" => "success"}}

      # Passing true to the :stream option initiates an async streaming request.
      iex> Ollama.API.pull_model(api, name: "llama2", stream: true)
      {:ok, %Task{}}
  """
  @spec pull_model(t(), keyword()) :: response()
  def pull_model(%__MODULE__{} = api, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:pull_model)) do
      req(api, :post, "/pull", json: Enum.into(params, %{})) |> res()
    end
  end

  def pull_model(%__MODULE__{} = api, model) when is_binary(model),
    do: pull_model(api, model, [])

  @doc false
  @deprecated "Use Ollama.API.pull_model/2"
  @spec pull_model(t(), String.t(), keyword()) :: response()
  def pull_model(%__MODULE__{} = api, model, opts) when is_binary(model),
    do: pull_model(api, [{:name, model} | opts])


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

      iex> Ollama.API.push_model(api, name: "mattw/pygmalion:latest")
      {:ok, %{"status" => "success"}}

      # Passing true to the :stream option initiates an async streaming request.
      iex> Ollama.API.push_model(api, name: "mattw/pygmalion:latest", stream: true)
      {:ok, %Task{}}
  """
  @spec push_model(t(), keyword()) :: response()
  def push_model(%__MODULE__{} = api, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:push_model)) do
      req(api, :post, "/push", json: Enum.into(params, %{})) |> res()
    end
  end


  @doc """
  Checks a blob exists in ollama by its digest or binary data.

  ## Examples

      iex> Ollama.API.check_blob(api, "sha256:fe938a131f40e6f6d40083c9f0f430a515233eb2edaa6d72eb85c50d64f2300e")
      {:ok, true}

      iex> Ollama.API.check_blob(api, "this should not exist")
      {:ok, false}
  """
  @spec check_blob(t(), Blob.digest() | binary()) :: response()
  def check_blob(%__MODULE__{} = api, "sha256:" <> _ = digest),
    do: req(api, :head, "/blobs/#{digest}") |> res_bool()
  def check_blob(%__MODULE__{} = api, blob) when is_binary(blob),
    do: check_blob(api, Blob.digest(blob))


  @doc """
  Creates a blob from its binary data.

  ## Example

      iex> Ollama.API.create_blob(api, data)
      {:ok, true}
  """
  @spec create_blob(t(), binary()) :: response()
  def create_blob(%__MODULE__{} = api, blob) when is_binary(blob),
    do: req(api, :post, "/blobs/#{Blob.digest(blob)}", body: blob) |> res_bool()


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

      iex> Ollama.API.embeddings(api, [
      ...>   model: "llama2",
      ...>   prompt: "Here is an article about llamas..."
      ...> ])
      {:ok, %{"embedding" => [
        0.5670403838157654, 0.009260174818336964, 0.23178744316101074, -0.2916173040866852, -0.8924556970596313,
        0.8785552978515625, -0.34576427936553955, 0.5742510557174683, -0.04222835972905159, -0.137906014919281
      ]}}
  """
  @spec embeddings(t(), keyword()) :: response()
  def embeddings(%__MODULE__{} = api, params) when is_list(params) do
    with {:ok, params} <- NimbleOptions.validate(params, schema(:embeddings)) do
      api
      |> req(:post, "/embeddings", json: Enum.into(params, %{}))
      |> res()
    end
  end

  @doc false
  @deprecated "Use Ollama.API.embeddings/2"
  @spec embeddings(t(), String.t(), String.t(), keyword()) :: response()
  def embeddings(%__MODULE__{} = api, model, prompt, opts \\ [])
    when is_binary(model) and is_binary(prompt),
    do: embeddings(api, [{:model, model}, {:prompt, prompt} | opts])


  # Builds the request from the given params
  @spec req(t(), atom(), Req.url(), keyword()) :: req_response()
  defp req(%__MODULE__{} = api, method, url, opts \\ []) do
    opts = Keyword.merge(opts, method: method, url: url)
    dest = case get_in(opts, [:json, :stream]) do
      true -> self()
      dest -> dest
    end

    cond do
      is_pid(dest) ->
        opts = opts
        |> Keyword.update!(:json, & Map.put(&1, :stream, true))
        |> Keyword.put(:into, stream_to(dest))

        Task.async(Req, :request, [api.req, opts])
      Keyword.get(opts, :json) |> is_map() ->
        opts = Keyword.update!(opts, :json, & Map.put(&1, :stream, false))
        Req.request(api.req, opts)
      true ->
        Req.request(api.req, opts)
    end
  end

  # Normalizes the response returned from the request
  @spec res(req_response()) :: response()
  defp res(%Task{} = task), do: {:ok, task}

  defp res({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp res({:ok, %{status: status}}) do
    {:error, {:http_error, Plug.Conn.Status.reason_atom(status)}}
  end

  defp res({:error, error}), do: {:error, error}

  # Normalizes the response returned from the request into a boolean
  @spec res_bool(req_response()) :: response()
  defp res_bool({:ok, %{status: status}}) when status in 200..299, do: {:ok, true}
  defp res_bool({:ok, _res}), do: {:ok, false}
  defp res_bool({:error, error}), do: {:error, error}

  # Returns a callback to handle streaming responses
  @spec stream_to(pid()) :: fun()
  defp stream_to(pid) do
    fn {:data, data}, acc ->
      case Jason.decode(data) do
        {:ok, data} ->
          Process.send(pid, {self(), {:data, data}}, [])

        {:error, _} ->
          Process.send(pid, {self(), {:data, data}}, [])
      end
      {:cont, acc}
    end
  end

end
