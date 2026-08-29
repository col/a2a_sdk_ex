defmodule A2A.Types.MessageTest do
  use ExUnit.Case, async: true
  alias A2A.Types.{Message, Part}

  test "constructs a message and exposes its field spec" do
    m = %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}
    assert m.message_id == "m1" and m.role == :user
    by_name = Map.new(Message.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "message_id", number: 1, type: :string} = by_name.message_id
    assert %{proto_name: "role", number: 4, type: {:enum, :role}} = by_name.role

    assert %{proto_name: "parts", number: 5, type: {:message, Part}, cardinality: :repeated} =
             by_name.parts

    assert %{proto_name: "metadata", number: 6, type: :struct} = by_name.metadata

    assert %{proto_name: "extensions", number: 7, type: :string, cardinality: :repeated} =
             by_name.extensions

    assert %{
             proto_name: "reference_task_ids",
             number: 8,
             cardinality: :repeated,
             json_name: "referenceTaskIds"
           } = by_name.reference_task_ids

    assert Message.__a2a_proto_name__() == "Message"
  end
end
