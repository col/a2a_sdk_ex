defmodule A2A.Types.RequestsTest do
  use ExUnit.Case, async: true

  alias A2A.Types.{
    CancelTaskRequest,
    GetTaskRequest,
    ListTasksRequest,
    ListTasksResponse,
    Message,
    SendMessageConfiguration,
    SendMessageRequest,
    SendMessageResponse,
    SubscribeToTaskRequest,
    Task,
    TaskPushNotificationConfig
  }

  test "SendMessageConfiguration field spec" do
    by_name = Map.new(SendMessageConfiguration.__a2a_fields__(), &{&1.name, &1})

    assert %{proto_name: "accepted_output_modes", number: 1, type: :string, cardinality: :repeated} =
             by_name.accepted_output_modes

    assert %{
             proto_name: "task_push_notification_config",
             number: 2,
             type: {:message, TaskPushNotificationConfig}
           } = by_name.task_push_notification_config

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

  test "ListTasksRequest field spec" do
    by_name = Map.new(ListTasksRequest.__a2a_fields__(), &{&1.name, &1})
    assert ListTasksRequest.__a2a_proto_name__() == "ListTasksRequest"
    assert %{proto_name: "tenant", number: 1, type: :string} = by_name.tenant
    assert %{proto_name: "context_id", number: 2, type: :string} = by_name.context_id
    assert %{proto_name: "status", number: 3, type: {:enum, :task_state}} = by_name.status

    assert %{proto_name: "page_size", number: 4, type: :int32, presence: :explicit} =
             by_name.page_size

    assert %{proto_name: "page_token", number: 5, type: :string} = by_name.page_token

    assert %{proto_name: "history_length", number: 6, type: :int32, presence: :explicit} =
             by_name.history_length

    assert %{proto_name: "status_timestamp_after", number: 7, type: :timestamp} =
             by_name.status_timestamp_after

    assert %{proto_name: "include_artifacts", number: 8, type: :bool, presence: :explicit} =
             by_name.include_artifacts
  end

  test "ListTasksResponse field spec" do
    by_name = Map.new(ListTasksResponse.__a2a_fields__(), &{&1.name, &1})

    assert %{proto_name: "tasks", number: 1, type: {:message, Task}, cardinality: :repeated} =
             by_name.tasks

    assert %{proto_name: "next_page_token", number: 2, type: :string} = by_name.next_page_token

    assert %{proto_name: "page_size", number: 3, type: :int32, presence: :implicit} =
             by_name.page_size

    assert %{proto_name: "total_size", number: 4, type: :int32, presence: :implicit} =
             by_name.total_size
  end

  test "CancelTaskRequest and SubscribeToTaskRequest field specs" do
    cancel = Map.new(CancelTaskRequest.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "tenant", number: 1, type: :string} = cancel.tenant
    assert %{proto_name: "id", number: 2, type: :string} = cancel.id
    assert %{proto_name: "metadata", number: 3, type: :struct} = cancel.metadata

    sub = Map.new(SubscribeToTaskRequest.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "tenant", number: 1, type: :string} = sub.tenant
    assert %{proto_name: "id", number: 2, type: :string} = sub.id
  end

  test "ListTasksResponse round-trips through the codec" do
    resp = %ListTasksResponse{
      tasks: [%Task{id: "t-1"}],
      next_page_token: "cursor",
      page_size: 25,
      total_size: 100
    }

    {:ok, io} = A2A.JSON.encode(resp)
    assert {:ok, ^resp} = A2A.JSON.decode(IO.iodata_to_binary(io), ListTasksResponse)
  end
end
