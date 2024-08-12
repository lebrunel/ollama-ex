defmodule Ollama.MockServer do
  use Plug.Router

  @mocks %{
    completion: """
    {
      "model": "llama2",
      "created_at": "2023-08-04T19:22:45.499127Z",
      "response": "The sky is blue because it is the color of the sky.",
      "done": true,
      "context": [1, 2, 3],
      "total_duration": 5043500667,
      "load_duration": 5025959,
      "prompt_eval_count": 26,
      "prompt_eval_duration": 325953000,
      "eval_count": 290,
      "eval_duration": 4709213000
    }
    """,

    chat: """
    {
      "model": "llama2",
      "created_at": "2023-12-12T14:13:43.416799Z",
      "message": {
        "role": "assistant",
        "content": "Hello! How are you today?"
      },
      "done": true,
      "total_duration": 5191566416,
      "load_duration": 2154458,
      "prompt_eval_count": 26,
      "prompt_eval_duration": 383809000,
      "eval_count": 298,
      "eval_duration": 4799921000
    }
    """,

    tool_call: """
    {
      "created_at": "2024-07-26T19:52:04.834647Z",
      "done": true,
      "done_reason": "stop",
      "eval_count": 21,
      "eval_duration": 1687556000,
      "load_duration": 28443959,
      "message": {
        "content": "",
        "role": "assistant",
        "tool_calls": [
          {
            "function": {
              "name": "get_stock_price",
              "arguments": {"ticker": "AAPL"}
            }
          }
        ]
      },
      "model": "mistral-nemo",
      "prompt_eval_count": 80,
      "prompt_eval_duration": 4916899000,
      "total_duration": 6637880709
    }
    """,

    tool_result: """
    {
      "created_at": "2024-07-26T19:52:07.337375Z",
      "done": true,
      "done_reason": "stop",
      "eval_count": 23,
      "eval_duration": 1877537000,
      "load_duration": 25199584,
      "message": {
        "content": "The current stock price for Apple (AAPL) is approximately $1568.12.",
        "role": "assistant"
      },
      "model": "mistral-nemo",
      "prompt_eval_count": 50,
      "prompt_eval_duration": 567447000,
      "total_duration": 2483884417
    }
    """,

    create_model: """
    {
      "status": "success"
    }
    """,

    show_model: """
    {
      "modelfile": "...",
      "parameters": "...",
      "template": "...",
      "details": {
        "format": "gguf",
        "family": "llama",
        "families": ["llama", "clip"],
        "parameter_size": "7B",
        "quantization_level": "Q4_0"
      }
    }
    """,

    list_models: """
    {
      "models": [
        {
          "name": "codellama:13b",
          "modified_at": "2023-11-04T14:56:49.277302595-07:00",
          "size": 7365960935,
          "digest": "9f438cb9cd581fc025612d27f7c1a6669ff83a8bb0ed86c94fcf4c5440555697",
          "details": {
            "format": "gguf",
            "family": "llama",
            "families": null,
            "parameter_size": "13B",
            "quantization_level": "Q4_0"
          }
        },
        {
          "name": "llama2:latest",
          "modified_at": "2023-12-07T09:32:18.757212583-08:00",
          "size": 3825819519,
          "digest": "fe938a131f40e6f6d40083c9f0f430a515233eb2edaa6d72eb85c50d64f2300e",
          "details": {
            "format": "gguf",
            "family": "llama",
            "families": null,
            "parameter_size": "7B",
            "quantization_level": "Q4_0"
          }
        }
      ]
    }
    """,

    list_running: """
    {
      "models": [
        {
          "details": {
            "families": ["nomic-bert"],
            "family": "nomic-bert",
            "format": "gguf",
            "parameter_size": "137M",
            "parent_model": "",
            "quantization_level": "F16"
          },
          "digest": "0a109f422b47e3a30ba2b10eca18548e944e8a23073ee3f3e947efcf3c45e59f",
          "expires_at": "2024-05-19T16:16:01.281389+01:00",
          "model": "nomic-embed-text:latest",
          "modified_at": "0001-01-01T00:00:00Z",
          "name": "nomic-embed-text:latest",
          "size": 904776704,
          "size_vram": 904776704
        }
      ]
    }
    """,

    pull_model: """
    {
      "status": "success"
    }
    """,

    push_model: """
    {
      "status": "success"
    }
    """,

    # truncated for simplicity
    embed_one: """
    {
      "embeddings": [
        [
          0.009724553, 0.04449892, -0.14063916, 0.0013168337, 0.032128844,
          0.10730086, -0.008447222, 0.010106917, 5.2289694e-4, -0.03554127
        ]
      ],
      "load_duration": 1881917,
      "model": "nomic-embed-text",
      "prompt_eval_count": 8,
      "total_duration": 48675959
    }
    """,

    # truncated for simplicity
    embed_many: """
    {
      "embeddings": [
        [
          0.009724553, 0.04449892, -0.14063916, 0.0013168337, 0.032128844,
          0.10730086, -0.008447222, 0.010106917, 5.2289694e-4, -0.03554127
        ],
        [
          0.028196355, 0.043162502, -0.18592504, 0.035034444, 0.055619627,
          0.12082449, -0.0090096295, 0.047170386, -0.032078084, 0.0047163847
        ]
      ],
      "load_duration": 1902709,
      "model": "nomic-embed-text",
      "prompt_eval_count": 16,
      "total_duration": 53473292
    }
    """,

    embeddings: """
    {
      "embedding": [
        0.5670403838157654, 0.009260174818336964, 0.23178744316101074, -0.2916173040866852, -0.8924556970596313,
        0.8785552978515625, -0.34576427936553955, 0.5742510557174683, -0.04222835972905159, -0.137906014919281
      ]
    }
    """
  }

  @stream_mocks %{
    completion: [
      """
      {
        "model": "llama2",
        "created_at": "2023-08-04T08:52:19.385406455-07:00",
        "response": "The",
        "done": false
      }
      """,
      """
      {
        "model": "llama2",
        "created_at": "2023-08-04T08:52:20.385406455-07:00",
        "response": " sky is",
        "done": false
      }
      """,
      """
      {
        "model": "llama2",
        "created_at": "2023-08-04T19:22:45.499127Z",
        "response": "",
        "done": true,
        "context": [1, 2, 3],
        "total_duration": 10706818083,
        "load_duration": 6338219291,
        "prompt_eval_count": 26,
        "prompt_eval_duration": 130079000,
        "eval_count": 259,
        "eval_duration": 4232710000
      }
      """
    ],

    chat: [
      """
      {
        "model": "llama2",
        "created_at": "2023-08-04T08:52:19.385406455-07:00",
        "message": {
          "role": "assistant",
          "content": "The",
          "images": null
        },
        "done": false
      }
      """,
      """
      {
        "model": "llama2",
        "created_at": "2023-08-04T08:52:20.385406455-07:00",
        "message": {
          "role": "assistant",
          "content": " sky is",
          "images": null
        },
        "done": false
      }
      """,
      """
      {
        "model": "llama2",
        "created_at": "2023-08-04T19:22:45.499127Z",
        "done": true,
        "total_duration": 4883583458,
        "load_duration": 1334875,
        "prompt_eval_count": 26,
        "prompt_eval_duration": 342546000,
        "eval_count": 282,
        "eval_duration": 4535599000
      }
      """
    ],

    create_model: [
      ~s({"status": "reading model metadata"}),
      ~s({"status": "creating system layer"}),
      ~s({"status": "using already created layer sha256:22f7f8ef5f4c791c1b03d7eb414399294764d7cc82c7e94aa81a1feb80a983a2"}),
      ~s({"status": "using already created layer sha256:8c17c2ebb0ea011be9981cc3922db8ca8fa61e828c5d3f44cb6ae342bf80460b"}),
      ~s({"status": "using already created layer sha256:7c23fb36d80141c4ab8cdbb61ee4790102ebd2bf7aeff414453177d4f2110e5d"}),
      ~s({"status": "using already created layer sha256:2e0493f67d0c8c9c68a8aeacdf6a38a2151cb3c4c1d42accf296e19810527988"}),
      ~s({"status": "using already created layer sha256:2759286baa875dc22de5394b4a925701b1896a7e3f8e53275c36f75a877a82c9"}),
      ~s({"status": "writing layer sha256:df30045fe90f0d750db82a058109cecd6d4de9c90a3d75b19c09e5f64580bb42"}),
      ~s({"status": "writing layer sha256:f18a68eb09bf925bb1b669490407c1b1251c5db98dc4d3d81f3088498ea55690"}),
      ~s({"status": "writing manifest"}),
      ~s({"status": "success"}),
    ],

    pull_model: [
      ~s({"status": "pulling manifest"}),
      """
      {
        "status": "downloading digestname",
        "digest": "digestname",
        "total": 2142590208,
        "completed": 241970
      }
      """,
      ~s({"status": "verifying sha256 digest"}),
      ~s({"status": "writing manifest"}),
      ~s({"status": "removing any unused layers"}),
      ~s({"status": "success"}),
    ],

    push_model: [
      ~s({ "status": "retrieving manifest" }),
      """
      {
        "status": "starting upload",
        "digest": "sha256:bc07c81de745696fdf5afca05e065818a8149fb0c77266fb584d9b2cba3711ab",
        "total": 1928429856
      }
      """,
      ~s({"status":"pushing manifest"}),
      ~s({"status": "success"}),
    ]
  }

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  post "/chat", do: handle_request(conn, :chat)
  post "/generate", do: handle_request(conn, :completion)
  post "/create", do: handle_request(conn, :create_model)
  get "/tags", do: handle_request(conn, :list_models)
  get "/ps", do: handle_request(conn, :list_running)
  post "/show", do: handle_request(conn, :show_model)

  post "/copy" do
    case conn.body_params do
      %{"source" => "llama2"} -> respond(conn, 200)
      %{"source" => "not-found"} -> respond(conn, 404)
    end
  end

  delete "/delete" do
    case conn.body_params do
      %{"name" => "llama2"} -> respond(conn, 200)
      %{"name" => "not-found"} -> respond(conn, 404)
    end
  end

  post "/pull", do: handle_request(conn, :pull_model)
  post "/push", do: handle_request(conn, :push_model)

  head "/blobs/:digest" do
    case conn.params["digest"] do
      "sha256:cd58120326971c71c0590f6b7084a0744e287ce9c67275d8b4bf34a5947d950b" -> respond(conn, 200)
      _ -> respond(conn, 404)
    end
  end

  post "/blobs/:digest", do: respond(conn, 200)
  post "/embeddings", do: handle_request(conn, :embeddings)

  post "/embed" do
    case conn.body_params do
      %{"model" => "not-found"} -> respond(conn, 404)
      %{"input" => input} when is_binary(input) -> respond(conn, :embed_one)
      %{"input" => input} when is_list(input) > 1 -> respond(conn, :embed_many)
    end
  end

  defp handle_request(conn, name) do
    case conn.body_params do
      %{"model" => "not-found"} -> respond(conn, 404)
      %{"name" => "not-found"} -> respond(conn, 404)
      %{"model" => "mistral-nemo", "messages" => messages} when length(messages) == 1 ->
        respond(conn, :tool_call)
      %{"model" => "mistral-nemo", "messages" => messages} when length(messages) > 1 ->
        respond(conn, :tool_result)
      %{"stream" => true} -> stream(conn, name)
      _ -> respond(conn, name)
    end
  end

  defp respond(conn, name) when is_atom(name) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(200, @mocks[name])
  end

  defp respond(conn, status) when is_number(status) do
    send_resp(conn, status, "")
  end

  defp stream(conn, name) do
    Enum.reduce(@stream_mocks[name], send_chunked(conn, 200), fn chunk, conn ->
      {:ok, conn} = chunk(conn, chunk)
      conn
    end)
  end

end
