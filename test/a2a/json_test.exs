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

  test "Timestamp with a non-UTC offset normalizes to Z at the correct instant" do
    {:ok, plus_two, 7200} = DateTime.from_iso8601("2023-10-27T12:00:00+02:00")
    encoded = jmap(%TaskStatus{state: :working, timestamp: plus_two})["timestamp"]
    assert encoded == "2023-10-27T10:00:00Z"

    assert {:ok, %TaskStatus{state: :working, timestamp: ~U[2023-10-27 10:00:00Z]}} =
             JSON.from_json_map(
               %{"state" => "TASK_STATE_WORKING", "timestamp" => encoded},
               TaskStatus
             )
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

  test "int64 synthetic: encode as decimal string, decode from string or number" do
    # int64 has no real covered proto field, so exercise the codec helpers directly
    # via A2A.Test.SyntheticInt64 (test/support/synthetic_int64.ex).
    assert JSON.encode_scalar(:int64, 9_000_000_000) == "9000000000"

    assert {:ok, %{big: 9_000_000_000}} =
             JSON.from_json_map(%{"big" => "9000000000"}, A2A.Test.SyntheticInt64)

    assert {:ok, %{big: 42}} = JSON.from_json_map(%{"big" => 42}, A2A.Test.SyntheticInt64)

    assert {:error, _} = JSON.from_json_map(%{"big" => "not-a-number"}, A2A.Test.SyntheticInt64)
  end

  test "decode accepts camelCase and snake_case keys" do
    {:ok, m1} = JSON.from_json_map(%{"messageId" => "m", "role" => "ROLE_USER"}, Message)
    {:ok, m2} = JSON.from_json_map(%{"message_id" => "m", "role" => "ROLE_USER"}, Message)
    assert m1 == m2
    assert m1.message_id == "m" and m1.role == :user
  end

  test "decode enums accept name and integer, reject UNSPECIFIED" do
    assert {:ok, %TaskStatus{state: :working}} =
             JSON.from_json_map(%{"state" => "TASK_STATE_WORKING"}, TaskStatus)

    assert {:ok, %TaskStatus{state: :working}} = JSON.from_json_map(%{"state" => 2}, TaskStatus)
    assert {:error, _} = JSON.from_json_map(%{"state" => "TASK_STATE_UNSPECIFIED"}, TaskStatus)
  end

  test "decode base64 accepts standard, urlsafe, and unpadded" do
    b = <<255, 240, 1>>

    for enc <- [Base.encode64(b), Base.url_encode64(b), Base.encode64(b, padding: false)] do
      assert {:ok, %Part{kind: :raw, raw: ^b}} = JSON.from_json_map(%{"raw" => enc}, Part)
    end
  end

  test "decode sets the discriminator on unions" do
    {:ok, sr} =
      JSON.from_json_map(%{"statusUpdate" => %{"taskId" => "t"}}, A2A.Types.StreamResponse)

    assert sr.kind == :status_update
    assert sr.status_update.task_id == "t"
  end

  test "decode timestamp parses RFC3339 with offset to UTC DateTime" do
    {:ok, ts} =
      JSON.from_json_map(
        %{"state" => "TASK_STATE_WORKING", "timestamp" => "2023-10-27T12:00:00+02:00"},
        TaskStatus
      )

    assert ts.timestamp == ~U[2023-10-27 10:00:00Z]
  end

  test "decode/2 parses a JSON string" do
    assert {:ok, %TaskStatus{state: :completed}} =
             JSON.decode(~s({"state":"TASK_STATE_COMPLETED"}), TaskStatus)
  end

  test "round-trips a rich Task through encode |> decode" do
    task = %Task{
      id: "t1",
      context_id: "c1",
      status: %TaskStatus{state: :working, timestamp: ~U[2023-10-27 10:00:00Z]},
      artifacts: [
        %Artifact{
          artifact_id: "a1",
          parts: [Part.text("hi"), Part.raw(<<1, 2>>), Part.data(%{"k" => 1})]
        }
      ],
      metadata: %{"m" => true}
    }

    {:ok, iodata} = JSON.encode(task)
    assert {:ok, ^task} = JSON.decode(IO.iodata_to_binary(iodata), Task)
  end
end
