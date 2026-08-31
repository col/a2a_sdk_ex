defmodule A2A.Server.StreamingPropertyTest do
  @moduledoc """
  Property coverage for the streaming path: any valid event script (see
  `A2A.Test.Generators.valid_event_script/0`) replayed by `A2A.Test.ReplayExecutor`
  through `DefaultHandler.send_message_stream/2` must yield only codec-valid
  `%StreamResponse{}` frames. A single `A2A.Server.Supervisor` is started once in
  `setup` (not per property run) because `A2A.Server.TaskStore.ETS` is a globally
  named `GenServer` — starting a second one concurrently would crash with
  `{:already_started, _}`. Each property run instead uses a fresh task id.
  """
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias A2A.Server.DefaultHandler
  alias A2A.Test.{Generators, ReplayExecutor}
  alias A2A.Types.{Message, Part, SendMessageRequest, StreamResponse}

  setup do
    name = :"srv_prop_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_prop_#{System.unique_integer([:positive])}"

    start_supervised!({A2A.Server.Supervisor, name: name, executor: ReplayExecutor, pubsub: pubsub})

    %{server: A2A.Server.handle(name)}
  end

  property "any valid event script projects to codec-valid StreamResponse frames",
           %{server: server} do
    check all(events <- Generators.valid_event_script(), max_runs: 25) do
      task_id = "prop_#{System.unique_integer([:positive])}"
      :ok = ReplayExecutor.load(task_id, events)

      # The ReplayExecutor is keyed by task id, so the id is pinned through the
      # server's generator — spec 3.4.2 forbids a client-supplied taskId for
      # creating a task.
      server = %{server | id_generator: fn -> task_id end}

      req = %SendMessageRequest{
        message: %Message{message_id: "m_#{task_id}", role: :user, parts: [Part.text("go")]}
      }

      frames = server |> DefaultHandler.send_message_stream(req) |> Enum.to_list()

      # One frame per scripted step, in order.
      assert length(frames) == length(events)

      for %StreamResponse{} = frame <- frames do
        json = A2A.JSON.encode!(frame)
        assert {:ok, %StreamResponse{}} = A2A.JSON.decode(json, StreamResponse)
      end
    end
  end
end
