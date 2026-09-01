defmodule A2A.Test.Generators do
  @moduledoc """
  `StreamData` generators for the covered `A2A.Types.*` structs, restricted to
  values that are both **decode-legal** proto3-JSON and **round-trip-stable**
  through `A2A.JSON.encode/1` + `A2A.JSON.decode/2`.

  Two rules matter here and are easy to get backwards:

    1. **Implicit-presence scalar fields must be non-empty (or `nil`).** A
       proto3 field with implicit presence (the default for scalars) that
       holds its type's zero value (`""` for strings, `0` for ints, `false`
       for bools) is *omitted* on encode (see `A2A.JSON.encode_field/2`), and
       therefore decodes back to `nil`, not to the zero value. Generating an
       empty string for e.g. `Message.message_id` would produce `x` such that
       `decode(encode(x)) != x`. So: generate non-empty strings for these
       fields, or generate `nil`.

    2. **Oneof arms round-trip even when "empty."** `Part.text("")` has
       *explicit* presence (it's a proto3 `oneof` member), so it is always
       emitted and always decodes back — the empty string is fine there.

    3. **Timestamps must be whole-second.** `A2A.JSON.encode_scalar(:timestamp, _)`
       formats via `DateTime.to_iso8601/1`, which prints sub-second precision
       verbatim; `DateTime.from_unix!/1` yields whole-second `DateTime`s with
       no fractional part, so the ISO-8601 string is exact and round-trips.

    4. **`metadata`/`data` are JSON-value maps with string keys and JSON-scalar
       values** (booleans, integers, strings, or nested such maps) — anything
       Jason can round-trip byte-for-byte through `Google.Protobuf.Struct`.
  """
  import StreamData
  use ExUnitProperties

  alias A2A.Types.{
    APIKeySecurityScheme,
    Artifact,
    AuthenticationInfo,
    CancelTaskRequest,
    DeleteTaskPushNotificationConfigRequest,
    GetTaskPushNotificationConfigRequest,
    HTTPAuthSecurityScheme,
    ListTaskPushNotificationConfigsRequest,
    ListTaskPushNotificationConfigsResponse,
    ListTasksRequest,
    ListTasksResponse,
    Message,
    Part,
    SecurityScheme,
    SubscribeToTaskRequest,
    Task,
    TaskPushNotificationConfig,
    TaskStatus
  }

  @spec role() :: StreamData.t(A2A.Types.Enums.role())
  def role, do: member_of([:user, :agent])

  @spec task_state() :: StreamData.t(A2A.Types.Enums.task_state())
  def task_state do
    member_of([
      :submitted,
      :working,
      :completed,
      :failed,
      :canceled,
      :input_required,
      :rejected,
      :auth_required
    ])
  end

  @doc "A non-empty printable string — safe for implicit-presence string fields."
  @spec non_empty_string() :: StreamData.t(String.t())
  def non_empty_string, do: string(:printable, min_length: 1)

  @doc "A JSON-scalar value: boolean, integer, string, or a flat string-keyed map of such."
  @spec json_value() :: StreamData.t(term)
  def json_value do
    scalar = one_of([boolean(), integer(), string(:printable)])
    one_of([scalar, map_of(string(:alphanumeric, min_length: 1), scalar, max_length: 3)])
  end

  @doc "A metadata map: string keys, JSON-scalar values — encodes via `Google.Protobuf.Struct`."
  @spec metadata() :: StreamData.t(map)
  def metadata, do: map_of(string(:alphanumeric, min_length: 1), json_value(), max_length: 3)

  @doc "Whole-second UTC timestamp: exact under `DateTime.to_iso8601/1` round-tripping."
  @spec timestamp() :: StreamData.t(DateTime.t())
  def timestamp, do: map(integer(1_500_000_000..1_900_000_000), &DateTime.from_unix!/1)

  @doc "A `Part` in one of its four oneof arms (`text` may legally be empty)."
  @spec part() :: StreamData.t(Part.t())
  def part do
    one_of([
      map(string(:printable), &Part.text/1),
      map(binary(), &Part.raw/1),
      map(non_empty_string(), &Part.url/1),
      map(metadata(), &Part.data/1)
    ])
  end

  @spec message() :: StreamData.t(Message.t())
  def message do
    gen all(
          id <- non_empty_string(),
          r <- role(),
          parts <- list_of(part(), max_length: 3)
        ) do
      %Message{message_id: id, role: r, parts: parts}
    end
  end

  @spec artifact() :: StreamData.t(Artifact.t())
  def artifact do
    gen all(
          id <- non_empty_string(),
          parts <- list_of(part(), max_length: 3)
        ) do
      %Artifact{artifact_id: id, parts: parts}
    end
  end

  @spec task_status() :: StreamData.t(TaskStatus.t())
  def task_status do
    gen all(
          state <- task_state(),
          ts <- timestamp()
        ) do
      %TaskStatus{state: state, timestamp: ts}
    end
  end

  @spec task() :: StreamData.t(Task.t())
  def task do
    gen all(
          id <- non_empty_string(),
          status <- task_status(),
          artifacts <- list_of(artifact(), max_length: 2),
          history <- list_of(message(), max_length: 2)
        ) do
      %Task{id: id, status: status, artifacts: artifacts, history: history}
    end
  end

  @doc """
  A `SecurityScheme` restricted to arms whose leaf structs have only scalar
  fields with non-empty values, so the round-trip stays stable — no
  empty-map/implicit-presence pitfalls.
  """
  @spec security_scheme() :: StreamData.t(A2A.Types.SecurityScheme.t())
  def security_scheme do
    one_of([
      map(non_empty_string(), fn n ->
        SecurityScheme.api_key(%APIKeySecurityScheme{location: "header", name: n})
      end),
      map(non_empty_string(), fn s ->
        SecurityScheme.http_auth(%HTTPAuthSecurityScheme{scheme: s})
      end)
    ])
  end

  @doc "An optional positive int — safe for implicit-presence int32 fields (zero would be omitted)."
  @spec positive_int() :: StreamData.t(integer() | nil)
  def positive_int, do: one_of([constant(nil), integer(1..1_000_000)])

  @doc "An optional int incl. 0 — safe for explicit-presence int32 fields (always emitted)."
  @spec optional_int() :: StreamData.t(integer() | nil)
  def optional_int, do: one_of([constant(nil), integer(0..1_000_000)])

  @doc "An optional non-empty string — safe for implicit-presence string fields."
  @spec optional_string() :: StreamData.t(String.t() | nil)
  def optional_string, do: one_of([constant(nil), non_empty_string()])

  @spec authentication_info() :: StreamData.t(A2A.Types.AuthenticationInfo.t())
  def authentication_info do
    gen all(scheme <- optional_string(), credentials <- optional_string()) do
      %AuthenticationInfo{scheme: scheme, credentials: credentials}
    end
  end

  @spec task_push_notification_config() :: StreamData.t(TaskPushNotificationConfig.t())
  def task_push_notification_config do
    gen all(
          tenant <- optional_string(),
          id <- optional_string(),
          task_id <- optional_string(),
          url <- optional_string(),
          token <- optional_string(),
          auth <- one_of([constant(nil), authentication_info()])
        ) do
      %TaskPushNotificationConfig{
        tenant: tenant,
        id: id,
        task_id: task_id,
        url: url,
        token: token,
        authentication: auth
      }
    end
  end

  @spec get_task_push_notification_config_request() ::
          StreamData.t(GetTaskPushNotificationConfigRequest.t())
  def get_task_push_notification_config_request do
    gen all(tenant <- optional_string(), task_id <- optional_string(), id <- optional_string()) do
      %GetTaskPushNotificationConfigRequest{tenant: tenant, task_id: task_id, id: id}
    end
  end

  @spec delete_task_push_notification_config_request() ::
          StreamData.t(DeleteTaskPushNotificationConfigRequest.t())
  def delete_task_push_notification_config_request do
    gen all(tenant <- optional_string(), task_id <- optional_string(), id <- optional_string()) do
      %DeleteTaskPushNotificationConfigRequest{tenant: tenant, task_id: task_id, id: id}
    end
  end

  @spec list_task_push_notification_configs_request() ::
          StreamData.t(ListTaskPushNotificationConfigsRequest.t())
  def list_task_push_notification_configs_request do
    gen all(
          task_id <- optional_string(),
          page_size <- positive_int(),
          page_token <- optional_string(),
          tenant <- optional_string()
        ) do
      %ListTaskPushNotificationConfigsRequest{
        task_id: task_id,
        page_size: page_size,
        page_token: page_token,
        tenant: tenant
      }
    end
  end

  @spec list_task_push_notification_configs_response() ::
          StreamData.t(ListTaskPushNotificationConfigsResponse.t())
  def list_task_push_notification_configs_response do
    gen all(
          configs <- list_of(task_push_notification_config(), max_length: 2),
          next <- optional_string()
        ) do
      %ListTaskPushNotificationConfigsResponse{configs: configs, next_page_token: next}
    end
  end

  @spec list_tasks_request() :: StreamData.t(ListTasksRequest.t())
  def list_tasks_request do
    gen all(
          tenant <- optional_string(),
          context_id <- optional_string(),
          status <- one_of([constant(nil), task_state()]),
          page_size <- optional_int(),
          page_token <- optional_string(),
          history_length <- optional_int(),
          ts <- one_of([constant(nil), timestamp()]),
          include_artifacts <- one_of([constant(nil), boolean()])
        ) do
      %ListTasksRequest{
        tenant: tenant,
        context_id: context_id,
        status: status,
        page_size: page_size,
        page_token: page_token,
        history_length: history_length,
        status_timestamp_after: ts,
        include_artifacts: include_artifacts
      }
    end
  end

  @spec list_tasks_response() :: StreamData.t(ListTasksResponse.t())
  def list_tasks_response do
    gen all(
          tasks <- list_of(task(), max_length: 2),
          next <- optional_string(),
          page_size <- positive_int(),
          total_size <- positive_int()
        ) do
      %ListTasksResponse{
        tasks: tasks,
        next_page_token: next,
        page_size: page_size,
        total_size: total_size
      }
    end
  end

  @spec cancel_task_request() :: StreamData.t(CancelTaskRequest.t())
  def cancel_task_request do
    gen all(
          tenant <- optional_string(),
          id <- optional_string(),
          metadata <-
            one_of([constant(nil), map(metadata(), fn m -> if m == %{}, do: nil, else: m end)])
        ) do
      %CancelTaskRequest{tenant: tenant, id: id, metadata: metadata}
    end
  end

  @spec subscribe_to_task_request() :: StreamData.t(SubscribeToTaskRequest.t())
  def subscribe_to_task_request do
    gen all(tenant <- optional_string(), id <- optional_string()) do
      %SubscribeToTaskRequest{tenant: tenant, id: id}
    end
  end

  @doc """
  A valid `A2A.Test.ReplayExecutor` script: zero or more intermediate steps
  (`{:status, :working | :auth_required}`, `{:artifact, text}`) followed by
  exactly one step that ends the turn (`{:status, last_state}`) — one of the four
  terminal states, or `input_required`, which parks the task instead.
  """
  @spec valid_event_script() :: StreamData.t([{:status, atom()} | {:artifact, String.t()}])
  def valid_event_script do
    intermediate_step =
      one_of([
        map(non_empty_string(), &{:artifact, &1}),
        member_of([{:status, :working}, {:status, :auth_required}])
      ])

    # NOT all terminal states: `input_required` is an *interrupted* state, which ends
    # a turn (and a blocking wait, §3.2.2) without ending the task or its streams
    # (§3.1.2, §3.1.6). The mix is deliberate — do not collapse the two sets.
    last_state = member_of([:completed, :failed, :canceled, :rejected, :input_required])

    gen all(
          steps <- list_of(intermediate_step, max_length: 5),
          last <- last_state
        ) do
      steps ++ [{:status, last}]
    end
  end
end
