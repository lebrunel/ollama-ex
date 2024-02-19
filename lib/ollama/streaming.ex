defmodule Ollama.Streaming do
  @moduledoc """
  When an Ollama endpoint is called with the `:stream` option set to `true`, a
  `t:Ollama.Streaming.t/0` struct is returned providing a unqiue `t:reference/0`
  for the streaming request, and a lazy enumerable that generates messages as
  they are received from the streaming request.

  `Ollama.Streaming` implements the `Enumerable` protocol, so can be used
  directly with any `Stream` functions. Most of the time, you'll just want to
  asynchronously call `send_to/2`, which will run the stream and send each
  message to a process of your chosing.

  Messages are sent in the following format, allowing the receiving process
  to pattern match against the `t:reference/0` of the streaming request:

  ```elixir
  {request_ref, {:data,  :data}}
  ```

  ## Example

  A typical example is to make a streaming request as part of a LiveView event,
  and send each of the streaming messages back to the same LiveView process.

  ```elixir
  defmodule MyApp.ChatLive do
    use Phoenix.LiveView
    alias Ollama.Streaming

    # When the client invokes the "prompt" event, create a streaming request and
    # asynchronously send messages back to self.
    def handle_event("prompt", %{"message" => prompt}, socket) do
      {:ok, streamer} = Ollama.completion(Ollama.init(), [
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

    # The streaming request sends messages back to the LiveView process.
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

    # When the streaming request is finished, remove the current reference.
    def handle_async(:streaming, :ok, socket) do
      {:noreply, assign(socket, current_request: nil)}
    end
  end
  ```
  """
  defstruct [:ref, :enum]

  @typedoc "Streaming request struct"
  @type t() :: %__MODULE__{
    ref: reference(),
    enum: Enumerable.t(),
  }

  @doc false
  @spec init(fun()) :: t()
  def init(start_fun) when is_function(start_fun, 0),
    do: do_init(fn -> Task.async(start_fun) end)

  @doc false
  @spec init(module(), atom(), list()) :: t()
  def init(mod, fun, args)
    when is_atom(mod) and is_atom(fun) and is_list(args),
    do: do_init(fn -> Task.async(mod, fun, args) end)

  defp do_init(start_fn) when is_function(start_fn, 0) do
    enum = Stream.resource(
      start_fn,
      fn %Task{pid: pid, ref: ref} = task ->
        receive do
          {^pid, {:data, data}} ->
            case Jason.decode(data) do
              {:ok, data} -> {[data], task}
              {:error, _} -> {[data], task}
            end

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
      end,
      fn %Task{ref: ref} -> Process.demonitor(ref, [:flush]) end
    )
    struct(__MODULE__, ref: make_ref(), enum: enum)
  end


  @doc """
  Runs the stream and sends each message from the streaming request to the
  process associated with the given pid.

  Messages are sent in the following format, allowing the receiving process
  to pattern match against the `t:reference/0` of the streaming request:

  ```elixir
  {request_ref, {:data,  :data}}
  ```
  """
  @spec send_to(t(), pid()) :: :ok
  def send_to(%__MODULE__{ref: ref, enum: enum}, pid) when is_pid(pid) do
    enum
    |> Stream.each(& Process.send(pid, {ref, {:data, &1}}, []))
    |> Stream.run()
  end

  defimpl Enumerable do
    @compile :inline_list_funcs
    alias Ollama.Streaming, as: S
    def count(%S{enum: enum}), do: Enumerable.count(enum)
    def member?(%S{enum: enum}, val), do: Enumerable.member?(enum, val)
    def reduce(%S{enum: enum}, acc, fun), do: Enumerable.reduce(enum, acc, fun)
    def slice(%S{enum: enum}), do: Enumerable.slice(enum)
  end

end
