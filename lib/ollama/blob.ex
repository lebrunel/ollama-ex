defmodule Ollama.Blob do
  @type digest() :: String.t()

  @spec digest(binary()) :: digest()
  def digest(blob) when is_binary(blob) do
    digest = :crypto.hash(:sha256, blob) |> Base.encode16(case: :lower)
    "sha256:" <> digest
  end

end
