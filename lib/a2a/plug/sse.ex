defmodule A2A.Plug.SSE do
  @moduledoc """
  Streams a lazy enumerable of `%A2A.Types.StreamResponse{}` frames as
  Server-Sent Events. The enumerable was produced (and its PubSub subscription
  opened) by the handler in THIS request process, so it is enumerated here.

  Peek-first: the first frame is pulled *before* headers are sent, so an early
  error surfaces as a normal JSON-RPC error envelope rather than a `200` stream
  that immediately fails. Once the first frame is in hand, headers go out and
  every frame (including the peeked one) is chunked as `data: <envelope>\\n\\n`.
  A client disconnect surfaces as a `chunk/2` error, which stops iteration and
  returns the (abandoned) `conn` without resuming the suspended continuation.
  The PubSub subscription isn't unsubscribed explicitly at that point; it is
  released when the Bandit request process terminates, since Phoenix.PubSub
  auto-unsubscribes a subscriber on its `:DOWN`. The task execution keeps
  running regardless and is re-attachable via `tasks/resubscribe`.

  The enumerable is a **single-use live PubSub subscription** — it is
  enumerated exactly once, via the `Enumerable.reduce/3` continuation, so a
  peek never re-enumerates (and thereby loses) events.
  """
  import Plug.Conn
  alias A2A.Plug.JSONRPC

  @spec respond(Plug.Conn.t(), term(), Enumerable.t()) :: Plug.Conn.t()
  def respond(conn, id, enum) do
    reducer = fn frame, _acc -> {:suspend, frame} end

    case Enumerable.reduce(enum, {:cont, :init}, reducer) do
      {:suspended, first, cont} ->
        conn
        |> sse_headers()
        |> send_chunked(200)
        |> stream_frames(id, first, cont)

      {:done, _} ->
        conn
        |> sse_headers()
        |> send_chunked(200)
    end
  end

  defp sse_headers(conn) do
    conn
    |> put_resp_content_type("text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
  end

  defp stream_frames(conn, id, first, cont) do
    case chunk(conn, encode(id, first)) do
      {:ok, conn} -> drain(conn, id, cont)
      {:error, _} -> conn
    end
  end

  defp drain(conn, id, cont) do
    case cont.({:cont, :acc}) do
      {:suspended, frame, next} ->
        case chunk(conn, encode(id, frame)) do
          {:ok, conn} -> drain(conn, id, next)
          {:error, _} -> conn
        end

      {:done, _} ->
        conn

      {:halted, _} ->
        conn
    end
  end

  defp encode(id, frame), do: ["data: ", JSONRPC.stream_frame(id, frame), "\n\n"]
end
