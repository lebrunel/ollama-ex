defmodule Ollama.HTTPError do
  @moduledoc false
  defexception [:status, :message]

  @impl true
  def exception(status) do
    struct(__MODULE__, [
      status: status,
      message: Plug.Conn.Status.reason_phrase(status),
    ])
  end
end
