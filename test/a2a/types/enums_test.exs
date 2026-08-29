defmodule A2A.Types.EnumsTest do
  use ExUnit.Case, async: true
  alias A2A.Types.Enums

  test "encodes task_state atoms to SCREAMING_SNAKE proto names" do
    assert Enums.encode(:task_state, :input_required) == {:ok, "TASK_STATE_INPUT_REQUIRED"}
    assert Enums.encode(:task_state, :canceled) == {:ok, "TASK_STATE_CANCELED"}
    assert Enums.encode(:role, :user) == {:ok, "ROLE_USER"}
  end

  test "decodes proto names and integers, both directions" do
    assert Enums.decode(:task_state, "TASK_STATE_WORKING") == {:ok, :working}
    assert Enums.decode(:task_state, 8) == {:ok, :auth_required}
    assert Enums.decode(:role, "ROLE_AGENT") == {:ok, :agent}
  end

  test "rejects UNSPECIFIED / zero and unknown values" do
    assert {:error, _} = Enums.decode(:task_state, "TASK_STATE_UNSPECIFIED")
    assert {:error, _} = Enums.decode(:task_state, 0)
    assert {:error, _} = Enums.decode(:role, "ROLE_BOGUS")
    assert {:error, _} = Enums.encode(:task_state, :bogus)
  end

  test "lists proto enum type names for the coverage manifest" do
    assert Enum.sort(Enums.proto_names()) == ["Role", "TaskState"]
  end
end
