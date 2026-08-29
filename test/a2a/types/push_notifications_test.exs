defmodule A2A.Types.PushNotificationsTest do
  use ExUnit.Case, async: true

  alias A2A.Types.{
    AuthenticationInfo,
    DeleteTaskPushNotificationConfigRequest,
    GetTaskPushNotificationConfigRequest,
    ListTaskPushNotificationConfigsRequest,
    ListTaskPushNotificationConfigsResponse,
    TaskPushNotificationConfig
  }

  test "TaskPushNotificationConfig field spec" do
    by_name = Map.new(TaskPushNotificationConfig.__a2a_fields__(), &{&1.name, &1})
    assert TaskPushNotificationConfig.__a2a_proto_name__() == "TaskPushNotificationConfig"
    assert %{proto_name: "tenant", number: 1, type: :string} = by_name.tenant
    assert %{proto_name: "id", number: 2, type: :string} = by_name.id
    assert %{proto_name: "task_id", number: 3, type: :string} = by_name.task_id
    assert %{proto_name: "url", number: 4, type: :string} = by_name.url
    assert %{proto_name: "token", number: 5, type: :string} = by_name.token

    assert %{proto_name: "authentication", number: 6, type: {:message, AuthenticationInfo}} =
             by_name.authentication
  end

  test "Get/Delete push-config requests share the tenant/task_id/id shape" do
    for mod <- [
          GetTaskPushNotificationConfigRequest,
          DeleteTaskPushNotificationConfigRequest
        ] do
      by_name = Map.new(mod.__a2a_fields__(), &{&1.name, &1})
      assert %{proto_name: "tenant", number: 1, type: :string} = by_name.tenant
      assert %{proto_name: "task_id", number: 2, type: :string} = by_name.task_id
      assert %{proto_name: "id", number: 3, type: :string} = by_name.id
    end
  end

  test "ListTaskPushNotificationConfigsRequest field numbers are out of positional order" do
    by_name = Map.new(ListTaskPushNotificationConfigsRequest.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "task_id", number: 1, type: :string} = by_name.task_id

    assert %{proto_name: "page_size", number: 2, type: :int32, presence: :implicit} =
             by_name.page_size

    assert %{proto_name: "page_token", number: 3, type: :string} = by_name.page_token
    assert %{proto_name: "tenant", number: 4, type: :string} = by_name.tenant
  end

  test "ListTaskPushNotificationConfigsResponse repeated configs" do
    by_name = Map.new(ListTaskPushNotificationConfigsResponse.__a2a_fields__(), &{&1.name, &1})

    assert %{
             proto_name: "configs",
             number: 1,
             type: {:message, TaskPushNotificationConfig},
             cardinality: :repeated
           } = by_name.configs

    assert %{proto_name: "next_page_token", number: 2, type: :string} = by_name.next_page_token
  end
end
