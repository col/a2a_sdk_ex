defmodule A2A.Plug.SSE do
  @moduledoc """
  Streams a lazy enumerable of `%A2A.Types.StreamResponse{}` frames as
  Server-Sent Events.
  """
  import Plug.Conn
  alias A2A.Plug.JSONRPC

  @spec respond(Plug.Conn.t(), term(), Enumerable.t()) :: Plug.Conn.t()
  def respond(conn, id, enum), do: respond(conn, id, enum, &JSONRPC.stream_frame/2)

  @spec respond(
          Plug.Conn.t(),
          term(),
          Enumerable.t(),
          (term(), A2A.Types.StreamResponse.t() -> iodata())
        ) :: Plug.Conn.t()
  def respond(conn, id, enum, formatter) do
    reducer = fn frame, _acc -> {:suspend, frame} end

    case Enumerable.reduce(enum, {:cont, :init}, reducer) do
      {:suspended, first, cont} ->
        conn
        |> sse_headers()
        |> send_chunked(200)
        |> stream_frames(id, first, cont, formatter)

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

  defp stream_frames(conn, id, first, cont, formatter) do
    case chunk(conn, encode(id, first, formatter)) do
      {:ok, conn} -> drain(conn, id, cont, formatter)
      {:error, _} -> conn
    end
  end

  defp drain(conn, id, cont, formatter) do
    case cont.({:cont, :acc}) do
      {:suspended, frame, next} ->
        case chunk(conn, encode(id, frame, formatter)) do
          {:ok, conn} -> drain(conn, id, next, formatter)
          {:error, _} -> conn
        end

      {:done, _} ->
        conn

      {:halted, _} ->
        conn
    end
  end

  defp encode(id, frame, formatter), do: ["data: ", formatter.(id, frame), "\n\n"]
end
