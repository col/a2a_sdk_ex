defmodule A2A.Types.TaskStatusTest do
  use ExUnit.Case, async: true
  alias A2A.Types.{Message, TaskStatus}

  test "field spec: state enum (field 2 = message), timestamp" do
    by_name = Map.new(TaskStatus.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "state", number: 1, type: {:enum, :task_state}} = by_name.state
    assert %{proto_name: "message", number: 2, type: {:message, Message}} = by_name.message
    assert %{proto_name: "timestamp", number: 3, type: :timestamp} = by_name.timestamp
    assert TaskStatus.__a2a_proto_name__() == "TaskStatus"
  end
end
