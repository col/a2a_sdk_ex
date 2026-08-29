defmodule A2A.JSON.NamingTest do
  use ExUnit.Case, async: true
  alias A2A.JSON.Naming

  test "converts snake_case to lowerCamelCase" do
    assert Naming.to_camel("message_id") == "messageId"
    assert Naming.to_camel("context_id") == "contextId"
    assert Naming.to_camel("reference_task_ids") == "referenceTaskIds"
    assert Naming.to_camel("media_type") == "mediaType"
    assert Naming.to_camel("state") == "state"
    assert Naming.to_camel("task_push_notification_config") == "taskPushNotificationConfig"
  end
end
