defmodule A2A.Types.TaskTest do
  use ExUnit.Case, async: true
  alias A2A.Types.{Artifact, Message, Task, TaskStatus}

  test "field spec" do
    by_name = Map.new(Task.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "id", number: 1, type: :string} = by_name.id

    assert %{proto_name: "context_id", number: 2, type: :string, json_name: "contextId"} =
             by_name.context_id

    assert %{proto_name: "status", number: 3, type: {:message, TaskStatus}} = by_name.status

    assert %{proto_name: "artifacts", number: 4, type: {:message, Artifact}, cardinality: :repeated} =
             by_name.artifacts

    assert %{proto_name: "history", number: 5, type: {:message, Message}, cardinality: :repeated} =
             by_name.history

    assert %{proto_name: "metadata", number: 6, type: :struct} = by_name.metadata
    assert Task.__a2a_proto_name__() == "Task"
  end
end
