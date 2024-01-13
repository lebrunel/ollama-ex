defmodule Ollama.API do
  @moduledoc """
  Client module for interacting with the Ollama API.

  Currently supporting all Ollama API endpoints except pushing models (`/api/push`),
  which is coming soon.

  ## Usage

  Assuming you have Ollama running on localhost, and that you have installed a
  model, immediately trying the `completion/4` and `chat/4` functions should be very
  straightforward.

      iex> api = Ollama.API.new
      iex> Ollama.API.completion(api, "llama2", "Why is the sky blue?")
      {:ok, %{"response" => "The sky is blue because it is the color of the sky."}}
  """
  alias Ollama.Blob
  defstruct [:req]

  @typedoc "Client struct"
  @type t() :: %__MODULE__{
    req: Req.Request.t()
  }

  @typedoc "Model name, in the format `<model name>:<tag>`"
  @type model() :: String.t()

  @typedoc """
  Chat message

  A chat message is a `t:map/0` with the following fields:

  - `role` - The role of the message, either `system`, `user` or `assistant`.
  - `content` - The content of the message.
  - `images` - *(optional)* List of Base64 encoded images (for multimodal models only).
  """
  @type message() :: map()

  @typedoc "Stream handler callback function"
  @type handle_stream() :: (map() -> nil)

  @typedoc "API function response"
  @type response() :: {:ok, map() | boolean()} | {:error, term()}

  @typep req_response() :: {:ok, Req.Response.t()} | {:error, term()}

  @doc """
  Creates a new API client with the provided URL. If no URL is given, it
  defaults to `"http://localhost:11434/api"`.

  ## Examples

      iex> api = Ollama.API.new("https://ollama.service.ai:11434")
      %Ollama.API{}
  """
  @spec new(Req.url() | module() | fun()) :: t()
  def new(url \\ "http://localhost:11434/api")

  def new(url) when is_binary(url),
    do: struct(__MODULE__, req: Req.new(base_url: url))

  def new(%URI{} = url),
    do: struct(__MODULE__, req: Req.new(base_url: url))

  @doc false
  @spec mock(module() | fun()) :: t()
  def mock(plug) when is_atom(plug) or is_function(plug, 1),
    do: struct(__MODULE__, req: Req.new(plug: plug))

  @doc """
  Generates a completion for the given prompt using the specified model.
  Optionally streamable.

  ## Options

  The following options are accepted:

  - `:images` - A list of Base64 encoded images to be included with the prompt (for multimodal models only).
  - `:options` - Additional advanced [model parameters](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values).
  - `:system` - System prompt, overriding the model default.
  - `:template` - Prompt template, overriding the model default.
  - `:context` - The context parameter returned from a previous `f:completion/4` call (enabling short conversational memory).
  - `:stream` - A callback to handle streaming response chunks.

  ## Examples

      # Passing a callback to the :stream option initiates a streaming request.
      iex> Ollama.API.completion(api, "llama2", "Why is the sky blue?", stream: fn data ->
      ...>   IO.inspect(data) # %{"response" => "The"}
      ...> end)
      {:ok, ""}

      # Without the :stream option initiates a standard request
      iex> Ollama.API.completion(api, "llama2", "Why is the sky blue?")
      {:ok, %{"response": "The sky is blue because it is the color of the sky.", ...}}
  """
  @spec completion(t(), model(), String.t(), keyword()) :: response()
  def completion(%__MODULE__{} = api, model, prompt, opts \\ [])
    when is_binary(model) and is_binary(prompt)
  do
    on_chunk = Keyword.get(opts, :stream, nil)
    params = %{"model" => model, "prompt" => prompt}
    |> put_from(opts, :images)
    |> put_from(opts, :options)
    |> put_from(opts, :system)
    |> put_from(opts, :template)
    |> put_from(opts, :context)

    req(api, :post, "/generate", json: params, into: on_chunk) |> res()
  end

  @doc """
  Generates the next message in a chat using the specified model. Optionally
  streamable.

  ## Message structure

  A list of chat messages must be passed to this request. Each message has the
  following fields:

  - `role` - The role of the message, either `system`, `user` or `assistant`.
  - `content` - The content of the message.
  - `images` - *(optional)* List of Base64 encoded images (for multimodal models only).

  ## Options

  The following options are accepted:

  - `:options` - Additional advanced [model parameters](https://github.com/jmorganca/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values)
  - `:template` - Prompt template, overriding the model default
  - `:stream` - A callback to handle streaming response chunks.

  ## Examples

      iex> messages = [
      ...>   %{role: "system", content: "You are a helpful assistant."},
      ...>   %{role: "user", content: "Why is the sky blue?"},
      ...>   %{role: "assistant", content: "Due to rayleigh scattering."},
      ...>   %{role: "user", content: "How is that different than mie scattering?"},
      ...> ]

      # Passing a callback to the :stream option initiates a streaming request.
      iex> Ollama.API.chat(api, "llama2", messages, stream: fn data ->
      ...>   IO.inspect(data) # %{"message" => %{"role" => "assistant", "content" => "Mie"}}
      ...> end)
      {:ok, ""}

      # Without the :stream option initiates a standard request
      iex> Ollama.API.chat(api, "llama2", messages)
      {:ok, %{"message" => %{
        "role" => "assistant",
        "content" => "Mie scattering affects all wavelengths similarly, while Rayleigh favors shorter ones."
      }, ...}}
  """
  @spec chat(t(), model(), list(message()), keyword()) :: response()
  def chat(%__MODULE__{} = api, model, messages, opts \\ [])
    when is_binary(model) and is_list(messages)
  do
    on_chunk = Keyword.get(opts, :stream, nil)
    params = %{"model" => model, "messages" => messages}
    |> put_from(opts, :options)
    |> put_from(opts, :template)

    req(api, :post, "/chat", json: params, into: on_chunk) |> res()
  end

  @doc """
  Creates a model using the given name and model file. Optionally
  streamable.

  Any dependent blobs reference in the modelfile, such as `FROM` and `ADAPTER`
  instructions, must exist first. See `check_blob/2` and `create_blob/2`.

  ## Options

  The following options are accepted:

  - `:stream` - A callback to handle streaming response chunks.

  ## Example

      iex> modelfile = "FROM llama2\\nSYSTEM \\"You are mario from Super Mario Bros.\\""
      iex> Ollama.API.create_model(api, "mario", modelfile, stream: fn data ->
      ...>   IO.inspect(data) # %{"status" => "reading model metadata"}
      ...> end)
      {:ok, ""}
  """
  @spec create_model(t(), model(), String.t(), keyword()) :: response()
  def create_model(%__MODULE__{} = api, model, modelfile, opts \\ [])
    when is_binary(model) and is_binary(modelfile)
  do
    on_chunk = Keyword.get(opts, :stream, nil)
    params = %{"name" => model, "modelfile" => modelfile}

    req(api, :post, "/create", json: params, into: on_chunk) |> res()
  end

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
  def list_models(%__MODULE__{} = api), do: req(api, :get, "/tags") |> res()

  @doc """
  Shows all information for a specific model.

  ## Example

      iex> Ollama.API.show_model(api, "llama2")
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
  @spec show_model(t(), model()) :: response()
  def show_model(%__MODULE__{} = api, model) when is_binary(model),
    do: req(api, :post, "/show", json: %{name: model}) |> res()

  @doc """
  Creates a model with another name from an existing model.

  ## Example

      iex> Ollama.API.copy_model(api, "llama2", "llama2-backup")
      {:ok, true}
  """
  @spec copy_model(t(), model(), model()) :: response()
  def copy_model(%__MODULE__{} = api, from, to)
    when is_binary(from) and is_binary(to),
  do: req(api, :post, "/copy", json: %{source: from, destination: to}) |> res_bool()

  @doc """
  Deletes a model and its data.

  ## Example

      iex> Ollama.API.delete_model(api, "llama2")
      {:ok, true}
  """
  @spec delete_model(t(), model()) :: response()
  def delete_model(%__MODULE__{} = api, model) when is_binary(model),
    do: req(api, :delete, "/delete", json: %{name: model}) |> res_bool()

  @doc """
  Downloads a model from the ollama library. Optionally streamable.

  ## Options

  The following options are accepted:

  - `:stream` - A callback to handle streaming response chunks.

  ## Example

      iex> Ollama.API.pull_model(api, "llama2", stream: fn data ->
      ...>   IO.inspect(data) # %{"status" => "pulling manifest"}
      ...> end)
      {:ok, ""}
  """
  @spec pull_model(t(), model(), keyword()) :: response()
  def pull_model(%__MODULE__{} = api, model, opts \\ []) when is_binary(model) do
    params = %{"name" => model}
    on_chunk = Keyword.get(opts, :stream, nil)
    req(api, :post, "/pull", json: params, into: on_chunk) |> res()
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

      iex> Ollama.API.create_blob(api, modelfile)
      {:ok, true}
  """
  @spec create_blob(t(), binary()) :: response()
  def create_blob(%__MODULE__{} = api, blob) when is_binary(blob),
    do: req(api, :post, "/blobs/#{Blob.digest(blob)}", body: blob) |> res_bool()

  @doc """
  Generate embeddings from a model for the given prompt.

  ## Example

      iex> Ollama.API.embeddings(api, "llama2", "Here is an article about llamas...")
      {:ok, %{"embedding" => [
        0.5670403838157654, 0.009260174818336964, 0.23178744316101074, -0.2916173040866852, -0.8924556970596313,
        0.8785552978515625, -0.34576427936553955, 0.5742510557174683, -0.04222835972905159, -0.137906014919281
      ]}}
  """
  @spec embeddings(t(), model(), String.t(), keyword()) :: response()
  def embeddings(%__MODULE__{} = api, model, prompt, opts \\ [])
    when is_binary(model) and is_binary(prompt)
  do
    params = %{"model" => model, "prompt" => prompt}
    |> put_from(opts, :options)

    req(api, :post, "/embeddings", json: params) |> res()
  end

  # Builds the request from the given params
  @spec req(t(), atom(), Req.url(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  defp req(%__MODULE__{} = api, method, url, opts \\ []) when method in [:get, :post, :delete, :head] do
    opts = Keyword.merge(opts, method: method, url: url)
    cond do
      Keyword.get(opts, :into) |> is_function(1) ->
        Req.request(api.req, Keyword.update!(opts, :into, &stream_to/1))
      Keyword.get(opts, :json) |> is_map() ->
        Req.request(api.req, Keyword.update!(opts, :json, & Map.put(&1, "stream", false)))
      true ->
        Req.request(api.req, opts)
    end
  end

  # Normalizes the response returned from the request
  @spec res(req_response()) :: response()
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
  @spec stream_to(handle_stream()) :: fun()
  defp stream_to(cb) do
    fn {:data, data}, {req, resp} ->
      case Jason.decode(data) do
        {:ok, data} -> cb.(data)
        {:error, _} -> cb.(data)
      end
      {:cont, {req, resp}}
    end
  end

  # Puts a key and value from the given options into the params map
  @spec put_from(map(), keyword(), atom()) :: map()
  defp put_from(params, opts, key) do
    case Keyword.has_key?(opts, key) do
      true -> Map.put(params, Atom.to_string(key), Keyword.get(opts, key))
      false -> params
    end
  end

end
