defmodule OllamaTest do
  use ExUnit.Case, async: true
  alias Ollama.HTTPError

  setup_all do
    {:ok, pid} = Bandit.start_link(plug: Ollama.MockServer)
    on_exit(fn -> Process.exit(pid, :normal) end)
    {:ok, client: Ollama.init("http://localhost:4000")}
  end

  describe "chat2" do
    test "generates a response for a given prompt", %{client: client} do
      assert {:ok, res} = Ollama.chat(client, [
        model: "llama2",
        messages: [
          %{role: "user", content: "Why is the sky blue?"}
        ],
      ])
      assert res["done"]
      assert res["model"] == "llama2"
      assert is_map(res["message"])
    end

    test "streams a response for a given prompt", %{client: client} do
      assert {:ok, stream} = Ollama.chat(client, [
        model: "llama2",
        messages: [
          %{role: "user", content: "Why is the sky blue?"}
        ],
        stream: true,
      ])
      res = Enum.to_list(stream)
      assert is_list(res)
      assert List.last(res) |> Map.get("done")
    end

    test "returns error when model not found", %{client: client} do
      assert {:error, %HTTPError{status: 404}} = Ollama.chat(client, [
        model: "not-found",
        messages: [
          %{role: "user", content: "Why is the sky blue?"}
        ],
      ])
    end
  end

  describe "completion/2" do
    test "generates a response for a given prompt", %{client: client} do
      assert {:ok, res} = Ollama.completion(client, [
        model: "llama2",
        prompt: "Why is the sky blue?",
      ])
      assert res["done"]
      assert res["model"] == "llama2"
      assert is_binary(res["response"])
    end

    test "streams a response for a given prompt", %{client: client} do
      assert {:ok, stream} = Ollama.completion(client, [
        model: "llama",
        prompt: "Why is the sky blue?",
        stream: true,
      ])
      res = Enum.to_list(stream)
      assert is_list(res)
      assert List.last(res) |> Map.get("done")
    end

    test "returns error when model not found", %{client: client} do
      assert {:error, %HTTPError{status: 404}} = Ollama.completion(client, [
        model: "not-found",
        prompt: "Why is the sky blue?",
      ])
    end
  end

  describe "create_model2" do
    test "creates a model from the params", %{client: client} do
      modelfile = "FROM elena:latest\nSYSTEM \"You are mario from Super Mario Bros.\""
      assert {:ok, res} = Ollama.create_model(client, [
        name: "mario",
        modelfile: modelfile,
      ])
      assert res["status"] == "success"
    end

    test "creates a model from the params and streams the response", %{client: client} do
      modelfile = "FROM elena:latest\nSYSTEM \"You are mario from Super Mario Bros.\""
      assert {:ok, stream} = Ollama.create_model(client, [
        name: "mario",
        modelfile: modelfile,
        stream: true,
      ])
      res = Enum.to_list(stream)
      assert is_list(res)
      assert List.last(res) |> Map.get("status") == "success"
    end
  end

  describe "list_models/1" do
    test "lists models that are available", %{client: client} do
      assert {:ok, %{"models" => models}} = Ollama.list_models(client)
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
    test "shows information about a model", %{client: client} do
      assert {:ok, model} = Ollama.show_model(client, name: "llama2")
      assert is_binary(model["modelfile"])
      assert is_binary(model["parameters"])
      assert is_binary(model["template"])
      assert is_map(model["details"])
    end

    test "returns error when model not found", %{client: client} do
      assert {:error, %HTTPError{status: 404}} = Ollama.show_model(client, name: "not-found")
    end
  end

  describe "copy_model/2" do
    test "shows true if copied", %{client: client} do
      assert {:ok, true} = Ollama.copy_model(client, [
        source: "llama2",
        destination: "llama2-copy",
      ])
    end

    test "shows false if model not found", %{client: client} do
      assert {:ok, false} = Ollama.copy_model(client, [
        source: "not-found",
        destination: "llama2-copy",
      ])
    end
  end

  describe "delete_model/2" do
    test "shows true if copied", %{client: client} do
      assert {:ok, true} = Ollama.delete_model(client, name: "llama2")
    end

    test "shows false if model not found", %{client: client} do
      assert {:ok, false} = Ollama.delete_model(client, name: "not-found")
    end
  end

  describe "pull_model/2" do
    test "pulls the given model", %{client: client} do
      assert {:ok, res} = Ollama.pull_model(client, name: "llama2")
      assert res["status"] == "success"
    end

    test "pulls the given model and streams the response", %{client: client} do
      assert {:ok, stream} = Ollama.pull_model(client, [
        name: "llama2",
        stream: true,
      ])
      res = Enum.to_list(stream)
      assert is_list(res)
      assert List.last(res) |> Map.get("status") == "success"
    end
  end

  describe "push_model/2" do
    test "pushes the given model", %{client: client} do
      assert {:ok, res} = Ollama.push_model(client, name: "mattw/pygmalion:latest")
      assert res["status"] == "success"
    end

    test "pushes the given model and streams the response", %{client: client} do
      assert {:ok, stream} = Ollama.push_model(client, [
        name: "mattw/pygmalion:latest",
        stream: true,
      ])
      res = Enum.to_list(stream)
      assert is_list(res)
      assert List.last(res) |> Map.get("status") == "success"
    end
  end

  describe "check_blob/2" do
    test "returns true if a digest exists", %{client: client} do
      assert {:ok, true} = Ollama.check_blob(client, "sha256:cd58120326971c71c0590f6b7084a0744e287ce9c67275d8b4bf34a5947d950b")
    end

    test "returns false if a digest doesn't exist", %{client: client} do
      assert {:ok, false} = Ollama.check_blob(client, "sha256:00000000")
    end

    test "optionally receives a raw blob over a digest", %{client: client} do
      assert {:ok, false} = Ollama.check_blob(client, <<0,1,2,3>>)
    end
  end

  describe "create_blob/2" do
    test "creates a blob for the given binary data", %{client: client} do
      assert {:ok, true} = Ollama.create_blob(client, <<0,1,2,3>>)
    end
  end

  describe "embeddings/2" do
    test "generates an embedding for a given prompt", %{client: client} do
      assert {:ok, res} = Ollama.embeddings(client, [
        model: "llama2",
        prompt: "Why is the sky blue?",
      ])
      assert is_list(res["embedding"])
      assert length(res["embedding"]) == 10
    end

    test "returns error when model not found", %{client: client} do
      assert {:error, %HTTPError{status: 404}} = Ollama.embeddings(client, [
        model: "not-found",
        prompt: "Why is the sky blue?",
      ])
    end
  end

  describe "streaming methods" do
    test "with stream: true, returns a lazy enumerable", %{client: client} do
      assert {:ok, stream} = Ollama.chat(client, [
        model: "llama2",
        messages: [
          %{role: "user", content: "Why is the sky blue?"}
        ],
        stream: true,
      ])

      assert is_function(stream, 2)
      assert Enum.to_list(stream) |> length() == 2
    end

    test "with stream: pid, returns a task and sends messages to pid", %{client: client} do
      {:ok, pid} = Ollama.StreamCatcher.start_link()
      assert {:ok, task} = Ollama.chat(client, [
        model: "llama2",
        messages: [
          %{role: "user", content: "Why is the sky blue?"}
        ],
        stream: pid,
      ])

      assert match?(%Task{}, task)
      Task.await(task)
      assert Ollama.StreamCatcher.get_state(pid) |> length() == 2
      GenServer.stop(pid)
    end
  end

end
