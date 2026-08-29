defmodule A2A.Types.Field do
  @moduledoc false

  alias A2A.JSON.Naming

  @enforce_keys [:name, :proto_name, :number, :type]
  defstruct [
    :name,
    :proto_name,
    :json_name,
    :number,
    :type,
    cardinality: :singular,
    presence: :implicit,
    oneof: nil
  ]

  @type wire ::
          :string
          | :bool
          | :int32
          | :int64
          | :bytes
          | :timestamp
          | :struct
          | :value
          | :raw
          | {:enum, :task_state | :role}
          | {:message, module}

  @type t :: %__MODULE__{
          name: atom,
          proto_name: String.t(),
          json_name: String.t(),
          number: pos_integer,
          type: wire,
          cardinality: :singular | :repeated,
          presence: :implicit | :explicit,
          oneof: nil | {atom, atom}
        }

  @doc "Builds a field spec, deriving `json_name` from `proto_name` when omitted."
  @spec new(keyword) :: t
  def new(opts) do
    proto_name = Keyword.fetch!(opts, :proto_name)
    opts = Keyword.put_new(opts, :json_name, Naming.to_camel(proto_name))
    struct!(__MODULE__, opts)
  end
end
