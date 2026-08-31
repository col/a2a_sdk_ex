defmodule A2A.Plug.Router do
  @moduledoc """
  Mountable A2A HTTP transport — both bindings, JSON-RPC and REST. Mount into
  any Plug/Phoenix pipeline:

      forward "/a2a", to: A2A.Plug.Router, init_opts: [server: MyAgent]

  Routes: `GET /.well-known/agent-card.json` (serves the configured `AgentCard`);
  `POST /` (JSON-RPC 2.0; streaming methods respond as Server-Sent Events); and
  the REST routes (`A2A.Plug.REST`) — `POST /message:send`,
  `POST /message:stream` (SSE), `GET /tasks`, `GET /tasks/:id`,
  `GET /tasks/:id:subscribe` (SSE), `POST /tasks/:id:cancel` — following the
  vendored proto's `google.api.http` paths. All protocol semantics live behind
  `A2A.Server.RequestHandler`; this router only parses/renders the wire form.
  """
  use Plug.Router, copy_opts_to_assign: :init_opts

  alias A2A.Plug.{JSONRPC, REST, SSE}

  plug(:match)
  plug(:dispatch)

  get "/.well-known/agent-card.json" do
    server = A2A.Server.handle(conn.assigns.init_opts[:server])

    case server.agent_card do
      nil ->
        send_resp(conn, 404, "")

      card ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, A2A.JSON.encode!(card))
    end
  end

  post "/" do
    server = A2A.Server.handle(conn.assigns.init_opts[:server])

    case read_body(conn) do
      {:ok, body, conn} ->
        case JSONRPC.decode_envelope(body) do
          {:ok, env} ->
            case JSONRPC.dispatch(server, env) do
              {:reply, envelope} -> send_json(conn, 200, envelope)
              {:error, envelope} -> send_json(conn, 200, envelope)
              {:stream, id, enum} -> SSE.respond(conn, id, enum)
            end

          {:error, envelope} ->
            send_json(conn, 200, envelope)
        end

      {:more, _partial, conn} ->
        send_json(conn, 200, %{
          "jsonrpc" => "2.0",
          "id" => nil,
          "error" => %{"code" => -32_600, "message" => "request body too large"}
        })
    end
  end

  # The colon must be escaped (`\\:`) — an unescaped `:` mid-segment is Plug.Router's
  # dynamic-param syntax (e.g. `foo:bar` binds a param named `bar`), not a literal
  # colon, so `/message:send` and `/message:stream` would otherwise both compile to
  # the same "message" + capture-rest pattern and collide.
  post "/message\\:send" do
    server = A2A.Server.handle(conn.assigns.init_opts[:server])
    {:ok, body, conn} = read_body(conn)
    render_rest(conn, REST.send_message(server, decode_body(body)))
  end

  post "/message\\:stream" do
    server = A2A.Server.handle(conn.assigns.init_opts[:server])
    {:ok, body, conn} = read_body(conn)

    case REST.stream_message(server, decode_body(body)) do
      {:stream, enum} -> SSE.respond(conn, nil, enum, &REST.frame/2)
      other -> render_rest(conn, other)
    end
  end

  get "/tasks" do
    server = A2A.Server.handle(conn.assigns.init_opts[:server])
    conn = fetch_query_params(conn)
    render_rest(conn, REST.list_tasks(server, conn.query_params))
  end

  post "/tasks/:task_id/pushNotificationConfigs" do
    server = A2A.Server.handle(conn.assigns.init_opts[:server])
    {:ok, body, conn} = read_body(conn)
    render_rest(conn, REST.set_push_config(server, task_id, decode_body(body)))
  end

  get "/tasks/:task_id/pushNotificationConfigs" do
    server = A2A.Server.handle(conn.assigns.init_opts[:server])
    render_rest(conn, REST.list_push_configs(server, task_id))
  end

  get "/tasks/:task_id/pushNotificationConfigs/:id" do
    server = A2A.Server.handle(conn.assigns.init_opts[:server])
    render_rest(conn, REST.get_push_config(server, task_id, id))
  end

  delete "/tasks/:task_id/pushNotificationConfigs/:id" do
    server = A2A.Server.handle(conn.assigns.init_opts[:server])
    render_rest(conn, REST.delete_push_config(server, task_id, id))
  end

  get "/tasks/:id" do
    server = A2A.Server.handle(conn.assigns.init_opts[:server])

    if String.ends_with?(id, ":subscribe") do
      real = String.replace_suffix(id, ":subscribe", "")

      case REST.subscribe(server, real) do
        {:stream, enum} -> SSE.respond(conn, nil, enum, &REST.frame/2)
        other -> render_rest(conn, other)
      end
    else
      render_rest(conn, REST.get_task(server, id))
    end
  end

  post "/tasks/:id" do
    server = A2A.Server.handle(conn.assigns.init_opts[:server])

    if String.ends_with?(id, ":cancel") do
      real = String.replace_suffix(id, ":cancel", "")
      {:ok, body, conn} = read_body(conn)
      render_rest(conn, REST.cancel_task(server, real, decode_body(body)))
    else
      send_resp(conn, 404, "")
    end
  end

  match _ do
    send_resp(conn, 404, "")
  end

  defp send_json(conn, status, map) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode_to_iodata!(map))
  end

  defp decode_body(""), do: %{}

  defp decode_body(body) do
    case Jason.decode(body) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp render_rest(conn, {:reply, status, map}), do: send_a2a(conn, status, map)
  defp render_rest(conn, {:error, status, body}), do: send_a2a(conn, status, body)

  defp send_a2a(conn, status, map) do
    conn
    |> put_resp_content_type(REST.content_type())
    |> send_resp(status, Jason.encode_to_iodata!(map))
  end
end
