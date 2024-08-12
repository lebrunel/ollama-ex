defmodule OllamaTest do
  use ExUnit.Case, async: true
  alias Ollama.HTTPError

  setup_all do
    {:ok, pid} = Bandit.start_link(plug: Ollama.MockServer)
    on_exit(fn -> Process.exit(pid, :normal) end)
    {:ok, client: Ollama.init("http://localhost:4000")}
  end

  describe "init/2" do
    test "default client" do
      client = Ollama.init()
      assert "http://localhost:11434/api" = client.req.options.base_url
      assert %{"user-agent" => _val} = client.req.headers
    end

    test "client with custom base url" do
      client = Ollama.init("https://ollama.my.site/api")
      assert "https://ollama.my.site/api" = client.req.options.base_url
    end

    test "client with custom req opts" do
      client = Ollama.init(receive_timeout: :infinity)
      assert "http://localhost:11434/api" = client.req.options.base_url
      assert :infinity = client.req.options.receive_timeout
    end

    test "client with custom req struct" do
      client = Ollama.init(Req.new(base_url: "https://ollama.my.site/api"))
      assert "https://ollama.my.site/api" = client.req.options.base_url
    end

    test "client with merged headers" do
      client = Ollama.init(headers: [
        {"User-Agent", "testing"},
        {"X-Test", "testing"},
      ])
      assert "http://localhost:11434/api" = client.req.options.base_url
      assert %{"user-agent" => ["testing"], "x-test" => ["testing"]} = client.req.headers
    end
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

  describe "list_running/1" do
    test "lists models that are running", %{client: client} do
      assert {:ok, %{"models" => models}} = Ollama.list_running(client)
      assert is_list(models)
      for model <- models do
        assert is_binary(model["name"])
        assert is_binary(model["digest"])
        assert is_number(model["size"])
        assert is_number(model["size_vram"])
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

  describe "embed/1" do
    test "generates an embedding for a given input", %{client: client} do
      assert {:ok, res} = Ollama.embed(client, [
        model: "nomic-embed-text",
        input: "Why is the sky blue?",
      ])

      assert res["model"] == "nomic-embed-text"
      assert is_list(res["embeddings"])
      assert length(res["embeddings"]) == 1
      assert Enum.all?(res["embeddings"], &is_list/1)
    end

    test "generates an embedding for a list of input texts", %{client: client} do
      assert {:ok, res} = Ollama.embed(client, [
        model: "nomic-embed-text",
        input: ["Why is the sky blue?", "Why is the grass green?"],
      ])

      assert res["model"] == "nomic-embed-text"
      assert is_list(res["embeddings"])
      assert length(res["embeddings"]) == 2
      assert Enum.all?(res["embeddings"], &is_list/1)
    end

    test "returns error when model not found", %{client: client} do
      assert {:error, %HTTPError{status: 404}} = Ollama.embed(client, [
        model: "not-found",
        input: "Why is the sky blue?",
      ])
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

  describe "streaming" do
    test "with stream: true, returns a lazy enumerable", %{client: client} do
      assert {:ok, stream} = Ollama.chat(client, [
        model: "llama2",
        messages: [
          %{role: "user", content: "Why is the sky blue?"}
        ],
        stream: true,
      ])

      assert is_function(stream, 2)
      assert Enum.to_list(stream) |> length() == 3
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
      assert {:ok, %{"message" => %{"content" => _}}} = Task.await(task)
      assert Ollama.StreamCatcher.get_state(pid) |> length() == 3
      GenServer.stop(pid)
    end
  end

  describe "using tools" do
    test "function calling roundtrip", %{client: client} do
      prompt = %{role: "user", content: "What is the current stock price for Apple?"}
      tools = [
        %{type: "function", function: %{
          name: "get_stock_price",
          description: "Fetches the live stock price for the given ticker.",
          parameters: %{
            type: "object",
            properties: %{
              ticker: %{
                type: "string",
                description: "The stock ticker to fetch the price of."
              }
            },
            required: ["ticker"],
          }
        }}
      ]
      # Initial prompt
      assert {:ok, res} = Ollama.chat(client, [
        model: "mistral-nemo",
        messages: [prompt],
        tools: tools,
      ])
      tool_calls = get_in(res, ["message", "tool_calls"])
      assert is_list(tool_calls)
      assert get_in(hd(tool_calls), ["function", "name"]) == "get_stock_price"
      assert get_in(hd(tool_calls), ["function", "arguments", "ticker"]) == "AAPL"

      messages = [
        prompt,
        %{role: "assistant", content: "", tool_calls: tool_calls},
        %{role: "tool", content: "$1568.12"}
      ]

      # Tool result prompt
      assert {:ok, res} = Ollama.chat(client, [
        model: "mistral-nemo",
        messages: messages,
        tools: tools,
      ])
      assert get_in(res, ["message", "content"]) == "The current stock price for Apple (AAPL) is approximately $1568.12."
    end
  end

end
