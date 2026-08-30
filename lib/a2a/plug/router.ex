defmodule A2A.Plug.Router do
  @moduledoc """
  Mountable A2A HTTP transport (JSON-RPC binding). Mount into any Plug/Phoenix
  pipeline:

      forward "/a2a", to: A2A.Plug.Router, init_opts: [server: MyAgent]

  Routes: `GET /.well-known/agent-card.json` (serves the configured `AgentCard`)
  and `POST /` (JSON-RPC 2.0; streaming methods respond as Server-Sent Events).
  All protocol semantics live behind `A2A.Server.RequestHandler`; this router
  only parses/renders the wire form.
  """
  use Plug.Router, copy_opts_to_assign: :init_opts

  alias A2A.Plug.{JSONRPC, SSE}

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

  match _ do
    send_resp(conn, 404, "")
  end

  defp send_json(conn, status, map) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode_to_iodata!(map))
  end
end
