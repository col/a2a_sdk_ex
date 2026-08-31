defmodule A2A.Test.CapturingSender do
  @moduledoc "Test `A2A.Server.PushSender` that forwards `{config, frame}` to a registered pid instead of doing HTTP."
  @behaviour A2A.Server.PushSender

  def attach(pid \\ self()), do: :persistent_term.put(__MODULE__, pid)

  @impl true
  def send(config, frame, _opts \\ []) do
    case :persistent_term.get(__MODULE__, nil) do
      pid when is_pid(pid) -> Kernel.send(pid, {:push, config, frame})
      _ -> :ok
    end

    :ok
  end
end

defmodule A2A.Test.WebhookReceiver do
  @moduledoc "Tiny Bandit+Plug receiver that forwards each POST (headers+body) to a pid. For live push-delivery tests."
  import Plug.Conn

  def init(pid), do: pid

  def call(conn, pid) do
    {:ok, body, conn} = read_body(conn)
    send(pid, {:webhook, conn.req_headers, body})
    send_resp(conn, 200, "")
  end

  @doc "Starts the receiver on an ephemeral port; returns {base_url, server_pid}."
  def start(test_pid) do
    {:ok, srv} = Bandit.start_link(plug: {__MODULE__, test_pid}, port: 0, ip: {127, 0, 0, 1})
    # `Bandit.start_link/1` returns the pid of the `ThousandIsland` top-level
    # supervisor directly (Bandit does not wrap it in its own Supervisor), so
    # `srv` is already the `supervisor` argument `ThousandIsland.listener_info/1`
    # expects.
    {:ok, {_ip, port}} = ThousandIsland.listener_info(srv)
    {"http://127.0.0.1:#{port}", srv}
  end
end
