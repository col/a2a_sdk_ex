defmodule A2A.Types.RequestsTest do
  use ExUnit.Case, async: true

  alias A2A.Types.{
    GetTaskRequest,
    Message,
    SendMessageConfiguration,
    SendMessageRequest,
    SendMessageResponse,
    Task
  }

  test "SendMessageConfiguration field spec" do
    by_name = Map.new(SendMessageConfiguration.__a2a_fields__(), &{&1.name, &1})

    assert %{proto_name: "accepted_output_modes", number: 1, type: :string, cardinality: :repeated} =
             by_name.accepted_output_modes

    assert %{proto_name: "task_push_notification_config", number: 2, type: :raw} =
             by_name.task_push_notification_config

    assert %{proto_name: "history_length", number: 3, type: :int32, presence: :explicit} =
             by_name.history_length

    assert %{proto_name: "return_immediately", number: 4, type: :bool} = by_name.return_immediately
  end

  test "SendMessageRequest field spec" do
    by_name = Map.new(SendMessageRequest.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "tenant", number: 1, type: :string} = by_name.tenant
    assert %{proto_name: "message", number: 2, type: {:message, Message}} = by_name.message

    assert %{proto_name: "configuration", number: 3, type: {:message, SendMessageConfiguration}} =
             by_name.configuration

    assert %{proto_name: "metadata", number: 4, type: :struct} = by_name.metadata
  end

  test "SendMessageResponse union and GetTaskRequest" do
    assert %SendMessageResponse{kind: :task, task: %Task{id: "t"}} =
             SendMessageResponse.task(%Task{id: "t"})

    resp_by = Map.new(SendMessageResponse.__a2a_fields__(), &{&1.name, &1})
    assert %{oneof: {:payload, :task}, presence: :explicit} = resp_by.task
    assert %{oneof: {:payload, :message}, presence: :explicit} = resp_by.message
    assert SendMessageResponse.__a2a_discriminator__() == :kind

    get_by = Map.new(GetTaskRequest.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "id", number: 2, type: :string} = get_by.id

    assert %{proto_name: "history_length", number: 3, type: :int32, presence: :explicit} =
             get_by.history_length
  end
end
