defmodule Ollama.Schemas do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :__schemas, accumulate: true)
      import Ollama.Schemas
    end
  end

  @doc """
  Returns documentation for the given schema.
  """
  @spec doc(atom()) :: Macro.t()
  defmacro doc(key) do
    quote do
      @__schemas
      |> Keyword.get(unquote(key))
      |> NimbleOptions.docs()
      |> String.replace("\n\n", "\n")
    end
  end

  @doc """
  Registers a schema using the specified key and options.
  """
  @spec schema(atom(), NimbleOptions.schema()) :: Macro.t()
  defmacro schema(key, opts) do
    quote do
      @__schemas {unquote(key), NimbleOptions.new!(unquote(opts))}
    end
  end

  @doc """
  Fetchs a schema by the given key.
  """
  @spec schema(atom()) :: Macro.t()
  defmacro schema(key) do
    quote do
      Keyword.fetch!(@__schemas, unquote(key))
    end
  end

end
