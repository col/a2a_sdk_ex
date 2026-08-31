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

defmodule A2A.Test.RaisingSender do
  @moduledoc "Test `A2A.Server.PushSender` whose `send/3` always raises — proves the dispatcher survives a raising sender (best-effort delivery)."
  @behaviour A2A.Server.PushSender

  # `send/3` unconditionally raises (by design, to exercise the dispatcher's
  # rescue path), so Dialyzer infers `no_return` for the underlying `send/2`
  # clause — expected and intentional here, not a defect.
  @dialyzer {:nowarn_function, send: 2}

  @impl true
  def send(_config, _frame, _opts \\ []), do: raise("boom")
end

defmodule A2A.Test.PartialRaisingSender do
  @moduledoc """
  Test `A2A.Server.PushSender` that RAISES when `config.url` contains `"raise"` and
  otherwise forwards `{:push, config, frame}` to the attached pid (like
  `A2A.Test.CapturingSender`). Proves a raising dispatch for one config neither
  aborts a sibling config's delivery within the same event nor kills the dispatcher
  across events — the normal config must keep receiving every event.
  """
  @behaviour A2A.Server.PushSender

  def attach(pid \\ self()), do: :persistent_term.put({__MODULE__, :pid}, pid)

  @impl true
  def send(config, frame, _opts \\ []) do
    if String.contains?(config.url, "raise"), do: raise("boom")

    case :persistent_term.get({__MODULE__, :pid}, nil) do
      pid when is_pid(pid) -> Kernel.send(pid, {:push, config, frame})
      _ -> :ok
    end

    :ok
  end
end

defmodule A2A.Test.DelayingSender do
  @moduledoc """
  Test `A2A.Server.PushSender` that records an ordered `{:delivered, config_id, frame}`
  to the attached pid, optionally sleeping first. The delay is configured per config
  id via `configure/1` so a slow webhook, under a would-be fire-and-forget impl, would
  reorder relative to a fast one — the dispatcher's per-event barrier prevents that.
  """
  @behaviour A2A.Server.PushSender

  def attach(pid \\ self()), do: :persistent_term.put({__MODULE__, :pid}, pid)

  @doc ~S(Set per-config-id delays in ms, e.g. `%{"slow" => 40, "fast" => 0}`.)
  def configure(delays), do: :persistent_term.put({__MODULE__, :delays}, delays)

  @impl true
  def send(config, frame, _opts \\ []) do
    delays = :persistent_term.get({__MODULE__, :delays}, %{})
    if ms = delays[config.id], do: Process.sleep(ms)

    case :persistent_term.get({__MODULE__, :pid}, nil) do
      pid when is_pid(pid) -> Kernel.send(pid, {:delivered, config.id, frame})
      _ -> :ok
    end

    :ok
  end
end

defmodule A2A.Test.RaisingPushStore do
  @moduledoc """
  Test `A2A.Server.PushConfigStore` whose `put/2` always raises — proves the
  INLINE registration path in `DefaultHandler.maybe_register_inline_push/3` is
  best-effort against a broken store (a raise there must not fail `SendMessage`).
  `get/3`, `list/2`, `delete/3` delegate to the real ETS store so the rest of the
  flow (e.g. dispatcher lookups) behaves normally.
  """
  @behaviour A2A.Server.PushConfigStore

  alias A2A.Server.PushConfigStore.ETS

  @impl true
  def put(_config, _scope), do: raise("boom: push store put failed")

  @impl true
  def get(task_id, id, scope), do: ETS.get(task_id, id, scope)

  @impl true
  def list(task_id, scope), do: ETS.list(task_id, scope)

  @impl true
  def delete(task_id, id, scope), do: ETS.delete(task_id, id, scope)
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
