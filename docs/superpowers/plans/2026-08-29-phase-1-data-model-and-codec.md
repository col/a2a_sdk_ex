# Phase 1 — Data model & `A2A.JSON` codec — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the typed foundation of the A2A Elixir SDK — hand-written idiomatic structs for the Phase 1 core task/message flow, the field-spec-driven `A2A.JSON` proto3-JSON codec, and the complete test-only proto-validation harness.

**Architecture:** Each `A2A.Types.*` struct carries an internal **field spec** (`__a2a_fields__/0` returning `[%A2A.Types.Field{}]`) that maps struct field ⇄ proto field name/number/wire-type/cardinality/oneof. A single generic `A2A.JSON` codec is driven entirely by these specs (no per-struct encode/decode). A test-only harness generates throwaway proto modules with `protoc` and uses them as a differential oracle, enforcing a **coverage partition** so phasing is provably complete.

**Tech Stack:** Elixir (`~> 1.14`), `jason` (runtime), `stream_data`/`protobuf`/`google_protos`/`ex_doc`/`credo`/`dialyxir` (dev/test), `protoc` + `protoc-gen-elixir` (dev/CI only, never shipped).

**Spec:** [`docs/superpowers/specs/2026-08-29-data-model-and-codec-design.md`](../specs/2026-08-29-data-model-and-codec-design.md)

## Global Constraints

- **Authoritative proto:** `a2aproject/a2a` → `specification/a2a.proto`, package `lf.a2a.v1`, pinned at commit `cfc9d34bc41e368827eb6446d31f912e44f795c5`. Recorded in `priv/proto/PROTO_VERSION`.
- **Full v1.0 surface = 44 messages + 2 enums.** Phase 1 covers **12 messages + 2 enums**; the other **32 messages** are on the `@deferred` manifest (Phases 2–4). Enums are fully covered in Phase 1.
- **`Part` modeling = Option A (proto-faithful):** `kind: :text | :raw | :url | :data`; each proto oneof arm (`text`/`raw`/`url`/`data`) maps 1:1 to its own struct field. No `:file` grouping.
- **Enum atoms** (`A2A.Types.Enums`): `TaskState` → `:submitted | :working | :completed | :failed | :canceled | :input_required | :rejected | :auth_required` (note US spelling `:canceled`, one L → `"TASK_STATE_CANCELED"`). `Role` → `:user | :agent`.
- **`_UNSPECIFIED` (zero) values** are never stored as atoms, rejected on decode, never emitted on encode.
- **snake_case** struct fields; JSON keys are lowerCamelCase; decode accepts both camelCase and snake_case keys, and both enum name strings and integers.
- **Runtime dep graph = `jason` only.** Nothing in this feature starts a process or opens a socket.
- **`mix test` is green with NO proto toolchain.** All proto-oracle tests are `@tag :proto` and excluded by default; CI runs them in a separate `--only proto` job.
- **`mix a2a.gen_proto` is a manual/CI step, never part of `mix compile`.** Generated modules land in `test/support/gen/` (git-ignored).
- **Elixir version floor `~> 1.14`** (matches CI's minimum; newer is fine).

---

## File structure

**Library (`lib/`, ships):**
- `lib/a2a.ex` — top-level `@moduledoc` only.
- `lib/a2a/types/field.ex` — `A2A.Types.Field` field-spec struct.
- `lib/a2a/types/enums.ex` — `TaskState`/`Role` atom ⇄ proto mappings.
- `lib/a2a/types/message.ex`, `task.ex`, `task_status.ex`, `part.ex`, `artifact.ex` — core types.
- `lib/a2a/types/events.ex` — `TaskStatusUpdateEvent`, `TaskArtifactUpdateEvent`, `StreamResponse`.
- `lib/a2a/types/requests.ex` — `SendMessageRequest`, `SendMessageResponse`, `SendMessageConfiguration`, `GetTaskRequest`.
- `lib/a2a/json.ex` — the codec (public `encode/1`, `decode/2`; low-level `to_json_map/1`, `from_json_map/2`).
- `lib/a2a/json/naming.ex` — snake_case ⇄ camelCase.
- `lib/mix/tasks/a2a.gen_proto.ex` — codegen task (dev/CI).

**Harness (`test/support/`, `priv/proto/`, never ships):**
- `priv/proto/a2a.proto`, `priv/proto/google/**`, `priv/proto/PROTO_VERSION` — vendored.
- `test/support/coverage.ex` — `A2A.Test.Coverage` manifest (`@deferred` + derived `covered`).
- `test/support/generators.ex` — `stream_data` generators for covered types.
- `test/support/fixtures.ex` — representative instances.
- `test/support/golden/*.json` — golden files.
- `test/support/gen/` — generated proto modules (git-ignored).

**Tests:** `test/a2a/types/*_test.exs`, `test/a2a/json_test.exs`, `test/a2a/json/naming_test.exs`, `test/support/coverage_test.exs`, `test/a2a/proto_conformance_test.exs` (`:proto`).

---

## Wire-type vocabulary (used by every `%A2A.Types.Field{}`)

`type` is one of:
`:string | :bool | :int32 | :int64 | :bytes | :timestamp | :struct | :value | :raw | {:enum, :task_state | :role} | {:message, module}`

- `:struct` = `google.protobuf.Struct` ⇄ plain Elixir `map()` (string keys).
- `:value` = `google.protobuf.Value` ⇄ any JSON term.
- `:raw` = passthrough JSON term (used only for `SendMessageConfiguration.task_push_notification_config`, whose message type is a Phase-4 struct not built here — see Task 8).
- `:timestamp` ⇄ `DateTime.t()` (UTC).
- `:bytes` ⇄ `binary()`.

`cardinality`: `:singular | :repeated`. `presence`: `:implicit | :explicit`. `oneof`: `nil | {group_atom, tag_value}`.

**Encode omission rule:** a field is omitted from JSON when its value is `nil`, OR (`presence == :implicit` AND value equals the proto default for its type: `""`, `false`, `0`, `[]`). `presence: :explicit` fields (oneof arms; `optional int32` fields) are emitted whenever non-`nil`, even at default. Oneof arms are always `presence: :explicit`, so exactly the active arm (the only non-`nil` one) is emitted.

---

### Task 1: Project scaffolding & tooling

**Files:**
- Create: `mix.exs`, `.formatter.exs`, `.gitignore`, `.credo.exs`, `lib/a2a.ex`, `test/test_helper.exs`, `test/a2a_test.exs`, `.github/workflows/ci.yml`
- Test: `test/a2a_test.exs`

**Interfaces:**
- Consumes: nothing.
- Produces: a compiling `:a2a` mix project (module namespace `A2A`), `mix test` green, `mix format --check-formatted` clean, `mix credo` clean, ExDoc buildable.

- [ ] **Step 1: Write `mix.exs`**

```elixir
defmodule A2A.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/col/a2a_sdk_ex"

  def project do
    [
      app: :a2a,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:mix]],
      name: "A2A",
      description: "Elixir SDK for building A2A (Agent2Agent) compliant agents.",
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExUnit],
      preferred_cli_env: ["test.proto": :test]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:stream_data, "~> 1.1", only: :test},
      {:protobuf, "~> 0.14", only: [:dev, :test], runtime: false},
      {:google_protos, "~> 0.4", only: [:dev, :test]},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    ["test.proto": ["test --only proto"]]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv/proto/PROTO_VERSION mix.exs README.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: ["README.md", "docs/superpowers/specs/2026-08-29-data-model-and-codec-design.md"]
    ]
  end
end
```

- [ ] **Step 2: Write `.formatter.exs`, `.gitignore`, `.credo.exs`, `lib/a2a.ex`, `test/test_helper.exs`, `test/a2a_test.exs`**

`.formatter.exs`:
```elixir
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  line_length: 100
]
```

`.gitignore` (append; create if absent):
```
/_build/
/cover/
/deps/
/doc/
/.elixir_ls/
erl_crash.dump
*.ez
a2a-*.tar
/test/support/gen/
```

`.credo.exs`: use the default template — `mix credo gen.config` output is acceptable; if generating by hand, a minimal `%{configs: [%{name: "default", files: %{included: ["lib/", "test/"]}, strict: true}]}` is fine. Ensure `mix credo --strict` passes on the empty project.

`lib/a2a.ex`:
```elixir
defmodule A2A do
  @moduledoc """
  Elixir SDK for building A2A (Agent2Agent) compliant agents.

  Phase 1 provides the typed data model (`A2A.Types.*`) and the
  `A2A.JSON` proto3-JSON codec.
  """
end
```

`test/test_helper.exs`:
```elixir
ExUnit.start(exclude: [:proto])
```

`test/a2a_test.exs`:
```elixir
defmodule A2ATest do
  use ExUnit.Case, async: true

  test "module is defined" do
    assert Code.ensure_loaded?(A2A)
  end
end
```

- [ ] **Step 3: Fetch deps and verify the project compiles and tests pass**

Run:
```bash
mix local.hex --force && mix local.rebar --force
mix deps.get
mix compile --warnings-as-errors
mix test
mix format --check-formatted
mix credo --strict
```
Expected: deps resolve; compile clean; 1 test passes; format clean; credo clean.

- [ ] **Step 4: Write `.github/workflows/ci.yml`**

Two jobs. `test` (no toolchain): `mix deps.get`, `mix format --check-formatted`, `mix credo --strict`, `mix compile --warnings-as-errors`, `mix test`, `mix dialyzer`. `proto` (separate job): `apt-get install -y protobuf-compiler`, `mix escript.install --force hex protobuf`, `mix a2a.gen_proto`, `mix test --only proto`.

```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with: {otp-version: "26", elixir-version: "1.16"}
      - run: mix deps.get
      - run: mix format --check-formatted
      - run: mix credo --strict
      - run: mix compile --warnings-as-errors
      - run: mix test
      - run: mix dialyzer
  proto:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with: {otp-version: "26", elixir-version: "1.16"}
      - run: sudo apt-get update && sudo apt-get install -y protobuf-compiler
      - run: mix deps.get
      - run: mix escript.install --force hex protobuf
      - run: echo "$HOME/.mix/escripts" >> $GITHUB_PATH
      - run: mix a2a.gen_proto
      - run: mix test --only proto
```

- [ ] **Step 5: Commit**

```bash
git add mix.exs .formatter.exs .gitignore .credo.exs lib/a2a.ex test/ .github/
git commit -m "chore: scaffold :a2a mix project with tooling and CI"
```

---

### Task 2: Field spec, naming, and enums

**Files:**
- Create: `lib/a2a/types/field.ex`, `lib/a2a/json/naming.ex`, `lib/a2a/types/enums.ex`
- Test: `test/a2a/json/naming_test.exs`, `test/a2a/types/enums_test.exs`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `%A2A.Types.Field{name, proto_name, json_name, number, type, cardinality, presence, oneof}` and helper `A2A.Types.Field.new/1`.
  - `A2A.JSON.Naming.to_camel(binary) :: binary`.
  - `A2A.Types.Enums.encode(:task_state | :role, atom) :: {:ok, String.t()} | {:error, term}` and `encode!/2`.
  - `A2A.Types.Enums.decode(:task_state | :role, String.t() | integer) :: {:ok, atom} | {:error, term}`.
  - `A2A.Types.Enums.proto_names() :: [String.t()]` → `["TaskState", "Role"]` (for the coverage manifest).

- [ ] **Step 1: Write the failing naming test**

```elixir
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/a2a/json/naming_test.exs`
Expected: FAIL (`A2A.JSON.Naming` undefined).

- [ ] **Step 3: Implement `A2A.JSON.Naming`**

```elixir
defmodule A2A.JSON.Naming do
  @moduledoc false

  @doc "Converts a snake_case proto field name to lowerCamelCase (proto3-JSON key)."
  @spec to_camel(binary) :: binary
  def to_camel(snake) when is_binary(snake) do
    case String.split(snake, "_") do
      [first | rest] -> first <> Enum.map_join(rest, "", &String.capitalize/1)
    end
  end
end
```

- [ ] **Step 4: Run naming test to verify it passes**

Run: `mix test test/a2a/json/naming_test.exs`
Expected: PASS.

- [ ] **Step 5: Write `A2A.Types.Field`**

```elixir
defmodule A2A.Types.Field do
  @moduledoc false

  @enforce_keys [:name, :proto_name, :number, :type]
  defstruct [
    :name,
    :proto_name,
    :json_name,
    :number,
    :type,
    cardinality: :singular,
    presence: :implicit,
    oneof: nil
  ]

  @type wire ::
          :string
          | :bool
          | :int32
          | :int64
          | :bytes
          | :timestamp
          | :struct
          | :value
          | :raw
          | {:enum, :task_state | :role}
          | {:message, module}

  @type t :: %__MODULE__{
          name: atom,
          proto_name: String.t(),
          json_name: String.t(),
          number: pos_integer,
          type: wire,
          cardinality: :singular | :repeated,
          presence: :implicit | :explicit,
          oneof: nil | {atom, atom}
        }

  @doc "Builds a field spec, deriving `json_name` from `proto_name` when omitted."
  @spec new(keyword) :: t
  def new(opts) do
    proto_name = Keyword.fetch!(opts, :proto_name)
    opts = Keyword.put_new(opts, :json_name, A2A.JSON.Naming.to_camel(proto_name))
    struct!(__MODULE__, opts)
  end
end
```

- [ ] **Step 6: Write the failing enums test**

```elixir
defmodule A2A.Types.EnumsTest do
  use ExUnit.Case, async: true
  alias A2A.Types.Enums

  test "encodes task_state atoms to SCREAMING_SNAKE proto names" do
    assert Enums.encode(:task_state, :input_required) == {:ok, "TASK_STATE_INPUT_REQUIRED"}
    assert Enums.encode(:task_state, :canceled) == {:ok, "TASK_STATE_CANCELED"}
    assert Enums.encode(:role, :user) == {:ok, "ROLE_USER"}
  end

  test "decodes proto names and integers, both directions" do
    assert Enums.decode(:task_state, "TASK_STATE_WORKING") == {:ok, :working}
    assert Enums.decode(:task_state, 8) == {:ok, :auth_required}
    assert Enums.decode(:role, "ROLE_AGENT") == {:ok, :agent}
  end

  test "rejects UNSPECIFIED / zero and unknown values" do
    assert {:error, _} = Enums.decode(:task_state, "TASK_STATE_UNSPECIFIED")
    assert {:error, _} = Enums.decode(:task_state, 0)
    assert {:error, _} = Enums.decode(:role, "ROLE_BOGUS")
    assert {:error, _} = Enums.encode(:task_state, :bogus)
  end

  test "lists proto enum type names for the coverage manifest" do
    assert Enum.sort(Enums.proto_names()) == ["Role", "TaskState"]
  end
end
```

- [ ] **Step 7: Run enums test to verify it fails**

Run: `mix test test/a2a/types/enums_test.exs`
Expected: FAIL (`A2A.Types.Enums` undefined).

- [ ] **Step 8: Implement `A2A.Types.Enums`**

```elixir
defmodule A2A.Types.Enums do
  @moduledoc "Atom ⇄ proto3-JSON mappings for the A2A enums."

  @enums %{
    task_state: %{
      submitted: {1, "TASK_STATE_SUBMITTED"},
      working: {2, "TASK_STATE_WORKING"},
      completed: {3, "TASK_STATE_COMPLETED"},
      failed: {4, "TASK_STATE_FAILED"},
      canceled: {5, "TASK_STATE_CANCELED"},
      input_required: {6, "TASK_STATE_INPUT_REQUIRED"},
      rejected: {7, "TASK_STATE_REJECTED"},
      auth_required: {8, "TASK_STATE_AUTH_REQUIRED"}
    },
    role: %{
      user: {1, "ROLE_USER"},
      agent: {2, "ROLE_AGENT"}
    }
  }

  @proto_type_names %{task_state: "TaskState", role: "Role"}

  @spec proto_names() :: [String.t()]
  def proto_names, do: Map.values(@proto_type_names)

  @spec atoms(atom) :: [atom]
  def atoms(enum), do: Map.keys(Map.fetch!(@enums, enum))

  @spec encode(atom, atom) :: {:ok, String.t()} | {:error, term}
  def encode(enum, atom) do
    case @enums |> Map.fetch!(enum) |> Map.get(atom) do
      {_num, name} -> {:ok, name}
      nil -> {:error, {:unknown_enum_value, enum, atom}}
    end
  end

  @spec encode!(atom, atom) :: String.t()
  def encode!(enum, atom) do
    case encode(enum, atom) do
      {:ok, name} -> name
      {:error, reason} -> raise ArgumentError, "invalid #{enum}: #{inspect(reason)}"
    end
  end

  @spec decode(atom, String.t() | integer) :: {:ok, atom} | {:error, term}
  def decode(enum, value) do
    table = Map.fetch!(@enums, enum)

    match =
      Enum.find(table, fn
        {_atom, {num, name}} -> value == num or value == name
      end)

    case match do
      {atom, _} -> {:ok, atom}
      nil -> {:error, {:unknown_enum_value, enum, value}}
    end
  end
end
```

- [ ] **Step 9: Run all tests to verify they pass**

Run: `mix test test/a2a/json/naming_test.exs test/a2a/types/enums_test.exs`
Expected: PASS. Then `mix format` and `mix credo --strict`.

- [ ] **Step 10: Commit**

```bash
git add lib/a2a/types/field.ex lib/a2a/json/naming.ex lib/a2a/types/enums.ex test/a2a
git commit -m "feat: add field spec, camelCase naming, and A2A enums"
```

---

### Task 3: `A2A.Types.Part`

**Files:**
- Create: `lib/a2a/types/part.ex`
- Test: `test/a2a/types/part_test.exs`

**Interfaces:**
- Consumes: `A2A.Types.Field`.
- Produces:
  - `%A2A.Types.Part{kind, text, raw, url, data, metadata, filename, media_type}`.
  - Constructors `Part.text/2`, `Part.raw/2`, `Part.url/2`, `Part.data/2` (2nd arg = keyword opts `:metadata`, `:filename`, `:media_type`).
  - `Part.__a2a_fields__/0 :: [Field.t()]`, `Part.__a2a_proto_name__/0 :: "Part"`, `Part.__a2a_discriminator__/0 :: :kind`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule A2A.Types.PartTest do
  use ExUnit.Case, async: true
  alias A2A.Types.Part

  test "text/2 builds a :text part" do
    p = Part.text("hello", metadata: %{"a" => 1})
    assert %Part{kind: :text, text: "hello", metadata: %{"a" => 1}} = p
    assert p.raw == nil and p.url == nil and p.data == nil
  end

  test "raw/2 builds a :raw part with filename and media_type" do
    p = Part.raw(<<1, 2, 3>>, filename: "a.bin", media_type: "application/octet-stream")
    assert %Part{kind: :raw, raw: <<1, 2, 3>>, filename: "a.bin", media_type: "application/octet-stream"} = p
  end

  test "url/2 and data/2" do
    assert %Part{kind: :url, url: "https://x/y"} = Part.url("https://x/y")
    assert %Part{kind: :data, data: %{"k" => "v"}} = Part.data(%{"k" => "v"})
  end

  test "field spec maps every proto field with oneof grouping" do
    by_name = Map.new(Part.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "text", number: 1, type: :string, oneof: {:content, :text}, presence: :explicit} =
             by_name.text
    assert %{proto_name: "raw", number: 2, type: :bytes, oneof: {:content, :raw}} = by_name.raw
    assert %{proto_name: "url", number: 3, type: :string, oneof: {:content, :url}} = by_name.url
    assert %{proto_name: "data", number: 4, type: :value, oneof: {:content, :data}} = by_name.data
    assert %{proto_name: "metadata", number: 5, type: :struct, oneof: nil} = by_name.metadata
    assert %{proto_name: "filename", number: 6, type: :string} = by_name.filename
    assert %{proto_name: "media_type", number: 7, type: :string, json_name: "mediaType"} = by_name.media_type
    assert Part.__a2a_proto_name__() == "Part"
    assert Part.__a2a_discriminator__() == :kind
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/a2a/types/part_test.exs`
Expected: FAIL (`A2A.Types.Part` undefined).

- [ ] **Step 3: Implement `A2A.Types.Part`**

```elixir
defmodule A2A.Types.Part do
  @moduledoc """
  A message/artifact part: a tagged union over `text | raw | url | data`.
  Match on `:kind` for exhaustive handling.
  """
  alias A2A.Types.Field

  @type kind :: :text | :raw | :url | :data
  @type t :: %__MODULE__{
          kind: kind,
          text: String.t() | nil,
          raw: binary() | nil,
          url: String.t() | nil,
          data: term() | nil,
          metadata: map() | nil,
          filename: String.t() | nil,
          media_type: String.t() | nil
        }

  defstruct [:kind, :text, :raw, :url, :data, :metadata, :filename, :media_type]

  @spec text(String.t(), keyword) :: t
  def text(text, opts \\ []), do: build(:text, [text: text], opts)

  @spec raw(binary, keyword) :: t
  def raw(bytes, opts \\ []), do: build(:raw, [raw: bytes], opts)

  @spec url(String.t(), keyword) :: t
  def url(url, opts \\ []), do: build(:url, [url: url], opts)

  @spec data(term, keyword) :: t
  def data(data, opts \\ []), do: build(:data, [data: data], opts)

  defp build(kind, arm, opts) do
    fields =
      [kind: kind]
      |> Keyword.merge(arm)
      |> Keyword.merge(Keyword.take(opts, [:metadata, :filename, :media_type]))

    struct!(__MODULE__, fields)
  end

  @doc false
  def __a2a_proto_name__, do: "Part"
  @doc false
  def __a2a_discriminator__, do: :kind

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :text, proto_name: "text", number: 1, type: :string, presence: :explicit, oneof: {:content, :text}),
      Field.new(name: :raw, proto_name: "raw", number: 2, type: :bytes, presence: :explicit, oneof: {:content, :raw}),
      Field.new(name: :url, proto_name: "url", number: 3, type: :string, presence: :explicit, oneof: {:content, :url}),
      Field.new(name: :data, proto_name: "data", number: 4, type: :value, presence: :explicit, oneof: {:content, :data}),
      Field.new(name: :metadata, proto_name: "metadata", number: 5, type: :struct),
      Field.new(name: :filename, proto_name: "filename", number: 6, type: :string),
      Field.new(name: :media_type, proto_name: "media_type", number: 7, type: :string)
    ]
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/a2a/types/part_test.exs`
Expected: PASS. Then `mix format`, `mix credo --strict`.

- [ ] **Step 5: Commit**

```bash
git add lib/a2a/types/part.ex test/a2a/types/part_test.exs
git commit -m "feat: add A2A.Types.Part tagged union"
```

---

### Task 4: `A2A.Types.Message` and `A2A.Types.Artifact`

**Files:**
- Create: `lib/a2a/types/message.ex`, `lib/a2a/types/artifact.ex`
- Test: `test/a2a/types/message_test.exs`, `test/a2a/types/artifact_test.exs`

**Interfaces:**
- Consumes: `A2A.Types.Field`, `A2A.Types.Part`.
- Produces:
  - `%A2A.Types.Message{message_id, context_id, task_id, role, parts, metadata, extensions, reference_task_ids}` + `__a2a_fields__/0` + `__a2a_proto_name__/0 :: "Message"`.
  - `%A2A.Types.Artifact{artifact_id, name, description, parts, metadata, extensions}` + `__a2a_fields__/0` + `__a2a_proto_name__/0 :: "Artifact"`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule A2A.Types.MessageTest do
  use ExUnit.Case, async: true
  alias A2A.Types.{Message, Part}

  test "constructs a message and exposes its field spec" do
    m = %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}
    assert m.message_id == "m1" and m.role == :user
    by_name = Map.new(Message.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "message_id", number: 1, type: :string} = by_name.message_id
    assert %{proto_name: "role", number: 4, type: {:enum, :role}} = by_name.role
    assert %{proto_name: "parts", number: 5, type: {:message, Part}, cardinality: :repeated} = by_name.parts
    assert %{proto_name: "metadata", number: 6, type: :struct} = by_name.metadata
    assert %{proto_name: "extensions", number: 7, type: :string, cardinality: :repeated} = by_name.extensions
    assert %{proto_name: "reference_task_ids", number: 8, cardinality: :repeated, json_name: "referenceTaskIds"} =
             by_name.reference_task_ids
    assert Message.__a2a_proto_name__() == "Message"
  end
end
```

```elixir
defmodule A2A.Types.ArtifactTest do
  use ExUnit.Case, async: true
  alias A2A.Types.{Artifact, Part}

  test "constructs an artifact and exposes its field spec" do
    a = %Artifact{artifact_id: "a1", parts: [Part.text("x")]}
    assert a.artifact_id == "a1"
    by_name = Map.new(Artifact.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "artifact_id", number: 1, type: :string, json_name: "artifactId"} = by_name.artifact_id
    assert %{proto_name: "name", number: 2, type: :string} = by_name.name
    assert %{proto_name: "description", number: 3, type: :string} = by_name.description
    assert %{proto_name: "parts", number: 4, type: {:message, Part}, cardinality: :repeated} = by_name.parts
    assert %{proto_name: "metadata", number: 5, type: :struct} = by_name.metadata
    assert %{proto_name: "extensions", number: 6, cardinality: :repeated} = by_name.extensions
    assert Artifact.__a2a_proto_name__() == "Artifact"
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `mix test test/a2a/types/message_test.exs test/a2a/types/artifact_test.exs`
Expected: FAIL (modules undefined).

- [ ] **Step 3: Implement `A2A.Types.Message`**

```elixir
defmodule A2A.Types.Message do
  @moduledoc "An A2A message: an ordered list of `Part`s with a role."
  alias A2A.Types.{Field, Part}

  @type t :: %__MODULE__{
          message_id: String.t() | nil,
          context_id: String.t() | nil,
          task_id: String.t() | nil,
          role: A2A.Types.Enums.role() | nil,
          parts: [Part.t()],
          metadata: map() | nil,
          extensions: [String.t()],
          reference_task_ids: [String.t()]
        }

  defstruct [
    :message_id,
    :context_id,
    :task_id,
    :role,
    :metadata,
    parts: [],
    extensions: [],
    reference_task_ids: []
  ]

  @doc false
  def __a2a_proto_name__, do: "Message"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :message_id, proto_name: "message_id", number: 1, type: :string),
      Field.new(name: :context_id, proto_name: "context_id", number: 2, type: :string),
      Field.new(name: :task_id, proto_name: "task_id", number: 3, type: :string),
      Field.new(name: :role, proto_name: "role", number: 4, type: {:enum, :role}),
      Field.new(name: :parts, proto_name: "parts", number: 5, type: {:message, Part}, cardinality: :repeated),
      Field.new(name: :metadata, proto_name: "metadata", number: 6, type: :struct),
      Field.new(name: :extensions, proto_name: "extensions", number: 7, type: :string, cardinality: :repeated),
      Field.new(name: :reference_task_ids, proto_name: "reference_task_ids", number: 8, type: :string, cardinality: :repeated)
    ]
  end
end
```

Add `@type role :: :user | :agent` and `@type task_state :: ...` to `A2A.Types.Enums` (as `@type`s) so the `Message`/`TaskStatus` typespecs reference `A2A.Types.Enums.role()` / `.task_state()`. If simpler, inline the union in the `@type` instead — either is acceptable; keep it consistent.

- [ ] **Step 4: Implement `A2A.Types.Artifact`**

```elixir
defmodule A2A.Types.Artifact do
  @moduledoc "An artifact produced by a task: named, described, a list of `Part`s."
  alias A2A.Types.{Field, Part}

  @type t :: %__MODULE__{
          artifact_id: String.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          parts: [Part.t()],
          metadata: map() | nil,
          extensions: [String.t()]
        }

  defstruct [:artifact_id, :name, :description, :metadata, parts: [], extensions: []]

  @doc false
  def __a2a_proto_name__, do: "Artifact"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :artifact_id, proto_name: "artifact_id", number: 1, type: :string),
      Field.new(name: :name, proto_name: "name", number: 2, type: :string),
      Field.new(name: :description, proto_name: "description", number: 3, type: :string),
      Field.new(name: :parts, proto_name: "parts", number: 4, type: {:message, Part}, cardinality: :repeated),
      Field.new(name: :metadata, proto_name: "metadata", number: 5, type: :struct),
      Field.new(name: :extensions, proto_name: "extensions", number: 6, type: :string, cardinality: :repeated)
    ]
  end
end
```

- [ ] **Step 5: Run to verify they pass**

Run: `mix test test/a2a/types/message_test.exs test/a2a/types/artifact_test.exs`
Expected: PASS. Then `mix format`, `mix credo --strict`.

- [ ] **Step 6: Commit**

```bash
git add lib/a2a/types/message.ex lib/a2a/types/artifact.ex lib/a2a/types/enums.ex test/a2a/types
git commit -m "feat: add A2A.Types.Message and A2A.Types.Artifact"
```

---

### Task 5: `A2A.Types.TaskStatus` and `A2A.Types.Task`

**Files:**
- Create: `lib/a2a/types/task_status.ex`, `lib/a2a/types/task.ex`
- Test: `test/a2a/types/task_status_test.exs`, `test/a2a/types/task_test.exs`

**Interfaces:**
- Consumes: `A2A.Types.Field`, `A2A.Types.Message`, `A2A.Types.Artifact`.
- Produces:
  - `%A2A.Types.TaskStatus{state, message, timestamp}` + `__a2a_fields__/0` + `__a2a_proto_name__/0 :: "TaskStatus"`.
  - `%A2A.Types.Task{id, context_id, status, artifacts, history, metadata}` + `__a2a_fields__/0` + `__a2a_proto_name__/0 :: "Task"`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule A2A.Types.TaskStatusTest do
  use ExUnit.Case, async: true
  alias A2A.Types.{TaskStatus, Message}

  test "field spec: state enum (field 2 = message), timestamp" do
    by_name = Map.new(TaskStatus.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "state", number: 1, type: {:enum, :task_state}} = by_name.state
    assert %{proto_name: "message", number: 2, type: {:message, Message}} = by_name.message
    assert %{proto_name: "timestamp", number: 3, type: :timestamp} = by_name.timestamp
    assert TaskStatus.__a2a_proto_name__() == "TaskStatus"
  end
end
```

```elixir
defmodule A2A.Types.TaskTest do
  use ExUnit.Case, async: true
  alias A2A.Types.{Task, TaskStatus, Message, Artifact}

  test "field spec" do
    by_name = Map.new(Task.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "id", number: 1, type: :string} = by_name.id
    assert %{proto_name: "context_id", number: 2, type: :string, json_name: "contextId"} = by_name.context_id
    assert %{proto_name: "status", number: 3, type: {:message, TaskStatus}} = by_name.status
    assert %{proto_name: "artifacts", number: 4, type: {:message, Artifact}, cardinality: :repeated} = by_name.artifacts
    assert %{proto_name: "history", number: 5, type: {:message, Message}, cardinality: :repeated} = by_name.history
    assert %{proto_name: "metadata", number: 6, type: :struct} = by_name.metadata
    assert Task.__a2a_proto_name__() == "Task"
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `mix test test/a2a/types/task_status_test.exs test/a2a/types/task_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement `A2A.Types.TaskStatus`**

```elixir
defmodule A2A.Types.TaskStatus do
  @moduledoc "The status of a task: its state, an optional message, and a timestamp."
  alias A2A.Types.{Field, Message}

  @type t :: %__MODULE__{
          state: A2A.Types.Enums.task_state() | nil,
          message: Message.t() | nil,
          timestamp: DateTime.t() | nil
        }

  defstruct [:state, :message, :timestamp]

  @doc false
  def __a2a_proto_name__, do: "TaskStatus"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :state, proto_name: "state", number: 1, type: {:enum, :task_state}),
      Field.new(name: :message, proto_name: "message", number: 2, type: {:message, Message}),
      Field.new(name: :timestamp, proto_name: "timestamp", number: 3, type: :timestamp)
    ]
  end
end
```

- [ ] **Step 4: Implement `A2A.Types.Task`**

```elixir
defmodule A2A.Types.Task do
  @moduledoc "An A2A task: an id, its status, and accumulated artifacts/history."
  alias A2A.Types.{Field, TaskStatus, Message, Artifact}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          context_id: String.t() | nil,
          status: TaskStatus.t() | nil,
          artifacts: [Artifact.t()],
          history: [Message.t()],
          metadata: map() | nil
        }

  defstruct [:id, :context_id, :status, :metadata, artifacts: [], history: []]

  @doc false
  def __a2a_proto_name__, do: "Task"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :id, proto_name: "id", number: 1, type: :string),
      Field.new(name: :context_id, proto_name: "context_id", number: 2, type: :string),
      Field.new(name: :status, proto_name: "status", number: 3, type: {:message, TaskStatus}),
      Field.new(name: :artifacts, proto_name: "artifacts", number: 4, type: {:message, Artifact}, cardinality: :repeated),
      Field.new(name: :history, proto_name: "history", number: 5, type: {:message, Message}, cardinality: :repeated),
      Field.new(name: :metadata, proto_name: "metadata", number: 6, type: :struct)
    ]
  end
end
```

- [ ] **Step 5: Run to verify they pass**

Run: `mix test test/a2a/types/task_status_test.exs test/a2a/types/task_test.exs`
Expected: PASS. Then `mix format`, `mix credo --strict`.

- [ ] **Step 6: Commit**

```bash
git add lib/a2a/types/task_status.ex lib/a2a/types/task.ex test/a2a/types
git commit -m "feat: add A2A.Types.TaskStatus and A2A.Types.Task"
```

---

### Task 6: `A2A.Types.Events` (update events + `StreamResponse` union)

**Files:**
- Create: `lib/a2a/types/events.ex`
- Test: `test/a2a/types/events_test.exs`

**Interfaces:**
- Consumes: `A2A.Types.Field`, `.Task`, `.Message`, `.TaskStatus`, `.Artifact`.
- Produces (three modules in one file):
  - `%A2A.Types.TaskStatusUpdateEvent{task_id, context_id, status, metadata}` + specs, proto name `"TaskStatusUpdateEvent"`.
  - `%A2A.Types.TaskArtifactUpdateEvent{task_id, context_id, artifact, append, last_chunk, metadata}` + specs, proto name `"TaskArtifactUpdateEvent"`.
  - `%A2A.Types.StreamResponse{kind, task, message, status_update, artifact_update}` tagged union; `__a2a_discriminator__/0 :: :kind`; proto name `"StreamResponse"`; constructors `StreamResponse.task/1`, `.message/1`, `.status_update/1`, `.artifact_update/1`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule A2A.Types.EventsTest do
  use ExUnit.Case, async: true
  alias A2A.Types.{TaskStatusUpdateEvent, TaskArtifactUpdateEvent, StreamResponse, Task, TaskStatus, Artifact}

  test "TaskStatusUpdateEvent field spec" do
    by_name = Map.new(TaskStatusUpdateEvent.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "task_id", number: 1, json_name: "taskId"} = by_name.task_id
    assert %{proto_name: "context_id", number: 2} = by_name.context_id
    assert %{proto_name: "status", number: 3, type: {:message, TaskStatus}} = by_name.status
    assert %{proto_name: "metadata", number: 4, type: :struct} = by_name.metadata
    assert TaskStatusUpdateEvent.__a2a_proto_name__() == "TaskStatusUpdateEvent"
  end

  test "TaskArtifactUpdateEvent field spec incl. bools" do
    by_name = Map.new(TaskArtifactUpdateEvent.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "artifact", number: 3, type: {:message, Artifact}} = by_name.artifact
    assert %{proto_name: "append", number: 4, type: :bool} = by_name.append
    assert %{proto_name: "last_chunk", number: 5, type: :bool, json_name: "lastChunk"} = by_name.last_chunk
  end

  test "StreamResponse is a payload-oneof union" do
    t = %Task{id: "t1"}
    sr = StreamResponse.task(t)
    assert %StreamResponse{kind: :task, task: ^t} = sr
    by_name = Map.new(StreamResponse.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "task", number: 1, type: {:message, Task}, oneof: {:payload, :task}, presence: :explicit} =
             by_name.task
    assert %{proto_name: "status_update", number: 3, oneof: {:payload, :status_update}, json_name: "statusUpdate"} =
             by_name.status_update
    assert StreamResponse.__a2a_discriminator__() == :kind
    assert StreamResponse.__a2a_proto_name__() == "StreamResponse"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/a2a/types/events_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/a2a/types/events.ex`**

```elixir
defmodule A2A.Types.TaskStatusUpdateEvent do
  @moduledoc "Streaming event: a task's status changed."
  alias A2A.Types.{Field, TaskStatus}

  @type t :: %__MODULE__{
          task_id: String.t() | nil,
          context_id: String.t() | nil,
          status: TaskStatus.t() | nil,
          metadata: map() | nil
        }
  defstruct [:task_id, :context_id, :status, :metadata]

  @doc false
  def __a2a_proto_name__, do: "TaskStatusUpdateEvent"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :task_id, proto_name: "task_id", number: 1, type: :string),
      Field.new(name: :context_id, proto_name: "context_id", number: 2, type: :string),
      Field.new(name: :status, proto_name: "status", number: 3, type: {:message, TaskStatus}),
      Field.new(name: :metadata, proto_name: "metadata", number: 4, type: :struct)
    ]
  end
end

defmodule A2A.Types.TaskArtifactUpdateEvent do
  @moduledoc "Streaming event: an artifact was produced or appended."
  alias A2A.Types.{Field, Artifact}

  @type t :: %__MODULE__{
          task_id: String.t() | nil,
          context_id: String.t() | nil,
          artifact: Artifact.t() | nil,
          append: boolean() | nil,
          last_chunk: boolean() | nil,
          metadata: map() | nil
        }
  defstruct [:task_id, :context_id, :artifact, :append, :last_chunk, :metadata]

  @doc false
  def __a2a_proto_name__, do: "TaskArtifactUpdateEvent"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :task_id, proto_name: "task_id", number: 1, type: :string),
      Field.new(name: :context_id, proto_name: "context_id", number: 2, type: :string),
      Field.new(name: :artifact, proto_name: "artifact", number: 3, type: {:message, Artifact}),
      Field.new(name: :append, proto_name: "append", number: 4, type: :bool),
      Field.new(name: :last_chunk, proto_name: "last_chunk", number: 5, type: :bool),
      Field.new(name: :metadata, proto_name: "metadata", number: 6, type: :struct)
    ]
  end
end

defmodule A2A.Types.StreamResponse do
  @moduledoc "A streamed response frame: one of task | message | status_update | artifact_update."
  alias A2A.Types.{Field, Task, Message, TaskStatusUpdateEvent, TaskArtifactUpdateEvent}

  @type kind :: :task | :message | :status_update | :artifact_update
  @type t :: %__MODULE__{
          kind: kind,
          task: Task.t() | nil,
          message: Message.t() | nil,
          status_update: TaskStatusUpdateEvent.t() | nil,
          artifact_update: TaskArtifactUpdateEvent.t() | nil
        }
  defstruct [:kind, :task, :message, :status_update, :artifact_update]

  @spec task(Task.t()) :: t
  def task(%Task{} = t), do: %__MODULE__{kind: :task, task: t}
  @spec message(Message.t()) :: t
  def message(%Message{} = m), do: %__MODULE__{kind: :message, message: m}
  @spec status_update(TaskStatusUpdateEvent.t()) :: t
  def status_update(%TaskStatusUpdateEvent{} = e), do: %__MODULE__{kind: :status_update, status_update: e}
  @spec artifact_update(TaskArtifactUpdateEvent.t()) :: t
  def artifact_update(%TaskArtifactUpdateEvent{} = e), do: %__MODULE__{kind: :artifact_update, artifact_update: e}

  @doc false
  def __a2a_proto_name__, do: "StreamResponse"
  @doc false
  def __a2a_discriminator__, do: :kind

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :task, proto_name: "task", number: 1, type: {:message, Task}, presence: :explicit, oneof: {:payload, :task}),
      Field.new(name: :message, proto_name: "message", number: 2, type: {:message, Message}, presence: :explicit, oneof: {:payload, :message}),
      Field.new(name: :status_update, proto_name: "status_update", number: 3, type: {:message, TaskStatusUpdateEvent}, presence: :explicit, oneof: {:payload, :status_update}),
      Field.new(name: :artifact_update, proto_name: "artifact_update", number: 4, type: {:message, TaskArtifactUpdateEvent}, presence: :explicit, oneof: {:payload, :artifact_update})
    ]
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/a2a/types/events_test.exs`
Expected: PASS. Then `mix format`, `mix credo --strict`.

- [ ] **Step 5: Commit**

```bash
git add lib/a2a/types/events.ex test/a2a/types/events_test.exs
git commit -m "feat: add A2A.Types events and StreamResponse union"
```

---

### Task 7: `A2A.Types.Requests` (RPC envelopes)

**Files:**
- Create: `lib/a2a/types/requests.ex`
- Test: `test/a2a/types/requests_test.exs`

**Interfaces:**
- Consumes: `A2A.Types.Field`, `.Message`, `.Task`.
- Produces (four modules in one file):
  - `%A2A.Types.SendMessageConfiguration{accepted_output_modes, task_push_notification_config, history_length, return_immediately}`; proto name `"SendMessageConfiguration"`. `task_push_notification_config` uses `type: :raw` (Phase-4 message deferred — passthrough); `history_length` is `presence: :explicit`.
  - `%A2A.Types.SendMessageRequest{tenant, message, configuration, metadata}`; proto name `"SendMessageRequest"`.
  - `%A2A.Types.SendMessageResponse{kind, task, message}` union (`__a2a_discriminator__ :: :kind`); constructors `.task/1`, `.message/1`; proto name `"SendMessageResponse"`.
  - `%A2A.Types.GetTaskRequest{tenant, id, history_length}`; `history_length` `presence: :explicit`; proto name `"GetTaskRequest"`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule A2A.Types.RequestsTest do
  use ExUnit.Case, async: true
  alias A2A.Types.{SendMessageConfiguration, SendMessageRequest, SendMessageResponse, GetTaskRequest, Message, Task}

  test "SendMessageConfiguration field spec" do
    by_name = Map.new(SendMessageConfiguration.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "accepted_output_modes", number: 1, type: :string, cardinality: :repeated} =
             by_name.accepted_output_modes
    assert %{proto_name: "task_push_notification_config", number: 2, type: :raw} = by_name.task_push_notification_config
    assert %{proto_name: "history_length", number: 3, type: :int32, presence: :explicit} = by_name.history_length
    assert %{proto_name: "return_immediately", number: 4, type: :bool} = by_name.return_immediately
  end

  test "SendMessageRequest field spec" do
    by_name = Map.new(SendMessageRequest.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "tenant", number: 1, type: :string} = by_name.tenant
    assert %{proto_name: "message", number: 2, type: {:message, Message}} = by_name.message
    assert %{proto_name: "configuration", number: 3, type: {:message, SendMessageConfiguration}} = by_name.configuration
    assert %{proto_name: "metadata", number: 4, type: :struct} = by_name.metadata
  end

  test "SendMessageResponse union and GetTaskRequest" do
    assert %SendMessageResponse{kind: :task, task: %Task{id: "t"}} = SendMessageResponse.task(%Task{id: "t"})
    resp_by = Map.new(SendMessageResponse.__a2a_fields__(), &{&1.name, &1})
    assert %{oneof: {:payload, :task}, presence: :explicit} = resp_by.task
    assert %{oneof: {:payload, :message}, presence: :explicit} = resp_by.message
    assert SendMessageResponse.__a2a_discriminator__() == :kind

    get_by = Map.new(GetTaskRequest.__a2a_fields__(), &{&1.name, &1})
    assert %{proto_name: "id", number: 2, type: :string} = get_by.id
    assert %{proto_name: "history_length", number: 3, type: :int32, presence: :explicit} = get_by.history_length
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/a2a/types/requests_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/a2a/types/requests.ex`**

```elixir
defmodule A2A.Types.SendMessageConfiguration do
  @moduledoc "Per-request send configuration."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          accepted_output_modes: [String.t()],
          task_push_notification_config: map() | nil,
          history_length: integer() | nil,
          return_immediately: boolean() | nil
        }
  defstruct [:task_push_notification_config, :history_length, :return_immediately, accepted_output_modes: []]

  @doc false
  def __a2a_proto_name__, do: "SendMessageConfiguration"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :accepted_output_modes, proto_name: "accepted_output_modes", number: 1, type: :string, cardinality: :repeated),
      # task_push_notification_config references a Phase-4 message; passthrough until Phase 4 builds the struct.
      Field.new(name: :task_push_notification_config, proto_name: "task_push_notification_config", number: 2, type: :raw),
      Field.new(name: :history_length, proto_name: "history_length", number: 3, type: :int32, presence: :explicit),
      Field.new(name: :return_immediately, proto_name: "return_immediately", number: 4, type: :bool)
    ]
  end
end

defmodule A2A.Types.SendMessageRequest do
  @moduledoc "Request to send a message to an agent."
  alias A2A.Types.{Field, Message, SendMessageConfiguration}

  @type t :: %__MODULE__{
          tenant: String.t() | nil,
          message: Message.t() | nil,
          configuration: SendMessageConfiguration.t() | nil,
          metadata: map() | nil
        }
  defstruct [:tenant, :message, :configuration, :metadata]

  @doc false
  def __a2a_proto_name__, do: "SendMessageRequest"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :tenant, proto_name: "tenant", number: 1, type: :string),
      Field.new(name: :message, proto_name: "message", number: 2, type: {:message, Message}),
      Field.new(name: :configuration, proto_name: "configuration", number: 3, type: {:message, SendMessageConfiguration}),
      Field.new(name: :metadata, proto_name: "metadata", number: 4, type: :struct)
    ]
  end
end

defmodule A2A.Types.SendMessageResponse do
  @moduledoc "Response to a send: one of task | message."
  alias A2A.Types.{Field, Task, Message}

  @type kind :: :task | :message
  @type t :: %__MODULE__{kind: kind, task: Task.t() | nil, message: Message.t() | nil}
  defstruct [:kind, :task, :message]

  @spec task(Task.t()) :: t
  def task(%Task{} = t), do: %__MODULE__{kind: :task, task: t}
  @spec message(Message.t()) :: t
  def message(%Message{} = m), do: %__MODULE__{kind: :message, message: m}

  @doc false
  def __a2a_proto_name__, do: "SendMessageResponse"
  @doc false
  def __a2a_discriminator__, do: :kind

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :task, proto_name: "task", number: 1, type: {:message, Task}, presence: :explicit, oneof: {:payload, :task}),
      Field.new(name: :message, proto_name: "message", number: 2, type: {:message, Message}, presence: :explicit, oneof: {:payload, :message})
    ]
  end
end

defmodule A2A.Types.GetTaskRequest do
  @moduledoc "Request to fetch a task by id."
  alias A2A.Types.Field

  @type t :: %__MODULE__{tenant: String.t() | nil, id: String.t() | nil, history_length: integer() | nil}
  defstruct [:tenant, :id, :history_length]

  @doc false
  def __a2a_proto_name__, do: "GetTaskRequest"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :tenant, proto_name: "tenant", number: 1, type: :string),
      Field.new(name: :id, proto_name: "id", number: 2, type: :string),
      Field.new(name: :history_length, proto_name: "history_length", number: 3, type: :int32, presence: :explicit)
    ]
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/a2a/types/requests_test.exs`
Expected: PASS. Then `mix format`, `mix credo --strict`.

- [ ] **Step 5: Commit**

```bash
git add lib/a2a/types/requests.ex test/a2a/types/requests_test.exs
git commit -m "feat: add A2A.Types request/response envelopes"
```

---

### Task 8: `A2A.JSON.encode/1` (+ `to_json_map/1`)

**Files:**
- Create: `lib/a2a/json.ex`
- Test: `test/a2a/json_test.exs` (encode section)

**Interfaces:**
- Consumes: every `A2A.Types.*` module's `__a2a_fields__/0`, `A2A.Types.Enums`, `A2A.JSON.Naming`, `Jason`.
- Produces:
  - `A2A.JSON.to_json_map(struct) :: map` — the intermediate JSON-able map (string keys).
  - `A2A.JSON.encode(struct) :: {:ok, iodata} | {:error, term}` and `encode!/1 :: iodata` — `Jason`-encoded.

- [ ] **Step 1: Write the failing encode tests (one per rule)**

```elixir
defmodule A2A.JSONTest do
  use ExUnit.Case, async: true
  alias A2A.JSON
  alias A2A.Types.{Message, Part, TaskStatus, Task, Artifact}

  defp jmap(struct), do: JSON.to_json_map(struct)

  test "camelCase keys, snake_case dropped, enums as proto names" do
    m = %Message{message_id: "m1", role: :user, parts: [Part.text("hi")]}
    map = jmap(m)
    assert map["messageId"] == "m1"
    assert map["role"] == "ROLE_USER"
    assert [%{"text" => "hi"}] = map["parts"]
  end

  test "omits nil and implicit-default scalars, keeps explicit-presence zero" do
    # empty string / empty list / false omitted
    assert jmap(%Message{message_id: "x", role: :agent, parts: []}) == %{"messageId" => "x", "role" => "ROLE_AGENT"}
    assert jmap(%A2A.Types.GetTaskRequest{id: "t", history_length: 0}) == %{"id" => "t", "historyLength" => 0}
  end

  test "bytes -> standard base64 with padding" do
    assert jmap(Part.raw(<<255, 240, 1>>)) == %{"raw" => Base.encode64(<<255, 240, 1>>)}
  end

  test "google.protobuf.Struct metadata and Value data pass through as JSON" do
    assert jmap(Part.data(%{"k" => [1, 2, %{"z" => true}]}))["data"] == %{"k" => [1, 2, %{"z" => true}]}
    assert jmap(%Message{message_id: "m", role: :user, metadata: %{"a" => 1}})["metadata"] == %{"a" => 1}
  end

  test "Timestamp -> Z-normalized RFC3339" do
    ts = ~U[2023-10-27 10:00:00Z]
    assert jmap(%TaskStatus{state: :working, timestamp: ts})["timestamp"] == "2023-10-27T10:00:00Z"
  end

  test "nested messages and repeated fields recurse" do
    t = %Task{id: "t1", status: %TaskStatus{state: :completed}, artifacts: [%Artifact{artifact_id: "a", parts: [Part.text("x")]}]}
    map = jmap(t)
    assert map["id"] == "t1"
    assert map["status"] == %{"state" => "TASK_STATE_COMPLETED"}
    assert [%{"artifactId" => "a", "parts" => [%{"text" => "x"}]}] = map["artifacts"]
  end

  test "encode/1 produces JSON via Jason" do
    {:ok, iodata} = JSON.encode(%TaskStatus{state: :working})
    assert Jason.decode!(IO.iodata_to_binary(iodata)) == %{"state" => "TASK_STATE_WORKING"}
  end

  test "int64 synthetic rule: encoded as decimal string" do
    # exercised via A2A.JSON.encode_scalar/2 indirectly in the int64 synthetic test module (Task 11);
    # here assert the helper directly if exposed, else covered by synthetic fixtures.
    assert JSON.encode_scalar(:int64, 9_000_000_000) == "9000000000"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/a2a/json_test.exs`
Expected: FAIL (`A2A.JSON` undefined).

- [ ] **Step 3: Implement encode in `lib/a2a/json.ex`**

```elixir
defmodule A2A.JSON do
  @moduledoc """
  proto3-JSON codec for the A2A type surface. Driven entirely by each struct's
  `__a2a_fields__/0` spec. `encode/1` and `decode/2` are the public surface;
  `to_json_map/1` and `from_json_map/2` expose the intermediate map layer.
  """
  alias A2A.Types.Enums

  @spec encode(struct) :: {:ok, iodata} | {:error, term}
  def encode(struct), do: struct |> to_json_map() |> Jason.encode()

  @spec encode!(struct) :: iodata
  def encode!(struct), do: struct |> to_json_map() |> Jason.encode!()

  @spec to_json_map(struct) :: map
  def to_json_map(%module{} = struct) do
    Enum.reduce(module.__a2a_fields__(), %{}, fn field, acc ->
      value = Map.get(struct, field.name)

      case encode_field(field, value) do
        :skip -> acc
        {:emit, json} -> Map.put(acc, field.json_name, json)
      end
    end)
  end

  defp encode_field(_field, nil), do: :skip

  defp encode_field(%{cardinality: :repeated} = field, list) when is_list(list) do
    if list == [], do: :skip, else: {:emit, Enum.map(list, &encode_scalar(field.type, &1))}
  end

  defp encode_field(%{presence: :implicit, type: type} = _field, value) do
    if value == default(type), do: :skip, else: {:emit, encode_scalar(type, value)}
  end

  defp encode_field(field, value), do: {:emit, encode_scalar(field.type, value)}

  @doc false
  def encode_scalar(:string, v), do: v
  def encode_scalar(:bool, v), do: v
  def encode_scalar(:int32, v), do: v
  def encode_scalar(:int64, v), do: Integer.to_string(v)
  def encode_scalar(:bytes, v), do: Base.encode64(v)
  def encode_scalar(:timestamp, %DateTime{} = v), do: format_timestamp(v)
  def encode_scalar(:struct, v), do: v
  def encode_scalar(:value, v), do: v
  def encode_scalar(:raw, v), do: v
  def encode_scalar({:enum, e}, v), do: Enums.encode!(e, v)
  def encode_scalar({:message, _mod}, v), do: to_json_map(v)

  defp default(:string), do: ""
  defp default(:bool), do: false
  defp default(:int32), do: 0
  defp default(:int64), do: 0
  defp default(_), do: :__no_default__

  defp format_timestamp(%DateTime{} = dt) do
    dt |> DateTime.truncate_to_valid() |> DateTime.to_iso8601()
  end
end
```

Note on `format_timestamp`: use `DateTime.to_iso8601/1`, which for a UTC datetime emits `...Z` with fractional digits equal to the datetime's microsecond precision (0 → none, 3 → 3, 6 → 6). Proto3 allows 0/3/6/9 fractional digits, so these all conform. There is **no** `DateTime.truncate_to_valid/1` — replace that line with a plain `DateTime.to_iso8601(dt)` and require callers to store UTC datetimes (the decode path always produces UTC). If microsecond precision must be normalized for byte-equality with the oracle, the golden-file tests (Task 11) are the backstop; do not over-engineer here.

Fix the line to:
```elixir
defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
```

- [ ] **Step 4: Run to verify encode tests pass**

Run: `mix test test/a2a/json_test.exs`
Expected: PASS. Then `mix format`, `mix credo --strict`.

- [ ] **Step 5: Commit**

```bash
git add lib/a2a/json.ex test/a2a/json_test.exs
git commit -m "feat: add A2A.JSON encode driven by field specs"
```

---

### Task 9: `A2A.JSON.decode/2` (+ `from_json_map/2`) and round-trip properties

**Files:**
- Modify: `lib/a2a/json.ex`
- Test: `test/a2a/json_test.exs` (decode + round-trip sections)

**Interfaces:**
- Consumes: encode side from Task 8; `A2A.Types.Enums`; each module's `__a2a_fields__/0`, optional `__a2a_discriminator__/0`.
- Produces:
  - `A2A.JSON.from_json_map(map, module) :: {:ok, struct} | {:error, term}`.
  - `A2A.JSON.decode(binary, module) :: {:ok, struct} | {:error, term}` and `decode!/2`.

- [ ] **Step 1: Write the failing decode tests**

```elixir
# append to A2A.JSONTest
  test "decode accepts camelCase and snake_case keys" do
    {:ok, m1} = JSON.from_json_map(%{"messageId" => "m", "role" => "ROLE_USER"}, Message)
    {:ok, m2} = JSON.from_json_map(%{"message_id" => "m", "role" => "ROLE_USER"}, Message)
    assert m1 == m2
    assert m1.message_id == "m" and m1.role == :user
  end

  test "decode enums accept name and integer, reject UNSPECIFIED" do
    assert {:ok, %TaskStatus{state: :working}} = JSON.from_json_map(%{"state" => "TASK_STATE_WORKING"}, TaskStatus)
    assert {:ok, %TaskStatus{state: :working}} = JSON.from_json_map(%{"state" => 2}, TaskStatus)
    assert {:error, _} = JSON.from_json_map(%{"state" => "TASK_STATE_UNSPECIFIED"}, TaskStatus)
  end

  test "decode base64 accepts standard, urlsafe, and unpadded" do
    b = <<255, 240, 1>>
    for enc <- [Base.encode64(b), Base.url_encode64(b), Base.encode64(b, padding: false)] do
      assert {:ok, %Part{kind: :raw, raw: ^b}} = JSON.from_json_map(%{"raw" => enc}, Part)
    end
  end

  test "decode sets the discriminator on unions" do
    {:ok, sr} = JSON.from_json_map(%{"statusUpdate" => %{"taskId" => "t"}}, A2A.Types.StreamResponse)
    assert sr.kind == :status_update
    assert sr.status_update.task_id == "t"
  end

  test "decode timestamp parses RFC3339 with offset to UTC DateTime" do
    {:ok, ts} = JSON.from_json_map(%{"state" => "TASK_STATE_WORKING", "timestamp" => "2023-10-27T12:00:00+02:00"}, TaskStatus)
    assert ts.timestamp == ~U[2023-10-27 10:00:00Z]
  end

  test "decode/2 parses a JSON string" do
    assert {:ok, %TaskStatus{state: :completed}} = JSON.decode(~s({"state":"TASK_STATE_COMPLETED"}), TaskStatus)
  end

  test "round-trips a rich Task through encode |> decode" do
    task = %Task{
      id: "t1",
      context_id: "c1",
      status: %TaskStatus{state: :working, timestamp: ~U[2023-10-27 10:00:00Z]},
      artifacts: [%Artifact{artifact_id: "a1", parts: [Part.text("hi"), Part.raw(<<1, 2>>), Part.data(%{"k" => 1})]}],
      metadata: %{"m" => true}
    }
    {:ok, iodata} = JSON.encode(task)
    assert {:ok, ^task} = JSON.decode(IO.iodata_to_binary(iodata), Task)
  end
```

Property test (separate module):
```elixir
defmodule A2A.JSONPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias A2A.JSON
  alias A2A.Test.Generators

  property "decode(encode(x)) == x for Message" do
    check all m <- Generators.message() do
      {:ok, iodata} = JSON.encode(m)
      assert {:ok, ^m} = JSON.decode(IO.iodata_to_binary(iodata), A2A.Types.Message)
    end
  end
end
```
(`A2A.Test.Generators` is built in Task 11; if Task 11 has not landed yet, guard this module behind `@moduletag :proto`-free but skip via `@tag :skip` until generators exist, or fold the property module into Task 11. Recommended: move `A2A.JSONPropertyTest` into Task 11 so Task 9 has no forward dependency.)

- [ ] **Step 2: Run to verify decode tests fail**

Run: `mix test test/a2a/json_test.exs`
Expected: FAIL (`from_json_map`/`decode` undefined).

- [ ] **Step 3: Implement decode in `lib/a2a/json.ex`**

```elixir
  @spec decode(binary, module) :: {:ok, struct} | {:error, term}
  def decode(json, module) when is_binary(json) do
    with {:ok, map} <- Jason.decode(json), do: from_json_map(map, module)
  end

  @spec decode!(binary, module) :: struct
  def decode!(json, module) do
    case decode(json, module) do
      {:ok, struct} -> struct
      {:error, reason} -> raise ArgumentError, "A2A.JSON.decode failed: #{inspect(reason)}"
    end
  end

  @spec from_json_map(map, module) :: {:ok, struct} | {:error, term}
  def from_json_map(map, module) when is_map(map) do
    fields = module.__a2a_fields__()

    result =
      Enum.reduce_while(fields, {:ok, struct(module)}, fn field, {:ok, acc} ->
        case fetch(map, field) do
          :missing ->
            {:cont, {:ok, acc}}

          {:ok, raw} ->
            case decode_field(field, raw) do
              {:ok, value} -> {:cont, {:ok, Map.put(acc, field.name, value)}}
              {:error, _} = err -> {:halt, err}
            end
        end
      end)

    with {:ok, struct} <- result, do: {:ok, set_discriminator(module, struct)}
  end

  defp fetch(map, field) do
    cond do
      Map.has_key?(map, field.json_name) -> {:ok, Map.get(map, field.json_name)}
      Map.has_key?(map, field.proto_name) -> {:ok, Map.get(map, field.proto_name)}
      true -> :missing
    end
  end

  defp decode_field(_field, nil), do: {:ok, nil}

  defp decode_field(%{cardinality: :repeated} = field, list) when is_list(list) do
    reduce_ok(list, &decode_scalar(field.type, &1))
  end

  defp decode_field(field, raw), do: decode_scalar(field.type, raw)

  defp decode_scalar(:string, v) when is_binary(v), do: {:ok, v}
  defp decode_scalar(:bool, v) when is_boolean(v), do: {:ok, v}
  defp decode_scalar(:int32, v) when is_integer(v), do: {:ok, v}
  defp decode_scalar(:int64, v) when is_integer(v), do: {:ok, v}
  defp decode_scalar(:int64, v) when is_binary(v), do: {:ok, String.to_integer(v)}
  defp decode_scalar(:bytes, v) when is_binary(v), do: decode_base64(v)
  defp decode_scalar(:timestamp, v) when is_binary(v), do: decode_timestamp(v)
  defp decode_scalar(:struct, v) when is_map(v), do: {:ok, v}
  defp decode_scalar(:value, v), do: {:ok, v}
  defp decode_scalar(:raw, v), do: {:ok, v}
  defp decode_scalar({:enum, e}, v), do: Enums.decode(e, v)
  defp decode_scalar({:message, mod}, v) when is_map(v), do: from_json_map(v, mod)
  defp decode_scalar(type, v), do: {:error, {:type_mismatch, type, v}}

  defp decode_base64(str) do
    variants = [
      fn -> Base.decode64(str) end,
      fn -> Base.decode64(str, padding: false) end,
      fn -> Base.url_decode64(str) end,
      fn -> Base.url_decode64(str, padding: false) end
    ]

    Enum.find_value(variants, {:error, {:invalid_base64, str}}, fn f ->
      case f.() do
        {:ok, bin} -> {:ok, bin}
        :error -> nil
      end
    end)
  end

  defp decode_timestamp(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, reason} -> {:error, {:invalid_timestamp, reason}}
    end
  end

  defp reduce_ok(list, fun) do
    result =
      Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
        case fun.(item) do
          {:ok, v} -> {:cont, {:ok, [v | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    with {:ok, acc} <- result, do: {:ok, Enum.reverse(acc)}
  end

  defp set_discriminator(module, struct) do
    if function_exported?(module, :__a2a_discriminator__, 0) do
      disc = module.__a2a_discriminator__()

      tag =
        module.__a2a_fields__()
        |> Enum.find_value(fn
          %{oneof: {_group, tag}} = f -> if Map.get(struct, f.name) != nil, do: tag
          _ -> nil
        end)

      Map.put(struct, disc, tag)
    else
      struct
    end
  end
```

Note: `DateTime.from_iso8601/1` returns the datetime already shifted to UTC (with the offset reported separately), so `~U[2023-10-27 10:00:00Z]` is produced for `+02:00` input. Verify this against the installed Elixir; if a given version returns the naive local time, add `DateTime.add(dt, -offset, :second)` — but the standard behavior is UTC-normalized.

- [ ] **Step 4: Run to verify decode + round-trip tests pass**

Run: `mix test test/a2a/json_test.exs`
Expected: PASS. Then `mix format`, `mix credo --strict`, `mix dialyzer` (if PLT available).

- [ ] **Step 5: Commit**

```bash
git add lib/a2a/json.ex test/a2a/json_test.exs
git commit -m "feat: add A2A.JSON decode and full round-trip"
```

---

### Task 10: Proto vendoring, `mix a2a.gen_proto`, and the coverage manifest

**Files:**
- Create: `priv/proto/PROTO_VERSION`, `priv/proto/a2a.proto`, `priv/proto/google/**` (vendored imports), `lib/mix/tasks/a2a.gen_proto.ex`, `test/support/coverage.ex`, `test/support/coverage_test.exs`

**Interfaces:**
- Consumes: `A2A.Types.*` modules' `__a2a_proto_name__/0`, `A2A.Types.Enums.proto_names/0`.
- Produces:
  - `mix a2a.gen_proto` — runs `protoc` into `test/support/gen/` (git-ignored).
  - `A2A.Test.Coverage.covered() :: MapSet.t(String.t())` (derived from loaded `A2A.Types` modules + enum proto names).
  - `A2A.Test.Coverage.deferred() :: [%{message: String.t(), phase: 2..4, reason: String.t()}]` and `deferred_names/0 :: MapSet.t(String.t())`.
  - `A2A.Test.Coverage.all_expected() :: MapSet.t()` = `covered ∪ deferred_names`.

- [ ] **Step 1: Vendor the proto files and pin the version**

`priv/proto/PROTO_VERSION`:
```
repo: https://github.com/a2aproject/a2a
path: specification/a2a.proto
commit: cfc9d34bc41e368827eb6446d31f912e44f795c5
```

Fetch and save (do NOT hand-transcribe):
```bash
mkdir -p priv/proto/google/api priv/proto/google/protobuf
REF=cfc9d34bc41e368827eb6446d31f912e44f795c5
curl -fsSL "https://raw.githubusercontent.com/a2aproject/a2a/$REF/specification/a2a.proto" -o priv/proto/a2a.proto
for f in api/annotations.proto api/client.proto api/http.proto api/field_behavior.proto api/launch_stage.proto; do
  curl -fsSL "https://raw.githubusercontent.com/googleapis/googleapis/master/google/$f" -o "priv/proto/google/$f"
done
```
`google/protobuf/{struct,timestamp,empty,descriptor}.proto` are provided by the `protobuf`/`google_protos` packages' include path — pass their include dir to `protoc` (Step 3) instead of vendoring. If `protoc`'s bundled well-known types are on the default include path, no extra `-I` is needed for them.

Verify: `head -12 priv/proto/a2a.proto` shows `package lf.a2a.v1;` and the import list.

- [ ] **Step 2: Write `mix a2a.gen_proto`**

```elixir
defmodule Mix.Tasks.A2a.GenProto do
  @moduledoc """
  Generates throwaway Elixir proto modules from `priv/proto/a2a.proto` into
  `test/support/gen/` for use by the test-only proto-conformance harness.

  Requires `protoc` and the `protoc-gen-elixir` escript on PATH. Never part of
  `mix compile`; run manually or in CI before `mix test --only proto`.
  """
  use Mix.Task
  @shortdoc "Generate proto oracle modules into test/support/gen (dev/CI only)"

  @out "test/support/gen"
  @proto_dir "priv/proto"

  @impl true
  def run(_args) do
    File.mkdir_p!(@out)
    protoc = System.find_executable("protoc") || Mix.raise("protoc not found on PATH")

    includes = ["-I", @proto_dir] ++ well_known_includes()

    args =
      includes ++
        ["--elixir_out=#{@out}", "--elixir_opt=package_prefix=a2a.oracle", Path.join(@proto_dir, "a2a.proto")]

    case System.cmd(protoc, args, stderr_to_stdout: true) do
      {_out, 0} -> Mix.shell().info("Generated proto modules into #{@out}")
      {out, code} -> Mix.raise("protoc failed (#{code}):\n#{out}")
    end
  end

  defp well_known_includes do
    # google_protos ships the well-known .proto files; add its priv dir if present.
    case Application.app_dir(:google_protos) do
      dir when is_binary(dir) -> ["-I", Path.join(dir, "priv/protos")]
      _ -> []
    end
  rescue
    _ -> []
  end
end
```
Note: verify the `--elixir_opt` flags against the installed `protoc-gen-elixir` (the option to namespace generated modules may differ by version; if `package_prefix` is unsupported, drop it — the generated modules will use the proto package `Lf.A2a.V1.*`, and the harness in Task 11 must reference whatever namespace is produced). The gen task is dev/CI-only, so iterate against the real toolchain.

- [ ] **Step 3: Manually run codegen to confirm it works (local verification)**

```bash
mix escript.install --force hex protobuf
export PATH="$HOME/.mix/escripts:$PATH"
mix a2a.gen_proto
ls test/support/gen
```
Expected: at least one `.pb.ex` file generated, no protoc errors. (If googleapis imports fail, add the missing `-I` include or vendor the missing import; record what was needed.) This step proves the toolchain path; it produces git-ignored output.

- [ ] **Step 4: Write the failing coverage-manifest test**

```elixir
defmodule A2A.Test.CoverageTest do
  use ExUnit.Case, async: true
  alias A2A.Test.Coverage

  @all_proto_messages ~w(
    SendMessageConfiguration Task TaskStatus Part Message Artifact
    TaskStatusUpdateEvent TaskArtifactUpdateEvent AuthenticationInfo AgentInterface
    AgentCard AgentProvider AgentCapabilities AgentExtension AgentSkill AgentCardSignature
    TaskPushNotificationConfig StringList SecurityRequirement SecurityScheme
    APIKeySecurityScheme HTTPAuthSecurityScheme OAuth2SecurityScheme OpenIdConnectSecurityScheme
    MutualTlsSecurityScheme OAuthFlows AuthorizationCodeOAuthFlow ClientCredentialsOAuthFlow
    ImplicitOAuthFlow PasswordOAuthFlow DeviceCodeOAuthFlow SendMessageRequest GetTaskRequest
    ListTasksRequest ListTasksResponse CancelTaskRequest GetTaskPushNotificationConfigRequest
    DeleteTaskPushNotificationConfigRequest SubscribeToTaskRequest
    ListTaskPushNotificationConfigsRequest GetExtendedAgentCardRequest SendMessageResponse
    StreamResponse ListTaskPushNotificationConfigsResponse
  )

  test "covered set = the 12 Phase-1 messages + 2 enums" do
    assert Coverage.covered() ==
             MapSet.new(~w(
               Message Task TaskStatus Part Artifact TaskStatusUpdateEvent TaskArtifactUpdateEvent
               StreamResponse SendMessageRequest SendMessageResponse SendMessageConfiguration GetTaskRequest
               TaskState Role
             ))
  end

  test "deferred lists exactly the 32 remaining messages with a phase and reason" do
    assert MapSet.size(Coverage.deferred_names()) == 32
    for d <- Coverage.deferred() do
      assert d.phase in 2..4
      assert is_binary(d.reason) and d.reason != ""
    end
  end

  test "partition holds: covered and deferred are disjoint and cover all proto messages" do
    assert MapSet.disjoint?(Coverage.covered_messages(), Coverage.deferred_names())
    # covered messages (excluding the 2 enums) ∪ deferred == all 44 proto messages
    assert MapSet.union(Coverage.covered_messages(), Coverage.deferred_names()) ==
             MapSet.new(@all_proto_messages)
  end
end
```

- [ ] **Step 5: Run to verify it fails**

Run: `mix test test/support/coverage_test.exs`
Expected: FAIL (`A2A.Test.Coverage` undefined).

- [ ] **Step 6: Implement `test/support/coverage.ex`**

```elixir
defmodule A2A.Test.Coverage do
  @moduledoc """
  Coverage manifest for the proto-conformance harness. `covered` is DERIVED from
  the loaded `A2A.Types.*` modules (so it cannot drift from the code); `@deferred`
  is the explicit list of messages postponed to Phases 2–4.
  """

  @deferred [
    # Phase 2 — Agent card & discovery
    %{message: "AgentCard", phase: 2, reason: "Phase 2: agent card & discovery"},
    %{message: "AgentInterface", phase: 2, reason: "Phase 2: agent card & discovery"},
    %{message: "AgentProvider", phase: 2, reason: "Phase 2: agent card & discovery"},
    %{message: "AgentCapabilities", phase: 2, reason: "Phase 2: agent card & discovery"},
    %{message: "AgentExtension", phase: 2, reason: "Phase 2: agent card & discovery"},
    %{message: "AgentSkill", phase: 2, reason: "Phase 2: agent card & discovery"},
    %{message: "AgentCardSignature", phase: 2, reason: "Phase 2: agent card & discovery"},
    %{message: "GetExtendedAgentCardRequest", phase: 2, reason: "Phase 2: agent card & discovery"},
    # Phase 3 — Security schemes
    %{message: "SecurityScheme", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "APIKeySecurityScheme", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "HTTPAuthSecurityScheme", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "OAuth2SecurityScheme", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "OpenIdConnectSecurityScheme", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "MutualTlsSecurityScheme", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "SecurityRequirement", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "OAuthFlows", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "AuthorizationCodeOAuthFlow", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "ClientCredentialsOAuthFlow", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "ImplicitOAuthFlow", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "PasswordOAuthFlow", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "DeviceCodeOAuthFlow", phase: 3, reason: "Phase 3: security schemes"},
    %{message: "AuthenticationInfo", phase: 3, reason: "Phase 3: security schemes"},
    # Phase 4 — Push notifications & task listing
    %{message: "TaskPushNotificationConfig", phase: 4, reason: "Phase 4: push notifications & task listing"},
    %{message: "GetTaskPushNotificationConfigRequest", phase: 4, reason: "Phase 4: push notifications & task listing"},
    %{message: "DeleteTaskPushNotificationConfigRequest", phase: 4, reason: "Phase 4: push notifications & task listing"},
    %{message: "ListTaskPushNotificationConfigsRequest", phase: 4, reason: "Phase 4: push notifications & task listing"},
    %{message: "ListTaskPushNotificationConfigsResponse", phase: 4, reason: "Phase 4: push notifications & task listing"},
    %{message: "ListTasksRequest", phase: 4, reason: "Phase 4: push notifications & task listing"},
    %{message: "ListTasksResponse", phase: 4, reason: "Phase 4: push notifications & task listing"},
    %{message: "CancelTaskRequest", phase: 4, reason: "Phase 4: push notifications & task listing"},
    %{message: "SubscribeToTaskRequest", phase: 4, reason: "Phase 4: push notifications & task listing"},
    %{message: "StringList", phase: 4, reason: "Phase 4: push notifications & task listing"}
  ]

  @spec deferred() :: [%{message: String.t(), phase: 2..4, reason: String.t()}]
  def deferred, do: @deferred

  @spec deferred_names() :: MapSet.t(String.t())
  def deferred_names, do: MapSet.new(@deferred, & &1.message)

  @doc "Proto message names with a hand-written struct (derived from loaded modules)."
  @spec covered_messages() :: MapSet.t(String.t())
  def covered_messages do
    ensure_loaded()

    for {mod, _} <- :code.all_loaded(),
        mod |> Atom.to_string() |> String.starts_with?("Elixir.A2A.Types."),
        function_exported?(mod, :__a2a_proto_name__, 0),
        into: MapSet.new() do
      mod.__a2a_proto_name__()
    end
  end

  @doc "Covered messages plus covered enum type names."
  @spec covered() :: MapSet.t(String.t())
  def covered, do: MapSet.union(covered_messages(), MapSet.new(A2A.Types.Enums.proto_names()))

  @spec all_expected() :: MapSet.t(String.t())
  def all_expected, do: MapSet.union(covered(), deferred_names())

  # `:code.all_loaded/0` only sees loaded modules; force-load the A2A.Types tree.
  defp ensure_loaded do
    {:ok, mods} = :application.get_key(:a2a, :modules)
    Enum.each(mods, &Code.ensure_loaded/1)
  end
end
```

- [ ] **Step 7: Run to verify coverage tests pass**

Run: `mix test test/support/coverage_test.exs`
Expected: PASS (this test needs no `protoc`). Then `mix format`, `mix credo --strict`.

- [ ] **Step 8: Commit**

```bash
git add priv/proto/PROTO_VERSION priv/proto/a2a.proto priv/proto/google lib/mix/tasks/a2a.gen_proto.ex test/support/coverage.ex test/support/coverage_test.exs
git commit -m "feat: vendor proto, add gen_proto task and coverage manifest"
```

---

### Task 11: Proto-conformance harness — Tier 1 (partition) + Tier 2 (differential oracle + golden), generators, int64 synthetic

**Files:**
- Create: `test/support/generators.ex`, `test/support/fixtures.ex`, `test/support/golden/*.json`, `test/a2a/proto_conformance_test.exs`, `test/a2a/json_property_test.exs`
- Test: the above (all `@tag :proto` except the property + golden tests, which run without `protoc`)

**Interfaces:**
- Consumes: `A2A.JSON`, `A2A.Test.Coverage`, the generated oracle modules (namespace produced by Task 10 Step 3), all `A2A.Types.*`.
- Produces: `A2A.Test.Generators.<type>()` `StreamData` generators; `A2A.Test.Fixtures.all/0` representative instances.

- [ ] **Step 1: Write `A2A.Test.Generators` and `A2A.Test.Fixtures`**

`test/support/generators.ex` — `StreamData` generators that produce only decode-legal values (non-`UNSPECIFIED` enums, UTC timestamps truncated to microsecond, valid utf8 strings). Sketch:
```elixir
defmodule A2A.Test.Generators do
  import StreamData
  alias A2A.Types.{Message, Part, TaskStatus, Task, Artifact}

  def role, do: member_of([:user, :agent])
  def task_state, do: member_of([:submitted, :working, :completed, :failed, :canceled, :input_required, :rejected, :auth_required])

  def json_value, do: one_of([boolean(), integer(), string(:printable), map_of(string(:alphanumeric, min_length: 1), one_of([boolean(), integer(), string(:printable)]))])

  def metadata, do: map_of(string(:alphanumeric, min_length: 1), json_value())

  def part do
    one_of([
      map(string(:printable), &Part.text/1),
      map(binary(), &Part.raw/1),
      map(string(:printable), &Part.url/1),
      map(metadata(), &Part.data/1)
    ])
  end

  def message do
    gen all id <- string(:alphanumeric, min_length: 1),
            r <- role(),
            parts <- list_of(part(), max_length: 3) do
      %Message{message_id: id, role: r, parts: parts}
    end
  end

  # timestamp: seconds precision only, so encode/decode is exact and oracle-comparable
  def timestamp do
    map(integer(1_500_000_000..1_900_000_000), fn s -> DateTime.from_unix!(s) end)
  end

  # task_status/artifact/task generators compose the above; keep them decode-legal.
end
```
Important: generators must avoid values that legitimately don't round-trip: an empty string in a non-oneof scalar (omitted on encode → decodes to `nil`, not `""`). Either generate non-empty strings for implicit-presence fields, or set them to `nil`. For oneof arms (`Part.text("")`) the empty string DOES round-trip (explicit presence). Document this in the module.

`test/support/fixtures.ex` — `A2A.Test.Fixtures.all/0` returns `[{module, struct}, ...]` hand-built representative instances for each covered type (one non-trivial instance each), reused by Tier 2 and golden tests.

- [ ] **Step 2: Write the round-trip property test (no protoc)**

`test/a2a/json_property_test.exs`:
```elixir
defmodule A2A.JSONPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias A2A.JSON
  alias A2A.Test.Generators

  property "decode(encode(x)) == x for Message" do
    check all m <- Generators.message() do
      {:ok, io} = JSON.encode(m)
      assert {:ok, ^m} = JSON.decode(IO.iodata_to_binary(io), A2A.Types.Message)
    end
  end

  property "decode(encode(x)) == x for Task" do
    check all t <- Generators.task() do
      {:ok, io} = JSON.encode(t)
      assert {:ok, ^t} = JSON.decode(IO.iodata_to_binary(io), A2A.Types.Task)
    end
  end
end
```

- [ ] **Step 3: Run the property test (no toolchain)**

Run: `mix test test/a2a/json_property_test.exs`
Expected: PASS. Fix any generator that produces non-round-tripping values (see Step 1 note) rather than weakening the assertion.

- [ ] **Step 4: Write the int64 synthetic test (no protoc)**

`int64` has no real proto field, so test the codec helpers directly in `test/a2a/json_test.exs`:
```elixir
  test "int64 synthetic: encode as decimal string, decode from string or number" do
    assert JSON.encode_scalar(:int64, 9_000_000_000) == "9000000000"
    # decode is exercised through a synthetic field spec:
    field = A2A.Types.Field.new(name: :big, proto_name: "big", number: 1, type: :int64)
    defmodule SyntheticInt64 do
      def __a2a_fields__, do: [A2A.Types.Field.new(name: :big, proto_name: "big", number: 1, type: :int64)]
      defstruct [:big]
    end
    assert {:ok, %{big: 9_000_000_000}} = JSON.from_json_map(%{"big" => "9000000000"}, SyntheticInt64)
    assert {:ok, %{big: 42}} = JSON.from_json_map(%{"big" => 42}, SyntheticInt64)
    _ = field
  end
```
(Define `SyntheticInt64` at top-level in the test file, not inside the test, if the inline `defmodule` is awkward — move it to `test/support/`.)

- [ ] **Step 5: Capture golden files and write the golden round-trip test (no protoc)**

Create a small set of `test/support/golden/*.json` — canonical proto3-JSON captured from the reference SDKs / spec examples for representative covered types (at minimum: `message.json`, `task.json`, `part_file.json`, `stream_status_update.json`). For each, assert our decode→encode reproduces the same JSON **as decoded maps** (key-order independent):
```elixir
defmodule A2A.GoldenTest do
  use ExUnit.Case, async: true
  alias A2A.JSON

  @cases [
    {"message.json", A2A.Types.Message},
    {"task.json", A2A.Types.Task}
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
```
Populate the golden files by hand from the A2A spec examples / reference-SDK output; keep them minimal and valid proto3-JSON (camelCase keys, `TASK_STATE_*`/`ROLE_*` enum strings, base64 bytes, RFC3339 timestamps).

- [ ] **Step 6: Write the proto-conformance test (Tier 1 + Tier 2, `@tag :proto`)**

`test/a2a/proto_conformance_test.exs`:
```elixir
defmodule A2A.ProtoConformanceTest do
  use ExUnit.Case, async: false
  @moduletag :proto

  alias A2A.{JSON}
  alias A2A.Test.{Coverage, Fixtures}

  # Adjust to the namespace produced by `mix a2a.gen_proto` (Task 10 Step 3).
  # Maps proto message name -> generated oracle module.
  defp oracle_module(name), do: Module.concat([A2a, Oracle, Lf, A2a, V1, name])

  defp proto_message_names do
    # Introspect the generated file descriptors for all message names in a2a.proto.
    # Implementation depends on the elixir-protobuf version; e.g. iterate modules
    # under the oracle namespace exporting `descriptor/0` and collect their names.
    Coverage.all_expected() # placeholder: replace with descriptor introspection
  end

  describe "Tier 1 — completeness partition" do
    test "every proto message is either covered or explicitly deferred" do
      all = proto_message_names()
      assert MapSet.disjoint?(Coverage.covered_messages(), Coverage.deferred_names())
      assert MapSet.union(Coverage.covered_messages(), Coverage.deferred_names()) == all,
             "unpartitioned messages (new proto release?): " <>
               inspect(MapSet.difference(all, Coverage.all_expected()) |> MapSet.to_list())
    end

    test "each covered struct's fields match the proto descriptor (name + cardinality)" do
      for {module, _struct} <- Fixtures.all() do
        proto_name = module.__a2a_proto_name__()
        oracle = oracle_module(proto_name)
        # Compare module.__a2a_fields__() (proto_name, number, repeated?) against the
        # oracle descriptor's fields: same set of proto field names & numbers, same
        # repeated-ness. No struct field absent from the proto; no proto field unmapped.
        assert_fields_match(module.__a2a_fields__(), oracle)
      end
    end
  end

  describe "Tier 2 — compliance (differential oracle)" do
    test "A2A.JSON.encode equals the oracle's proto3-JSON for representative instances" do
      for {module, struct} <- Fixtures.all() do
        ours = struct |> JSON.encode!() |> IO.iodata_to_binary() |> Jason.decode!()
        theirs = struct |> to_oracle(module) |> oracle_to_json() |> Jason.decode!()
        assert ours == theirs, "mismatch for #{module.__a2a_proto_name__()}"
      end
    end
  end

  # Helpers `assert_fields_match/2`, `to_oracle/2`, `oracle_to_json/1` bridge our
  # structs to the generated proto structs and invoke the protobuf lib's JSON encoder
  # (`Protobuf.JSON.encode/1` or equivalent for the installed version).
end
```
This test is the one place that binds to the installed `protobuf`/`protoc-gen-elixir` API. Implement `proto_message_names/0` via descriptor introspection over the generated modules, and `to_oracle/2`/`oracle_to_json/1` by mapping each covered struct to its generated counterpart and calling the lib's proto3-JSON encoder. Iterate against the real toolchain (Task 10 Step 3 output). If the installed protobuf lib's JSON support is incomplete for a given well-known type, fall back to the golden files for that type and note it — the oracle is a convenience layer, the golden files are canonical (spec §8).

- [ ] **Step 7: Run non-proto tests, then the proto group**

Run (must be green with no toolchain):
```bash
mix test
```
Then, with the toolchain from Task 10 Step 3:
```bash
mix a2a.gen_proto && mix test --only proto
```
Expected: `mix test` green; `--only proto` green with the partition holding and Tier 2 matching (or golden-backed where noted).

- [ ] **Step 8: Commit**

```bash
git add test/support/generators.ex test/support/fixtures.ex test/support/golden test/a2a/proto_conformance_test.exs test/a2a/json_property_test.exs test/a2a/json_test.exs
git commit -m "test: add proto-conformance harness, generators, golden files"
```

---

## Definition of done (verify all)

- [ ] `mix test` green with **no** `protoc` installed (all `:proto` tests excluded).
- [ ] `mix test --only proto` green with the toolchain: Tier 1 partition holds (covered ∪ deferred == all 44 proto messages, disjoint), Tier 2 compliance passes over covered types (oracle or golden-backed).
- [ ] All 12 Phase-1 messages + 2 enums exist as `A2A.Types.*` with `__a2a_fields__/0`; the other 32 messages are in `@deferred` with phase + reason.
- [ ] `A2A.JSON.encode/1` + `decode/2` implement every §4 rule (camelCase, enums, Struct/Value, Timestamp, bytes/base64, tagged unions, `_UNSPECIFIED` rejection, int64-as-string synthetic).
- [ ] Golden-file round-trips pass (modulo key order).
- [ ] `mix format --check-formatted`, `mix credo --strict`, `mix compile --warnings-as-errors`, `mix dialyzer` all clean; `mix docs` builds.

## Self-review notes (spec coverage)

- §2.1 phasing → Task 10 `@deferred` (32 msgs, phases 2–4) + covered (12) = 44. ✓
- §3 idiomatic choices (atoms, `_UNSPECIFIED` rejection, kind-tagged Part/unions, snake_case) → Tasks 2,3,6,7,9. ✓
- §3 field-spec metadata → `A2A.Types.Field` + per-module `__a2a_fields__/0` (Tasks 2–7). ✓
- §4 codec full rule set → Tasks 8–9 (+ int64 synthetic Task 11). ✓
- §5.1 vendoring/codegen/opt-in `:proto` → Task 10 + Task 1 CI. ✓
- §5.2 Tier 1 completeness → Task 11. §5.3 partition manifest → Task 10. §5.4 Tier 2 oracle + golden → Task 11. ✓
- §6 scaffolding, §7 testing layout → Task 1 + test file placement throughout. ✓
- §9 DoD → checklist above. ✓
