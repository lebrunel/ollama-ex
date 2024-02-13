defmodule Ollama.API do
  @moduledoc """
  > #### API change {: .warning}
  >
  > The `Ollama.API` module has been deprecated in favour of the top level
  `Ollama` module. Apologies for the namespace change. `Ollama.API` will be
  removed in version 1.
  """

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate new(url), to: Ollama, as: :init

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate chat(client, params), to: Ollama

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate completion(client, params), to: Ollama

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate create_model(client, params), to: Ollama

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate list_models(client), to: Ollama

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate show_model(client, params), to: Ollama

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate copy_model(client, params), to: Ollama

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate delete_model(client, params), to: Ollama

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate pull_model(client, params), to: Ollama

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate push_model(client, params), to: Ollama

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate check_blob(client, blob), to: Ollama

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate create_blob(client, blob), to: Ollama

  @deprecated "Prefer top-level `Ollama` module."
  defdelegate embeddings(client, params), to: Ollama

end
