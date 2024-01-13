defmodule Ollama.API do
  alias Ollama.Blob
  defstruct [:req]

  @type t() :: %__MODULE__{
    req: Req.t()
  }

  @type digest() :: String.t()
  @type model() :: String.t()
  @type message() :: map()
  @type on_chunk() :: (map() -> nil)

  @type response() :: {:ok, map() | boolean()} | {:error, term()}
  @typep req_response() :: {:ok, Req.Response.t()} | {:error, term()}


  @spec new(Req.url()) :: t()
  def new(url \\ "http://localhost:11434/api") when is_binary(url) do
    req = Req.new(base_url: url)
    struct(__MODULE__, req: req)
  end

  @spec mock(module() | fun()) :: t()
  def mock(plug) do
    req = Req.new(plug: plug)
    struct(__MODULE__, req: req)
  end

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

  @spec create_model(t(), model(), String.t(), keyword()) :: response()
  def create_model(%__MODULE__{} = api, model, modelfile, opts \\ [])
    when is_binary(model) and is_binary(modelfile)
  do
    on_chunk = Keyword.get(opts, :stream, nil)
    params = %{"name" => model, "modelfile" => modelfile}

    req(api, :post, "/create", json: params, into: on_chunk) |> res()
  end

  @spec list_models(t()) :: response()
  def list_models(%__MODULE__{} = api), do: req(api, :get, "/tags") |> res()

  @spec show_model(t(), model()) :: response()
  def show_model(%__MODULE__{} = api, model) when is_binary(model),
    do: req(api, :post, "/show", json: %{name: model}) |> res()

  @spec copy_model(t(), model(), model()) :: response()
  def copy_model(%__MODULE__{} = api, from, to)
    when is_binary(from) and is_binary(to),
  do: req(api, :post, "/copy", json: %{source: from, destination: to}) |> res_bool()

  @spec delete_model(t(), model()) :: response()
  def delete_model(%__MODULE__{} = api, model) when is_binary(model),
    do: req(api, :delete, "/delete", json: %{name: model}) |> res_bool()

  @spec pull_model(t(), model(), keyword()) :: response()
  def pull_model(%__MODULE__{} = api, model, opts \\ []) when is_binary(model) do
    params = %{"name" => model}
    on_chunk = Keyword.get(opts, :stream, nil)
    req(api, :post, "/pull", json: params, into: on_chunk) |> res()
  end

  @spec check_blob(t(), Blob.digest() | binary()) :: response()
  def check_blob(%__MODULE__{} = api, "sha256:" <> _ = digest),
    do: req(api, :head, "/blobs/#{digest}") |> res_bool()
  def check_blob(%__MODULE__{} = api, blob) when is_binary(blob),
    do: check_blob(api, Blob.digest(blob))

  @spec create_blob(t(), binary()) :: response()
  def create_blob(%__MODULE__{} = api, blob) when is_binary(blob),
    do: req(api, :post, "/blobs/#{Blob.digest(blob)}", body: blob) |> res_bool()

  @spec embeddings(t(), model(), String.t(), keyword()) :: response()
  def embeddings(%__MODULE__{} = api, model, prompt, opts \\ [])
    when is_binary(model) and is_binary(prompt)
  do
    params = %{"model" => model, "prompt" => prompt}
    |> put_from(opts, :options)

    req(api, :post, "/embeddings", json: params) |> res()
  end

  ###

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

  @spec res(req_response()) :: response()
  defp res({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp res({:ok, %{status: status}}) do
    {:error, {:http_error, Plug.Conn.Status.reason_atom(status)}}
  end

  defp res({:error, error}), do: {:error, error}

  @spec res_bool(req_response()) :: response()
  defp res_bool({:ok, %{status: status}}) when status in 200..299, do: {:ok, true}
  defp res_bool({:ok, _res}), do: {:ok, false}
  defp res_bool({:error, error}), do: {:error, error}

  @spec stream_to(on_chunk()) :: fun()
  defp stream_to(cb) do
    fn {:data, data}, {req, resp} ->
      case Jason.decode(data) do
        {:ok, data} -> cb.(data)
        {:error, _} -> cb.(data)
      end
      {:cont, {req, resp}}
    end
  end

  @spec put_from(map(), keyword(), atom()) :: map()
  defp put_from(params, opts, key) do
    case Keyword.has_key?(opts, key) do
      true -> Map.put(params, Atom.to_string(key), Keyword.get(opts, key))
      false -> params
    end
  end

end
