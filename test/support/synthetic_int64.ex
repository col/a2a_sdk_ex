defmodule A2A.Test.SyntheticInt64 do
  @moduledoc """
  `int64` has no real covered proto field to exercise decode through — this is a
  minimal, hand-built field-spec module used only to test
  `A2A.JSON.from_json_map/2`'s int64 handling (decimal-string or number) in
  `test/a2a/json_test.exs`.
  """
  alias A2A.Types.Field

  defstruct [:big]

  @doc false
  def __a2a_fields__, do: [Field.new(name: :big, proto_name: "big", number: 1, type: :int64)]
end
