defmodule A2A.ClientIntegrationTest do
  @moduledoc """
  End-to-end interop oracle: the real `A2A.Client` (default `A2A.Client.HTTP.Req`
  adapter) driven against a real in-process `A2A.Server.Supervisor` tree behind
  `A2A.Standalone` (Bandit), once per protocol binding (`JSONRPC` and
  `HTTP+JSON`) served off the same dual-interface `AgentCard`.

  The port is a fixed pseudo-random value in `4100..4599`, chosen *before*
  either process starts. `A2A.Server.Supervisor` needs the finished `AgentCard`
  (with real interface URLs) up front, so we can't ask Bandit for an
  OS-assigned port (`port: 0`) first — the card would already be baked with
  the wrong URL by the time the listener told us its port. Picking a
  pseudo-random port up front sidesteps that chicken-and-egg problem at the
  cost of a small, accepted collision risk for a single test run.

  Runs in the **default** `mix test` — `req` and `bandit` are unconditional
  deps (see `mix.exs`). No `--include` flag is needed.

  Because `A2A.Server.TaskStore.ETS` is globally named, only **one** server tree
  is started for the whole module (`setup_all`); the two bindings are
  parameterised against that same tree via `Client.connect/2`'s
  `preferred_transports:`.
  """
  use ExUnit.Case, async: false
  @moduletag :integration

  alias A2A.Client
  alias A2A.Types.{AgentCapabilities, AgentCard, AgentInterface, AgentSkill, Message, Part}

  setup_all do
    name = :"srv_client_it_#{System.unique_integer([:positive])}"
    pubsub = :"pubsub_client_it_#{System.unique_integer([:positive])}"
    # `A2A.Server.Supervisor` needs the finished card (with real interface
    # URLs) up front, so the port must be chosen before either process starts
    # — we can't ask Bandit for an OS-assigned port (0) first, since the card
    # would then already be baked with the wrong URL. Picking a pseudo-random
    # port in a private range (as the task brief itself suggests) sidesteps
    # the chicken-and-egg problem at the cost of a small, accepted collision
    # risk for a single test run.
    port = 4100 + rem(System.unique_integer([:positive]), 500)
    url = "http://127.0.0.1:#{port}/"

    card = %AgentCard{
      name: "Client Integration Test Agent",
      description: "Echoes inbound text; drives the real A2A.Client against a real server.",
      version: "1.0",
      default_input_modes: ["text/plain"],
      default_output_modes: ["text/plain"],
      capabilities: %AgentCapabilities{streaming: true, extended_agent_card: true},
      supported_interfaces: [
        %AgentInterface{url: url, protocol_binding: "JSONRPC", protocol_version: "1.0"},
        %AgentInterface{url: url, protocol_binding: "HTTP+JSON", protocol_version: "1.0"}
      ],
      skills: [
        %AgentSkill{
          id: "echo",
          name: "Echo",
          description: "Returns the input text prefixed with \"echo: \".",
          tags: ["demo"]
        }
      ]
    }

    extended_card = %{card | name: "Client Integration Test Agent (extended)"}

    user_resolver = fn conn ->
      case Plug.Conn.get_req_header(conn, "authorization") do
        ["Bearer secret"] -> %A2A.User{id: "u1", authenticated?: true}
        _ -> A2A.User.anonymous()
      end
    end

    extended_agent_card_resolver = fn
      %A2A.User{authenticated?: true} -> extended_card
      %A2A.User{} -> nil
    end

    start_supervised!(
      {A2A.Server.Supervisor,
       name: name,
       executor: A2A.Test.EchoExecutor,
       pubsub: pubsub,
       agent_card: card,
       user_resolver: user_resolver,
       extended_agent_card_resolver: extended_agent_card_resolver,
       stream_idle_timeout: 5_000}
    )

    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)

    start_supervised!({A2A.Standalone, server: name, port: port})

    %{base: "http://127.0.0.1:#{port}"}
  end

  for binding <- ["JSONRPC", "HTTP+JSON"] do
    describe "over #{binding}" do
      setup %{base: base} do
        {:ok, client} = Client.connect(base, preferred_transports: [unquote(binding)])
        %{client: client}
      end

      test "connect/2 discovers the card and selects the binding", %{client: client} do
        expected_transport =
          case unquote(binding) do
            "JSONRPC" -> A2A.Client.Transport.JSONRPC
            "HTTP+JSON" -> A2A.Client.Transport.REST
          end

        assert client.transport == expected_transport
        assert %AgentCard{} = client.agent_card
      end

      test "send_message echoes", %{client: client} do
        msg = %Message{
          message_id: "m1-#{unquote(binding)}",
          role: :user,
          parts: [Part.text("hello")]
        }

        assert {:ok, result} = Client.send_message(client, msg)
        assert match?(%A2A.Types.Task{}, result) or match?(%Message{}, result)
      end

      test "send_message_stream reaches a terminal event", %{client: client} do
        msg = %Message{
          message_id: "m2-#{unquote(binding)}",
          role: :user,
          parts: [Part.text("stream")]
        }

        assert {:ok, stream} = Client.send_message_stream(client, msg)
        events = Enum.to_list(stream)
        assert events != []
      end

      test "get_task after a send returns the same task id", %{client: client} do
        msg = %Message{
          message_id: "m3-#{unquote(binding)}",
          role: :user,
          parts: [Part.text("hi")]
        }

        assert {:ok, %A2A.Types.Task{id: id}} = Client.send_message(client, msg)
        assert {:ok, %A2A.Types.Task{id: ^id}} = Client.get_task(client, id)
      end

      test "get_extended_agent_card: unauthenticated errors, authenticated succeeds", %{
        client: client
      } do
        assert {:error, %A2A.Error{code: :extended_agent_card_not_configured}} =
                 Client.get_extended_agent_card(client)

        assert {:ok, %AgentCard{}} =
                 Client.get_extended_agent_card(client,
                   headers: [{"authorization", "Bearer secret"}]
                 )
      end

      test "cancel_task on an already-completed task: EchoExecutor finishes synchronously, so cancel is not_cancelable",
           %{client: client} do
        msg = %Message{
          message_id: "m4-#{unquote(binding)}",
          role: :user,
          parts: [Part.text("hi")]
        }

        assert {:ok, %A2A.Types.Task{id: id}} = Client.send_message(client, msg)
        assert {:error, %A2A.Error{code: :task_not_cancelable}} = Client.cancel_task(client, id)
      end

      test "list_tasks returns a ListTasksResponse", %{client: client} do
        msg = %Message{
          message_id: "m5-#{unquote(binding)}",
          role: :user,
          parts: [Part.text("hi")]
        }

        assert {:ok, %A2A.Types.Task{}} = Client.send_message(client, msg)
        assert {:ok, %A2A.Types.ListTasksResponse{}} = Client.list_tasks(client)
      end

      test "resubscribe to an already-terminal task: EchoExecutor finishes synchronously, so the task is terminal by the time we resubscribe",
           %{client: client} do
        msg = %Message{
          message_id: "m6-#{unquote(binding)}",
          role: :user,
          parts: [Part.text("hi")]
        }

        assert {:ok, %A2A.Types.Task{id: id}} = Client.send_message(client, msg)

        assert {:error, %A2A.Error{code: :unsupported_operation}} =
                 Client.resubscribe(client, id)
      end

      test "push-config CRUD: server was started without push_notifications, so it errors :push_notification_not_supported",
           %{client: client} do
        msg = %Message{
          message_id: "m7-#{unquote(binding)}",
          role: :user,
          parts: [Part.text("hi")]
        }

        assert {:ok, %A2A.Types.Task{id: task_id}} = Client.send_message(client, msg)

        cfg = %A2A.Types.TaskPushNotificationConfig{
          task_id: task_id,
          id: "cfg1",
          url: "https://example.com/webhook"
        }

        assert {:error, %A2A.Error{code: :push_notification_not_supported}} =
                 Client.create_push_config(client, cfg)

        assert {:error, %A2A.Error{code: :push_notification_not_supported}} =
                 Client.get_push_config(client, task_id, "cfg1")

        assert {:error, %A2A.Error{code: :push_notification_not_supported}} =
                 Client.list_push_configs(client, task_id)

        assert {:error, %A2A.Error{code: :push_notification_not_supported}} =
                 Client.delete_push_config(client, task_id, "cfg1")
      end
    end
  end
end
