defmodule A2A.JSONPropertyTest do
  @moduledoc """
  Property-based round-trip tests: `decode(encode(x)) == x`. These run without
  `protoc` — they only exercise our own codec, never the generated oracle
  modules. See `test/support/generators.ex` for why the generators are
  restricted to decode-legal, round-trip-stable values.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias A2A.JSON
  alias A2A.Test.Generators

  property "decode(encode(x)) == x for Message" do
    check all(m <- Generators.message()) do
      {:ok, io} = JSON.encode(m)
      assert {:ok, ^m} = JSON.decode(IO.iodata_to_binary(io), A2A.Types.Message)
    end
  end

  property "decode(encode(x)) == x for Part" do
    check all(p <- Generators.part()) do
      {:ok, io} = JSON.encode(p)
      assert {:ok, ^p} = JSON.decode(IO.iodata_to_binary(io), A2A.Types.Part)
    end
  end

  property "decode(encode(x)) == x for Artifact" do
    check all(a <- Generators.artifact()) do
      {:ok, io} = JSON.encode(a)
      assert {:ok, ^a} = JSON.decode(IO.iodata_to_binary(io), A2A.Types.Artifact)
    end
  end

  property "decode(encode(x)) == x for TaskStatus" do
    check all(ts <- Generators.task_status()) do
      {:ok, io} = JSON.encode(ts)
      assert {:ok, ^ts} = JSON.decode(IO.iodata_to_binary(io), A2A.Types.TaskStatus)
    end
  end

  property "decode(encode(x)) == x for Task" do
    check all(t <- Generators.task()) do
      {:ok, io} = JSON.encode(t)
      assert {:ok, ^t} = JSON.decode(IO.iodata_to_binary(io), A2A.Types.Task)
    end
  end

  property "decode(encode(x)) == x for SecurityScheme" do
    check all(s <- Generators.security_scheme()) do
      {:ok, io} = JSON.encode(s)
      assert {:ok, ^s} = JSON.decode(IO.iodata_to_binary(io), A2A.Types.SecurityScheme)
    end
  end

  for {name, gen_fun, module} <- [
        {"TaskPushNotificationConfig", :task_push_notification_config,
         A2A.Types.TaskPushNotificationConfig},
        {"GetTaskPushNotificationConfigRequest", :get_task_push_notification_config_request,
         A2A.Types.GetTaskPushNotificationConfigRequest},
        {"DeleteTaskPushNotificationConfigRequest", :delete_task_push_notification_config_request,
         A2A.Types.DeleteTaskPushNotificationConfigRequest},
        {"ListTaskPushNotificationConfigsRequest", :list_task_push_notification_configs_request,
         A2A.Types.ListTaskPushNotificationConfigsRequest},
        {"ListTaskPushNotificationConfigsResponse", :list_task_push_notification_configs_response,
         A2A.Types.ListTaskPushNotificationConfigsResponse},
        {"ListTasksRequest", :list_tasks_request, A2A.Types.ListTasksRequest},
        {"ListTasksResponse", :list_tasks_response, A2A.Types.ListTasksResponse},
        {"CancelTaskRequest", :cancel_task_request, A2A.Types.CancelTaskRequest},
        {"SubscribeToTaskRequest", :subscribe_to_task_request, A2A.Types.SubscribeToTaskRequest}
      ] do
    property "decode(encode(x)) == x for #{name}" do
      check all(x <- apply(Generators, unquote(gen_fun), [])) do
        {:ok, io} = JSON.encode(x)
        assert {:ok, ^x} = JSON.decode(IO.iodata_to_binary(io), unquote(module))
      end
    end
  end
end
