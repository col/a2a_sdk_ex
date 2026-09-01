defmodule A2A.Server do
  @moduledoc "The resolved runtime handle for a mounted A2A server. Built by `A2A.Server.Supervisor`."

  @type timeout_opt :: non_neg_integer() | :infinity

  @type t :: %__MODULE__{
          name: atom(),
          executor: module(),
          pubsub: atom(),
          registry: atom(),
          dyn_sup: atom(),
          store: module(),
          scope: A2A.Scope.t(),
          user: A2A.User.t(),
          user_resolver: (Plug.Conn.t() -> A2A.User.t()),
          owner_resolver: (A2A.User.t() -> String.t() | nil),
          extended_agent_card_resolver: (A2A.User.t() -> A2A.Types.AgentCard.t() | nil) | nil,
          id_generator: (-> String.t()),
          drain_timeout: timeout_opt(),
          stream_idle_timeout: timeout_opt(),
          agent_card: A2A.Types.AgentCard.t() | nil,
          agent_card_modified_at: DateTime.t() | nil,
          push_notifications: boolean(),
          push_store: module() | nil,
          push_sender: module() | nil,
          push_timeout: timeout_opt(),
          push_idle_timeout: timeout_opt(),
          push_url_validator: (String.t() -> :ok | {:error, term()}) | nil,
          push_registry: atom() | nil,
          push_dyn_sup: atom() | nil
        }
  defstruct [
    :name,
    :executor,
    :pubsub,
    :registry,
    :dyn_sup,
    :store,
    :scope,
    :user_resolver,
    :owner_resolver,
    :extended_agent_card_resolver,
    :id_generator,
    :agent_card,
    :agent_card_modified_at,
    :push_store,
    :push_sender,
    :push_url_validator,
    :push_registry,
    :push_dyn_sup,
    user: nil,
    drain_timeout: :infinity,
    stream_idle_timeout: 300_000,
    push_notifications: false,
    push_timeout: 5_000,
    push_idle_timeout: 60_000
  ]

  @spec handle(atom()) :: t()
  def handle(name), do: :persistent_term.get({__MODULE__, name})

  @doc false
  def put_handle(%__MODULE__{name: name} = handle),
    do: :persistent_term.put({__MODULE__, name}, handle)

  @doc """
  Returns a per-request copy of this handle carrying the resolved caller and an
  owner-scoped `A2A.Scope`. Every downstream `server.scope` store call is thereby
  isolated to the owner, and `A2A.Server.DefaultHandler` reads `server.user` for
  the `A2A.Server.RequestContext`. The `owner_resolver` default yields `nil`, so an
  unconfigured server keeps its single shared bucket.
  """
  @spec for_request(t(), A2A.User.t()) :: t()
  def for_request(%__MODULE__{scope: %A2A.Scope{} = scope} = server, %A2A.User{} = user) do
    %{server | user: user, scope: %A2A.Scope{scope | owner: server.owner_resolver.(user)}}
  end

  @doc "Default id generator: lowercase hex, 16 bytes."
  @spec default_id() :: String.t()
  def default_id, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
end
