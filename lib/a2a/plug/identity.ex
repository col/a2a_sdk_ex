defmodule A2A.Plug.Identity do
  @moduledoc """
  Router plug that resolves the caller into an `A2A.User` once, before dispatch,
  and stashes it on `conn.private[:a2a_user]`. Both bindings read that one key, so
  JSON-RPC and REST resolve identity identically. The `user_resolver` (a server
  option, default an anonymous user) does the work; the SDK does not itself verify
  credentials — a host authenticates in its own pipeline and the resolver converts
  the request into an `A2A.User`. The configured `user_resolver` MUST return an
  `A2A.User` struct: this is a host contract, not a graceful fallback — returning
  anything else raises and surfaces as a 500 (see ADR-0018's resolver-totality
  stance).

  Agent-card discovery (`/.well-known/...`) is exempt: the public card names no
  caller.

  The server name is read from `opts[:server]` (direct/unit-test invocation) or,
  when absent, from `conn.assigns[:init_opts][:server]` (mounted in the router
  pipeline, where `Plug.Router`'s `copy_opts_to_assign: :init_opts` has already
  copied the mount opts into assigns before this plug runs).
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: [".well-known" | _]} = conn, _opts), do: conn

  def call(%Plug.Conn{} = conn, opts) do
    name = opts[:server] || conn.assigns[:init_opts][:server]
    server = A2A.Server.handle(name)
    Plug.Conn.put_private(conn, :a2a_user, server.user_resolver.(conn))
  end

  @doc "The resolved caller, or `A2A.User.anonymous/0` if the plug never ran."
  @spec current_user(Plug.Conn.t()) :: A2A.User.t()
  def current_user(%Plug.Conn{} = conn),
    do: Map.get(conn.private, :a2a_user, A2A.User.anonymous())
end
