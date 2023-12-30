defmodule OllamaTest do
  use ExUnit.Case
  doctest Ollama

  test "greets the world" do
    assert Ollama.hello() == :world
  end
end
