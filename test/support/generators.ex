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
    HTTPAuthSecurityScheme,
    Message,
    Part,
    SecurityScheme,
    Task,
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
end
