defmodule A2A.Plug.Router do
  @moduledoc """
  Mountable A2A HTTP transport — both bindings, JSON-RPC and REST. Mount into
  any Plug/Phoenix pipeline:

      forward "/a2a", to: A2A.Plug.Router, init_opts: [server: MyAgent]

  Routes: `GET /.well-known/agent-card.json` (serves the configured
  `A2A.Types.AgentCard`); `POST /` (JSON-RPC 2.0; streaming methods respond as
  Server-Sent Events); and the REST routes — `POST /message:send`,
  `POST /message:stream` (SSE), `GET /tasks`, `GET /tasks/:id`,
  `GET /tasks/:id:subscribe` (SSE), `POST /tasks/:id:cancel`. All protocol
  semantics live behind `A2A.Server.RequestHandler`; this router only
  parses/renders the wire form.
  """
  use Plug.Router, copy_opts_to_assign: :init_opts

  alias A2A.Plug.{Cache, Identity, JSONRPC, REST, ServiceParams, SSE}
  alias A2A.Server.AgentCardURL

  plug(:match)
  plug(:validate_service_params)
  plug(Identity, [])
  plug(:dispatch)

  # Service parameters are validated once, before dispatch, so both bindings
  # refuse the same requests (A2A.Plug.ServiceParams). Agent-card discovery is
  # exempt: a client has to read the card to learn which versions an agent
  # speaks, so gating it on the version would be circular.
  defp validate_service_params(%Plug.Conn{path_info: [".well-known" | _]} = conn, _opts), do: conn

  defp validate_service_params(conn, _opts) do
    case ServiceParams.check(conn) do
      :ok -> conn
      {:error, error} -> conn |> render_service_error(error) |> halt()
    end
  end

  # `POST /` is the JSON-RPC binding; every other route is REST. The refusal
  # happens before the envelope is parsed, so there is no request id to echo —
  # JSON-RPC 2.0 uses a null id when it cannot be determined.
  defp render_service_error(%Plug.Conn{path_info: []} = conn, error) do
    send_json(conn, 200, %{"jsonrpc" => "2.0", "id" => nil, "error" => A2A.Error.to_jsonrpc(error)})
  end

  defp render_service_error(conn, error) do
    {status, body} = A2A.Error.to_rest(error)
    send_a2a(conn, status, body)
  end

  # The per-request server handle: the static handle with the resolved caller and
  # an owner-scoped `A2A.Scope` folded in (A2A.Server.for_request/2). Every store
  # call downstream is thereby isolated to the owner, at no per-call-site cost.
  defp request_server(conn) do
    conn.assigns.init_opts[:server]
    |> A2A.Server.handle()
    |> A2A.Server.for_request(Identity.current_user(conn))
  end

  get "/.well-known/agent-card.json" do
    server = A2A.Server.handle(conn.assigns.init_opts[:server])

    case server.agent_card do
      nil -> render_service_error(conn, no_agent_card())
      card -> send_agent_card(conn, card, server.agent_card_modified_at)
    end
  end

  # Spec §8.6.1: the card should carry cache validators, since it changes far less
  # often than clients fetch it. A conditional request that still matches gets a
  # 304 carrying those same validators (RFC 9110 §15.4.5) and no body.
  #
  # Interface URLs are resolved from the request (A2A.Server.AgentCardURL) before
  # encoding, so the ETag reflects the exact bytes served at this host/mount.
  defp send_agent_card(conn, card, modified_at) do
    body = A2A.JSON.encode!(AgentCardURL.resolve(card, conn))
    etag = Cache.etag(body)

    conn = validators(conn, etag, modified_at)

    if Cache.fresh?(conn, etag) do
      send_resp(conn, 304, "")
    else
      conn |> put_resp_content_type("application/json") |> send_resp(200, body)
    end
  end

  defp validators(conn, etag, modified_at) do
    conn = put_resp_header(conn, "etag", etag)

    case modified_at do
      %DateTime{} = at -> put_resp_header(conn, "last-modified", Cache.http_date(at))
      nil -> conn
    end
  end

  post "/" do
    server = request_server(conn)

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
    server = request_server(conn)
    {:ok, body, conn} = read_body(conn)
    render_rest(conn, REST.send_message(server, decode_body(body)))
  end

  post "/message\\:stream" do
    server = request_server(conn)
    {:ok, body, conn} = read_body(conn)

    case REST.stream_message(server, decode_body(body)) do
      {:stream, enum} -> SSE.respond(conn, nil, enum, &REST.frame/2)
      other -> render_rest(conn, other)
    end
  end

  get "/tasks" do
    server = request_server(conn)
    conn = fetch_query_params(conn)
    render_rest(conn, REST.list_tasks(server, conn.query_params))
  end

  get "/extendedAgentCard" do
    server = request_server(conn)
    render_rest(conn, REST.get_extended_agent_card(server))
  end

  post "/tasks/:task_id/pushNotificationConfigs" do
    server = request_server(conn)
    {:ok, body, conn} = read_body(conn)
    render_rest(conn, REST.set_push_config(server, task_id, decode_body(body)))
  end

  get "/tasks/:task_id/pushNotificationConfigs" do
    server = request_server(conn)
    render_rest(conn, REST.list_push_configs(server, task_id))
  end

  get "/tasks/:task_id/pushNotificationConfigs/:id" do
    server = request_server(conn)
    render_rest(conn, REST.get_push_config(server, task_id, id))
  end

  delete "/tasks/:task_id/pushNotificationConfigs/:id" do
    server = request_server(conn)
    render_rest(conn, REST.delete_push_config(server, task_id, id))
  end

  get "/tasks/:id" do
    server = request_server(conn)

    if String.ends_with?(id, ":subscribe") do
      subscribe(conn, server, String.replace_suffix(id, ":subscribe", ""))
    else
      conn = fetch_query_params(conn)
      render_rest(conn, REST.get_task(server, id, conn.query_params))
    end
  end

  post "/tasks/:id" do
    server = request_server(conn)

    cond do
      String.ends_with?(id, ":cancel") ->
        real = String.replace_suffix(id, ":cancel", "")
        {:ok, body, conn} = read_body(conn)
        render_rest(conn, REST.cancel_task(server, real, decode_body(body)))

      # Spec 11.3.2 lists `POST /tasks/{id}:subscribe`, while the vendored proto
      # annotates the same operation `get:`. The two authorities disagree, so both
      # verbs are served rather than guessing which one a client will use.
      String.ends_with?(id, ":subscribe") ->
        subscribe(conn, server, String.replace_suffix(id, ":subscribe", ""))

      true ->
        not_found(conn)
    end
  end

  match _ do
    not_found(conn)
  end

  defp subscribe(conn, server, task_id) do
    case REST.subscribe(server, task_id) do
      {:stream, enum} -> SSE.respond(conn, nil, enum, &REST.frame/2)
      other -> render_rest(conn, other)
    end
  end

  # An unrouted path is still an A2A error, and renders like one. An empty-bodied
  # 404 tells a client nothing, and reads as a transport fault rather than a
  # refusal — which is exactly how it was misdiagnosed once already.
  # The route exists; this server was simply started without a card to serve.
  defp no_agent_card do
    %A2A.Error{code: :method_not_found, message: "this agent serves no agent card"}
  end

  defp not_found(conn) do
    render_service_error(conn, %A2A.Error{
      code: :method_not_found,
      message: "no A2A route matches #{conn.method} #{conn.request_path}"
    })
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
