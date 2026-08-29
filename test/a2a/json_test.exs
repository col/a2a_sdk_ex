defmodule A2A.JSONTest do
  use ExUnit.Case, async: true
  alias A2A.JSON
  alias A2A.Types.{Artifact, Message, Part, Task, TaskStatus}

  defp jmap(struct), do: JSON.to_json_map(struct)

  test "camelCase keys, snake_case dropped, enums as proto names" do
    m = %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}
    map = jmap(m)
    assert map["messageId"] == "m1"
    assert map["role"] == "ROLE_USER"
    assert [%{"text" => "hi"}] = map["parts"]
  end

  test "omits nil and implicit-default scalars, keeps explicit-presence zero" do
    # empty string / empty list / false omitted
    assert jmap(%Message{message_id: "x", role: :agent, parts: []}) == %{
             "messageId" => "x",
             "role" => "ROLE_AGENT"
           }

    assert jmap(%A2A.Types.GetTaskRequest{id: "t", history_length: 0}) == %{
             "id" => "t",
             "historyLength" => 0
           }
  end

  test "implicit-presence fields holding their literal type-default are dropped" do
    # implicit-presence empty string ("") is omitted
    assert jmap(%Message{message_id: "", role: :agent}) == %{"role" => "ROLE_AGENT"}

    # implicit-presence false bool is omitted
    assert jmap(%A2A.Types.SendMessageConfiguration{return_immediately: false}) == %{}
  end

  test "bytes -> standard base64 with padding" do
    assert jmap(Part.raw(<<255, 240, 1>>)) == %{"raw" => Base.encode64(<<255, 240, 1>>)}
  end

  test "google.protobuf.Struct metadata and Value data pass through as JSON" do
    assert jmap(Part.data(%{"k" => [1, 2, %{"z" => true}]}))["data"] == %{
             "k" => [1, 2, %{"z" => true}]
           }

    assert jmap(%Message{message_id: "m", role: :user, metadata: %{"a" => 1}})["metadata"] ==
             %{"a" => 1}
  end

  test "Timestamp -> Z-normalized RFC3339" do
    ts = ~U[2023-10-27 10:00:00Z]
    assert jmap(%TaskStatus{state: :working, timestamp: ts})["timestamp"] == "2023-10-27T10:00:00Z"
  end

  test "nested messages and repeated fields recurse" do
    t = %Task{
      id: "t1",
      status: %TaskStatus{state: :completed},
      artifacts: [%Artifact{artifact_id: "a", parts: [Part.text("x")]}]
    }

    map = jmap(t)
    assert map["id"] == "t1"
    assert map["status"] == %{"state" => "TASK_STATE_COMPLETED"}
    assert [%{"artifactId" => "a", "parts" => [%{"text" => "x"}]}] = map["artifacts"]
  end

  test "encode/1 produces JSON via Jason" do
    {:ok, iodata} = JSON.encode(%TaskStatus{state: :working})
    assert Jason.decode!(IO.iodata_to_binary(iodata)) == %{"state" => "TASK_STATE_WORKING"}
  end

  test "encode!/1 produces JSON via Jason" do
    iodata = JSON.encode!(%TaskStatus{state: :working})
    assert Jason.decode!(IO.iodata_to_binary(iodata)) == %{"state" => "TASK_STATE_WORKING"}
  end

  test "int64 synthetic rule: encoded as decimal string" do
    # exercised via A2A.JSON.encode_scalar/2 indirectly in the int64 synthetic test module (Task 11);
    # here assert the helper directly if exposed, else covered by synthetic fixtures.
    assert JSON.encode_scalar(:int64, 9_000_000_000) == "9000000000"
  end
end
