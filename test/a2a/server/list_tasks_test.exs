defmodule A2A.Server.ListTasksTest do
  use ExUnit.Case, async: false

  alias A2A.Server.DefaultHandler
  alias A2A.Server.TaskStore.ETS
  alias A2A.Types.{Artifact, ListTasksRequest, ListTasksResponse, Message, Part, Task, TaskStatus}

  setup do
    # A minimal server handle pointing at the ETS store + default scope. The ETS
    # table is globally named, so ensure it's started (idempotent across tests
    # that already have a supervision tree running) before clearing it.
    case start_supervised(ETS) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    server = %A2A.Server{
      name: :list_test,
      store: ETS,
      scope: A2A.Scope.default(),
      id_generator: &A2A.Server.default_id/0
    }

    # Clear any prior rows for determinism.
    :ets.delete_all_objects(ETS)
    %{server: server}
  end

  defp put(server, id, ts, opts \\ []) do
    task = %Task{
      id: id,
      context_id: Keyword.get(opts, :context_id, "c"),
      status: %TaskStatus{state: Keyword.get(opts, :state, :working), timestamp: ts},
      history: Keyword.get(opts, :history, []),
      artifacts: Keyword.get(opts, :artifacts, [])
    }

    :ok = ETS.save(task, server.scope)
  end

  test "orders by status timestamp descending, id tiebreak", %{server: server} do
    put(server, "a", ~U[2026-01-01 00:00:01Z])
    put(server, "b", ~U[2026-01-01 00:00:03Z])
    put(server, "c", ~U[2026-01-01 00:00:02Z])

    {:ok, %ListTasksResponse{tasks: tasks, total_size: 3}} =
      DefaultHandler.list_tasks(server, %ListTasksRequest{})

    assert Enum.map(tasks, & &1.id) == ["b", "c", "a"]
  end

  test "paginates with an opaque cursor; last page has empty next_page_token", %{server: server} do
    for i <- 1..5, do: put(server, "t#{i}", DateTime.from_unix!(1_700_000_000 + i))
    {:ok, page1} = DefaultHandler.list_tasks(server, %ListTasksRequest{page_size: 2})
    assert length(page1.tasks) == 2
    assert page1.next_page_token != ""
    assert page1.total_size == 5

    {:ok, page2} =
      DefaultHandler.list_tasks(server, %ListTasksRequest{
        page_size: 2,
        page_token: page1.next_page_token
      })

    assert length(page2.tasks) == 2

    {:ok, page3} =
      DefaultHandler.list_tasks(server, %ListTasksRequest{
        page_size: 2,
        page_token: page2.next_page_token
      })

    assert length(page3.tasks) == 1
    assert page3.next_page_token == ""

    ids = Enum.flat_map([page1, page2, page3], fn p -> Enum.map(p.tasks, & &1.id) end)
    assert Enum.sort(ids) == Enum.sort(for i <- 1..5, do: "t#{i}")
    assert length(Enum.uniq(ids)) == 5
  end

  test "clamps page_size to 1..100", %{server: server} do
    for i <- 1..3, do: put(server, "t#{i}", DateTime.from_unix!(1_700_000_000 + i))
    {:ok, p} = DefaultHandler.list_tasks(server, %ListTasksRequest{page_size: 0})
    assert length(p.tasks) == 1
  end

  test "filters by context_id and status", %{server: server} do
    put(server, "a", ~U[2026-01-01 00:00:01Z], context_id: "x", state: :working)
    put(server, "b", ~U[2026-01-01 00:00:02Z], context_id: "y", state: :completed)
    {:ok, p} = DefaultHandler.list_tasks(server, %ListTasksRequest{context_id: "x"})
    assert Enum.map(p.tasks, & &1.id) == ["a"]
    {:ok, q} = DefaultHandler.list_tasks(server, %ListTasksRequest{status: :completed})
    assert Enum.map(q.tasks, & &1.id) == ["b"]
  end

  test "history_length truncates to most recent; include_artifacts drops by default", %{
    server: server
  } do
    msgs =
      for n <- 1..3, do: %Message{message_id: "m#{n}", role: :agent, parts: [Part.text("#{n}")]}

    art = %Artifact{artifact_id: "art1", parts: [Part.text("x")]}
    put(server, "a", ~U[2026-01-01 00:00:01Z], history: msgs, artifacts: [art])

    {:ok, %{tasks: [t]}} =
      DefaultHandler.list_tasks(server, %ListTasksRequest{history_length: 2})

    assert Enum.map(t.history, & &1.message_id) == ["m2", "m3"]
    assert t.artifacts == []

    {:ok, %{tasks: [t2]}} =
      DefaultHandler.list_tasks(server, %ListTasksRequest{include_artifacts: true})

    assert Enum.map(t2.artifacts, & &1.artifact_id) == ["art1"]
  end

  test "garbage page_token errors", %{server: server} do
    assert {:error, %A2A.Error{}} =
             DefaultHandler.list_tasks(server, %ListTasksRequest{page_token: "!!!not-base64!!!"})
  end

  test "equal timestamps order by id ascending", %{server: server} do
    ts = ~U[2026-01-01 00:00:00Z]
    put(server, "c", ts)
    put(server, "a", ts)
    put(server, "b", ts)

    {:ok, %ListTasksResponse{tasks: tasks}} =
      DefaultHandler.list_tasks(server, %ListTasksRequest{})

    assert Enum.map(tasks, & &1.id) == ["a", "b", "c"]
  end

  test "cursor split mid-tie yields no duplicates and no gaps", %{server: server} do
    ts = ~U[2026-01-01 00:00:00Z]
    for id <- ["c", "a", "b", "e", "d"], do: put(server, id, ts)

    {:ok, page1} = DefaultHandler.list_tasks(server, %ListTasksRequest{page_size: 2})
    assert Enum.map(page1.tasks, & &1.id) == ["a", "b"]
    assert page1.next_page_token != ""

    {:ok, page2} =
      DefaultHandler.list_tasks(server, %ListTasksRequest{
        page_size: 2,
        page_token: page1.next_page_token
      })

    assert Enum.map(page2.tasks, & &1.id) == ["c", "d"]

    {:ok, page3} =
      DefaultHandler.list_tasks(server, %ListTasksRequest{
        page_size: 2,
        page_token: page2.next_page_token
      })

    assert Enum.map(page3.tasks, & &1.id) == ["e"]
    assert page3.next_page_token == ""

    ids = Enum.flat_map([page1, page2, page3], fn p -> Enum.map(p.tasks, & &1.id) end)
    assert Enum.sort(ids) == ["a", "b", "c", "d", "e"]
    assert length(Enum.uniq(ids)) == 5
  end

  test "negative history_length behaves like unbounded (no crash)", %{server: server} do
    msgs =
      for n <- 1..3, do: %Message{message_id: "m#{n}", role: :agent, parts: [Part.text("#{n}")]}

    put(server, "a", ~U[2026-01-01 00:00:01Z], history: msgs)

    {:ok, %{tasks: [t]}} =
      DefaultHandler.list_tasks(server, %ListTasksRequest{history_length: -1})

    assert Enum.map(t.history, & &1.message_id) == ["m1", "m2", "m3"]
  end
end
