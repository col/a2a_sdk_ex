defmodule A2A.GoldenTest do
  @moduledoc """
  Golden-file round-trips: hand-written, canonical proto3-JSON (camelCase keys,
  `TASK_STATE_*`/`ROLE_*` enum strings, base64 bytes, RFC3339 `Z` timestamps)
  captured from the A2A spec examples. Asserts `decode(raw) |> encode`
  reproduces the same JSON, compared as decoded maps (key-order independent).

  These run without `protoc` and are the canonical compliance check per
  spec §8 — the differential oracle in `proto_conformance_test.exs` is a
  convenience layer on top of them, not a replacement.
  """
  use ExUnit.Case, async: true
  alias A2A.JSON

  @cases [
    {"message.json", A2A.Types.Message},
    {"task.json", A2A.Types.Task},
    {"part_file.json", A2A.Types.Part},
    {"stream_status_update.json", A2A.Types.StreamResponse},
    {"agent_card.json", A2A.Types.AgentCard},
    {"oauth2_security_scheme.json", A2A.Types.SecurityScheme},
    {"agent_card_secured.json", A2A.Types.AgentCard},
    {"task_push_notification_config.json", A2A.Types.TaskPushNotificationConfig},
    {"list_tasks_response.json", A2A.Types.ListTasksResponse}
  ]

  for {file, module} <- @cases do
    test "golden round-trip: #{file}" do
      path = Path.join([__DIR__, "..", "support", "golden", unquote(file)])
      raw = File.read!(path)
      expected = Jason.decode!(raw)
      {:ok, struct} = JSON.decode(raw, unquote(module))
      {:ok, io} = JSON.encode(struct)
      assert Jason.decode!(IO.iodata_to_binary(io)) == expected
    end
  end
end
