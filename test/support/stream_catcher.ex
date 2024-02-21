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
    {:noreply, [data | state]}
  end

end
