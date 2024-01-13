defmodule Ollama.Blob do
  @moduledoc """
  Module for working for blobs in Ollama.

  Currently this module only provides a function for generating a SHA256 digest
  of a binary blob.
  """

  @typedoc """
  Blob digest

  The digest is a hex-encoded SHA256 hash of the binary blob, prefixed with the
  algorithm.

  ## Example

      "sha256:054edec1d0211f624fed0cbca9d4f9400b0e491c43742af2c5b0abebf0c990d8"
  """
  @type digest() :: String.t()

  @doc """
  Generates a SHA256 digest of a binary blob.

  ## Example

      iex> Ollama.Blob.digest("hello")
      "sha256:2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
  """
  @spec digest(binary()) :: digest()
  def digest(blob) when is_binary(blob) do
    digest = :crypto.hash(:sha256, blob) |> Base.encode16(case: :lower)
    "sha256:" <> digest
  end

end
