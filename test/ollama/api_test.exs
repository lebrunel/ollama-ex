defmodule Ollama.APITest do
  use ExUnit.Case
  alias Ollama.Mock

  describe "completion/4" do
    test "generates a response for a given prompt" do
      mock = Ollama.API.mock(& Mock.respond(&1, :completion))
      assert {:ok, res} = Ollama.API.completion(mock, [
        model: "llama2",
        prompt: "Why is the sky blue?",
      ])
      assert res["done"]
      assert res["model"] == "llama2"
      assert is_binary(res["response"])
    end

    test "streams a response for a given prompt" do
      {:ok, pid} = Agent.start_link(fn -> [] end)
      mock = Ollama.API.mock(& Mock.stream(&1, :completion))
      assert {:ok, task} = Ollama.API.completion(mock, [
        model: "llama2",
        prompt: "Why is the sky blue?",
        stream: & Agent.update(pid, fn col -> [&1 | col] end),
      ])
      Task.await(task)
      res = Agent.get(pid, fn col -> col end)
      assert is_list(res)
      assert List.last(res) |> String.match?(~r/"done": true/)
      Agent.stop(pid)
    end

    test "returns error when model not found" do
      mock = Ollama.API.mock(& Mock.respond(&1, 404))
      assert {:error, {:http_error, :not_found}} = Ollama.API.completion(mock, [
        model: "llama2",
        prompt: "Why is the sky blue?",
      ])
    end
  end

  describe "chat/4" do
    test "generates a response for a given prompt" do
      mock = Ollama.API.mock(& Mock.respond(&1, :chat))
      assert {:ok, res} = Ollama.API.chat(mock, [
        model: "llama2",
        messages: [
          %{role: "user", content: "Why is the sky blue?"}
        ],
      ])
      assert res["done"]
      assert res["model"] == "llama2"
      assert is_map(res["message"])
    end

    test "streams a response for a given prompt" do
      {:ok, pid} = Agent.start_link(fn -> [] end)
      mock = Ollama.API.mock(& Mock.stream(&1, :chat))
      assert {:ok, task} = Ollama.API.chat(mock, [
        model: "llama2",
        messages: [
          %{role: "user", content: "Why is the sky blue?"}
        ],
        stream: & Agent.update(pid, fn col -> [&1 | col] end),
      ])
      Task.await(task)
      res = Agent.get(pid, fn col -> col end)
      assert is_list(res)
      assert List.last(res) |> String.match?(~r/"done": true/)
      Agent.stop(pid)
    end

    test "returns error when model not found" do
      mock = Ollama.API.mock(& Mock.respond(&1, 404))
      assert {:error, {:http_error, :not_found}} = Ollama.API.chat(mock, [
        model: "llama2",
        messages: [
          %{role: "user", content: "Why is the sky blue?"}
        ],
      ])
    end
  end

  describe "create_model/4" do
    test "creates a model from the params" do
      modelfile = "FROM elena:latest\nSYSTEM \"You are mario from Super Mario Bros.\""
      mock = Ollama.API.mock(& Mock.respond(&1, :create_model))
      assert {:ok, res} = Ollama.API.create_model(mock, [
        name: "mario",
        modelfile: modelfile,
      ])
      assert res["status"] == "success"
    end

    test "creates a model from the params and streams the response" do
      {:ok, pid} = Agent.start_link(fn -> [] end)
      modelfile = "FROM elena:latest\nSYSTEM \"You are mario from Super Mario Bros.\""
      mock = Ollama.API.mock(& Mock.stream(&1, :create_model))
      assert {:ok, task} = Ollama.API.create_model(mock, [
        name: "mario",
        modelfile: modelfile,
        stream: & Agent.update(pid, fn col -> [&1 | col] end),
      ])
      Task.await(task)
      res = Agent.get(pid, fn col -> col end)
      assert is_list(res)
      assert List.last(res) |> String.match?(~r/"status": "success"/)
      Agent.stop(pid)
    end
  end

  describe "list_models/1" do
    test "lists models that are available" do
      mock = Ollama.API.mock(& Mock.respond(&1, :list_models))
      assert {:ok, %{"models" => models}} = Ollama.API.list_models(mock)
      assert is_list(models)
      for model <- models do
        assert is_binary(model["name"])
        assert is_binary(model["digest"])
        assert is_number(model["size"])
        assert is_map(model["details"])
      end
    end
  end

  describe "show_model/2" do
    test "shows information about a model" do
      mock = Ollama.API.mock(& Mock.respond(&1, :show_model))
      assert {:ok, model} = Ollama.API.show_model(mock, name: "llama2")
      assert is_binary(model["modelfile"])
      assert is_binary(model["parameters"])
      assert is_binary(model["template"])
      assert is_map(model["details"])
    end

    test "returns error when model not found" do
      mock = Ollama.API.mock(& Mock.respond(&1, 404))
      assert {:error, {:http_error, :not_found}} = Ollama.API.show_model(mock, name: "llama2")
    end
  end

  describe "copy_model/3" do
    test "shows true if copied" do
      mock = Ollama.API.mock(& Mock.respond(&1, 200))
      assert {:ok, true} = Ollama.API.copy_model(mock, [
        source: "llama2",
        destination: "llama2-copy",
      ])
    end

    test "shows false if model not found" do
      mock = Ollama.API.mock(& Mock.respond(&1, 404))
      assert {:ok, false} = Ollama.API.copy_model(mock, [
        source: "llama2",
        destination: "llama2-copy",
      ])
    end
  end

  describe "delete_model/2" do
    test "shows true if copied" do
      mock = Ollama.API.mock(& Mock.respond(&1, 200))
      assert {:ok, true} = Ollama.API.delete_model(mock, name: "llama2")
    end

    test "shows false if model not found" do
      mock = Ollama.API.mock(& Mock.respond(&1, 404))
      assert {:ok, false} = Ollama.API.delete_model(mock, name: "llama2")
    end
  end

  describe "pull_model/3" do
    test "pulls the given model" do
      mock = Ollama.API.mock(& Mock.respond(&1, :pull_model))
      assert {:ok, res} = Ollama.API.pull_model(mock, name: "llama2")
      assert res["status"] == "success"
    end

    test "pulls the given model and streams the response" do
      {:ok, pid} = Agent.start_link(fn -> [] end)
      mock = Ollama.API.mock(& Mock.stream(&1, :pull_model))
      assert {:ok, task} = Ollama.API.pull_model(mock, [
        name: "llama2",
        stream: & Agent.update(pid, fn col -> [&1 | col] end),
      ])
      Task.await(task)
      res = Agent.get(pid, fn col -> col end)
      assert is_list(res)
      assert List.last(res) |> String.match?(~r/"status": "success"/)
      Agent.stop(pid)
    end
  end

  describe "check_blob/2" do
    test "returns true if a digest exists" do
      mock = Ollama.API.mock(& Mock.respond(&1, 200))
      assert {:ok, true} = Ollama.API.check_blob(mock, "sha256:cd58120326971c71c0590f6b7084a0744e287ce9c67275d8b4bf34a5947d950b")
    end

    test "returns false if a digest doesn't exist" do
      mock = Ollama.API.mock(& Mock.respond(&1, 404))
      assert {:ok, false} = Ollama.API.check_blob(mock, "sha256:00000000")
    end

    test "optionally recieves a raw blob over a digest" do
      mock = Ollama.API.mock(& Mock.respond(&1, 404))
      assert {:ok, false} = Ollama.API.check_blob(mock, <<0,1,2,3>>)
    end
  end

  describe "create_blob/2" do
    test "creates a blob for the given binary data" do
      mock = Ollama.API.mock(& Mock.respond(&1, 200))
      assert {:ok, true} = Ollama.API.create_blob(mock, <<0,1,2,3>>)
    end
  end

  describe "embeddings/4" do
    test "generates an embedding for a given prompt" do
      mock = Ollama.API.mock(& Mock.respond(&1, :embeddings))
      assert {:ok, res} = Ollama.API.embeddings(mock, [
        model: "llama2",
        prompt: "Why is the sky blue?",
      ])
      assert is_list(res["embedding"])
      assert length(res["embedding"]) == 10
    end

    test "returns error when model not found" do
      mock = Ollama.API.mock(& Mock.respond(&1, 404))
      assert {:error, {:http_error, :not_found}} = Ollama.API.embeddings(mock, [
        model: "llama2",
        prompt: "Why is the sky blue?",
      ])
    end
  end

end
