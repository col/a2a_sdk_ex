defmodule A2A.Server.MultiTurnTest do
  @moduledoc """
  Multi-turn continuation (spec §3.4): a message carrying an existing `taskId`
  continues that task rather than starting a fresh one, and the exchange
  accumulates in the task's history.
  """
  use ExUnit.Case, async: false

  alias A2A.Server.DefaultHandler

  alias A2A.Types.{
    GetTaskRequest,
    ListTasksRequest,
    Message,
    Part,
    SendMessageConfiguration,
    SendMessageRequest,
    StreamResponse,
    Task
  }

  setup do
    name = :"srv_mt_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_mt_#{System.unique_integer([:positive])}"

    start_supervised!(
      {A2A.Server.Supervisor, name: name, executor: A2A.Test.EchoExecutor, pubsub: pubsub}
    )

    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)
    %{server: A2A.Server.handle(name)}
  end

  defp req(text, opts \\ []) do
    %SendMessageRequest{
      message: %Message{
        message_id: "m_#{System.unique_integer([:positive])}",
        role: :user,
        task_id: Keyword.get(opts, :task_id),
        context_id: Keyword.get(opts, :context_id),
        parts: [Part.text(text)]
      },
      configuration: Keyword.get(opts, :configuration)
    }
  end

  # Turn one leaves the task in `input_required`, which is non-terminal and so
  # resumable — the shape every multi-turn exchange starts from. Uses
  # InputRequiredExecutor rather than AuthThenInputExecutor: since §3.2.2 a
  # blocking send now also returns at `auth_required` (the interrupted state
  # that executor emits first), so it would never reach `input_required` here.
  defp open_turn(server, text \\ "turn one") do
    server = %{server | executor: A2A.Test.InputRequiredExecutor}
    assert {:ok, %Task{status: %{state: :input_required}} = task} = send_msg(server, req(text))
    task
  end

  defp send_msg(server, request), do: DefaultHandler.send_message(server, request)

  defp texts(%Task{history: history}) do
    for %Message{parts: parts} <- history, %Part{kind: :text, text: t} <- parts, do: t
  end

  describe "continuation" do
    test "a follow-up resumes the stored task instead of starting a blank one",
         %{server: server} do
      first = open_turn(server)

      assert {:ok, %Task{} = second} =
               send_msg(server, req("turn two", task_id: first.id))

      assert second.id == first.id
      assert second.status.state == :completed
      # Turn one's artifacts survive rather than being wiped by a fresh projection.
      assert Enum.any?(second.artifacts, fn a ->
               Enum.any?(a.parts, &(&1.text == "echo: turn two"))
             end)
    end

    test "the task keeps its original context id", %{server: server} do
      # Spec §3.4.3: "Agents MUST infer contextId from the task if only taskId
      # is provided" — a follow-up must not mint a new context.
      first = open_turn(server)

      assert {:ok, %Task{context_id: context_id}} =
               send_msg(server, req("turn two", task_id: first.id))

      assert context_id == first.context_id
    end

    test "a follow-up naming a different context id is rejected", %{server: server} do
      # Spec §3.4.3: "Agents MUST reject messages containing mismatching
      # contextId and taskId".
      first = open_turn(server)

      assert {:error, %A2A.Error{code: :invalid_params}} =
               send_msg(server, req("turn two", task_id: first.id, context_id: "somewhere-else"))
    end
  end

  describe "history" do
    test "the incoming user message is recorded, even on the first turn",
         %{server: server} do
      assert {:ok, %Task{} = task} = send_msg(server, req("hello"))

      assert "hello" in texts(task)
    end

    test "each turn appends to the history in the order exchanged", %{server: server} do
      first = open_turn(server, "one")
      {:ok, _} = send_msg(server, req("two", task_id: first.id))

      assert {:ok, %Task{} = task} =
               DefaultHandler.get_task(server, %GetTaskRequest{id: first.id})

      user_texts = Enum.filter(texts(task), &(&1 in ["one", "two"]))
      assert user_texts == ["one", "two"]
    end

    test "the agent's own messages still reach history alongside the user's",
         %{server: server} do
      assert {:ok, %Task{} = task} = send_msg(server, req("hello"))

      # EchoExecutor completes with an agent message; both sides of the exchange
      # are recorded, user first.
      assert ["hello", "done"] = Enum.filter(texts(task), &(&1 in ["hello", "done"]))
    end
  end

  describe "message responses (spec §3.1.1)" do
    test "an executor may answer with a Message instead of creating a Task",
         %{server: server} do
      server = %{server | executor: A2A.Test.ReplyExecutor}

      assert {:ok, %Message{role: :agent, parts: [%Part{text: "direct reply"}]}} =
               send_msg(server, req("ping"))
    end

    test "a message response persists no task", %{server: server} do
      # Spec §3.1.1: a direct Message is "for simple interactions that don't
      # require task tracking" — so nothing is stored to track.
      server = %{server | executor: A2A.Test.ReplyExecutor}

      assert {:ok, %Message{}} = send_msg(server, req("ping"))
      assert {:ok, %{tasks: []}} = DefaultHandler.list_tasks(server, %ListTasksRequest{})
    end

    test "the streaming form is exactly one message frame, then close",
         %{server: server} do
      # Spec §3.1.2: "the stream MUST contain exactly one Message object and
      # then close immediately".
      server = %{server | executor: A2A.Test.ReplyExecutor}

      frames = server |> DefaultHandler.send_message_stream(req("ping")) |> Enum.to_list()

      assert [%StreamResponse{kind: :message, message: %Message{parts: [%Part{text: t}]}}] = frames
      assert t == "direct reply"
    end
  end

  describe "history_length" do
    test "get_task with history_length: 0 returns no history", %{server: server} do
      first = open_turn(server)

      assert {:ok, %Task{history: []}} =
               DefaultHandler.get_task(server, %GetTaskRequest{id: first.id, history_length: 0})
    end

    test "get_task with history_length: 1 returns only the most recent message",
         %{server: server} do
      first = open_turn(server, "one")
      {:ok, _} = send_msg(server, req("two", task_id: first.id))

      assert {:ok, %Task{history: [_single]}} =
               DefaultHandler.get_task(server, %GetTaskRequest{id: first.id, history_length: 1})
    end

    test "get_task without history_length returns the whole history", %{server: server} do
      first = open_turn(server, "one")

      assert {:ok, %Task{history: history}} =
               DefaultHandler.get_task(server, %GetTaskRequest{id: first.id})

      assert history != []
    end

    test "send_message honours the configuration's history_length", %{server: server} do
      assert {:ok, %Task{history: []}} =
               send_msg(
                 server,
                 req("hello", configuration: %SendMessageConfiguration{history_length: 0})
               )
    end

    test "truncation is a view, not a mutation of the stored task", %{server: server} do
      first = open_turn(server)

      {:ok, %Task{history: []}} =
        DefaultHandler.get_task(server, %GetTaskRequest{id: first.id, history_length: 0})

      assert {:ok, %Task{history: [_ | _]}} =
               DefaultHandler.get_task(server, %GetTaskRequest{id: first.id})
    end
  end
end
