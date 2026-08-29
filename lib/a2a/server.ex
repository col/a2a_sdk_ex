defmodule A2A.Server do
  @moduledoc "The resolved runtime handle for a mounted A2A server. Built by `A2A.Server.Supervisor`."

  @type t :: %__MODULE__{
          name: atom(),
          executor: module(),
          pubsub: atom(),
          registry: atom(),
          dyn_sup: atom(),
          store: module(),
          scope: A2A.Scope.t(),
          id_generator: (-> String.t())
        }
  defstruct [:name, :executor, :pubsub, :registry, :dyn_sup, :store, :scope, :id_generator]

  @spec handle(atom()) :: t()
  def handle(name), do: :persistent_term.get({__MODULE__, name})

  @doc false
  def put_handle(%__MODULE__{name: name} = handle),
    do: :persistent_term.put({__MODULE__, name}, handle)

  @doc "Default id generator: lowercase hex, 16 bytes."
  @spec default_id() :: String.t()
  def default_id, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
end
