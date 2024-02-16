defmodule Ollama.StreamCatcher do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, nil)
  end

  def get_state(pid) do
    GenServer.call(pid, :state)
  end

  @impl true
  def init(_) do
    {:ok, []}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, Enum.reverse(state), state}
  end

  @impl true
  def handle_info({_from, {:data, data}}, state) do
    state = case is_binary(data) do
      false ->
        [data | state]
      true ->
        parts = String.split(data, ~r/\}\s*\{/)
        parts
        |> Enum.with_index()
        |> Enum.map(fn
          {p, i} when i == 0 -> p <> "}"
          {p, i} when i == length(parts)-1 -> "{" <> p
          {p, _} -> "{" <> p <> "}"
        end)
        |> Enum.reduce(state, & [Jason.decode!(&1) | &2])
    end
    {:noreply, state}
  end

end
