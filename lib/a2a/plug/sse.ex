defmodule A2A.Plug.SSE do
  @moduledoc false
  # Temporary stub — real streaming lands in Task 5.
  def respond(conn, _id, _enum), do: Plug.Conn.send_resp(conn, 501, "streaming not yet wired")
end
