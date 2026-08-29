defmodule A2A.ProtoConformanceTest do
  @moduledoc """
  Proto-conformance harness. Requires the generated oracle modules produced by
  `mix a2a.gen_proto` (see `test/support/gen/a2a.pb.ex`, git-ignored) — run
  with `mix test --only proto`.

  Tier 1 — completeness/partition: every message defined in `a2a.proto` is
  either covered (has a hand-written `A2A.Types.*` struct) or explicitly
  deferred (`A2A.Test.Coverage.deferred/0`), and the two sets are disjoint.
  Each covered struct's `__a2a_fields__/0` is cross-checked against the
  oracle descriptor (proto_name + number + repeated-ness).

  Tier 2 — compliance (differential oracle): for each representative fixture,
  our `A2A.JSON.encode!/1` output is fed into the *reference* proto3-JSON
  decoder (`Protobuf.JSON`, from the `protobuf` dep) for the corresponding
  oracle module, then re-encoded by the reference encoder. If our JSON is
  both accepted by, and canonical under, the reference implementation, the
  two encodings agree once both are parsed back to maps (key order doesn't
  matter). This is a convenience layer on top of the golden files
  (`test/support/golden/*.json`), which remain the canonical compliance
  check per spec §8.
  """
  use ExUnit.Case, async: false
  @moduletag :proto

  alias A2A.JSON
  alias A2A.Test.{Coverage, Fixtures}
  alias A2A.Types.Enums

  @gen_dir Path.join([__DIR__, "..", "support", "gen"])

  @enum_oracle %{
    task_state: A2a.Oracle.Lf.A2a.V1.TaskState,
    role: A2a.Oracle.Lf.A2a.V1.Role
  }

  defp oracle_module(name), do: Module.concat([A2a, Oracle, Lf, A2a, V1, name])

  # Enumerate every module the generator emitted (one .ex file, many
  # `defmodule`s) by scanning the source rather than relying on
  # `:code.all_loaded/0`, which only reflects modules some other code path
  # has already touched.
  defp oracle_modules do
    case Path.wildcard(Path.join(@gen_dir, "**/*.ex")) do
      [] ->
        raise """
        No generated oracle modules found under #{@gen_dir}.
        Run `mix a2a.gen_proto` (needs protoc + the protoc-gen-elixir plugin) \
        before `mix test --only proto`.
        """

      files ->
        files
        |> Enum.flat_map(fn file ->
          file
          |> File.read!()
          |> then(&Regex.scan(~r/defmodule\s+(A2a\.Oracle\.Lf\.A2a\.V1\.[A-Za-z0-9_.]+)\s+do/, &1))
        end)
        |> Enum.map(fn [_, dotted] ->
          mod = dotted |> String.split(".") |> Module.concat()
          Code.ensure_loaded!(mod)
          mod
        end)
        |> Enum.uniq()
    end
  end

  # All proto MESSAGE names (excludes enum types and synthetic map-entry
  # messages like `AgentCard.SecuritySchemesEntry`).
  defp proto_message_names do
    for mod <- oracle_modules(),
        function_exported?(mod, :__message_props__, 0),
        props = mod.__message_props__(),
        not props.enum?,
        not props.map?,
        into: MapSet.new() do
      mod |> Module.split() |> List.last()
    end
  end

  defp assert_fields_match(fields, oracle_mod) do
    oracle_field_props = oracle_mod.__message_props__().field_props

    for field <- fields do
      fp =
        Map.get(oracle_field_props, field.number) ||
          flunk(
            "#{inspect(oracle_mod)} has no field numbered #{field.number} " <>
              "(ours: #{field.proto_name})"
          )

      assert fp.name == field.proto_name,
             "field #{field.number} on #{inspect(oracle_mod)}: proto_name mismatch " <>
               "(ours: #{field.proto_name}, oracle: #{fp.name})"

      assert fp.repeated? == (field.cardinality == :repeated),
             "field #{field.proto_name} on #{inspect(oracle_mod)}: cardinality mismatch"
    end

    ours_numbers = MapSet.new(fields, & &1.number)
    oracle_numbers = MapSet.new(Map.keys(oracle_field_props))

    assert ours_numbers == oracle_numbers,
           "#{inspect(oracle_mod)}: field-number sets differ " <>
             "(ours only: #{inspect(MapSet.difference(ours_numbers, oracle_numbers))}, " <>
             "oracle only: #{inspect(MapSet.difference(oracle_numbers, ours_numbers))})"
  end

  defp to_oracle_json(ours, module) do
    oracle_mod = oracle_module(module.__a2a_proto_name__())
    {:ok, oracle_struct} = Protobuf.JSON.decode(ours, oracle_mod)
    Protobuf.JSON.encode!(oracle_struct)
  end

  describe "Tier 1 — completeness partition" do
    test "every proto message is either covered or explicitly deferred" do
      all = proto_message_names()

      assert MapSet.disjoint?(Coverage.covered_messages(), Coverage.deferred_names())

      assert MapSet.union(Coverage.covered_messages(), Coverage.deferred_names()) == all,
             "unpartitioned messages (new proto release?): " <>
               inspect(
                 MapSet.difference(
                   all,
                   MapSet.union(Coverage.covered_messages(), Coverage.deferred_names())
                 )
                 |> MapSet.to_list()
               )
    end

    test "each covered struct's fields match the proto descriptor (name + cardinality)" do
      for {module, _struct} <- Fixtures.all() do
        proto_name = module.__a2a_proto_name__()
        oracle = oracle_module(proto_name)
        assert_fields_match(module.__a2a_fields__(), oracle)
      end
    end

    test "every covered enum's values match the proto descriptor (minus UNSPECIFIED)" do
      for {enum, oracle_mod} <- @enum_oracle do
        Code.ensure_loaded!(oracle_mod)

        oracle_names =
          oracle_mod.mapping()
          |> Map.keys()
          |> Enum.map(&Atom.to_string/1)
          |> Enum.reject(&String.ends_with?(&1, "_UNSPECIFIED"))
          |> MapSet.new()

        ours =
          Enums.atoms(enum)
          |> Enum.map(&Enums.encode!(enum, &1))
          |> MapSet.new()

        assert ours == oracle_names,
               "#{enum}: SDK values #{inspect(MapSet.to_list(ours))} != proto values #{inspect(MapSet.to_list(oracle_names))}"
      end
    end
  end

  describe "Tier 2 — compliance (differential oracle)" do
    test "A2A.JSON.encode equals the oracle's proto3-JSON for representative instances" do
      for {module, struct} <- Fixtures.all() do
        ours = struct |> JSON.encode!() |> IO.iodata_to_binary()
        theirs = to_oracle_json(ours, module)

        assert Jason.decode!(ours) == Jason.decode!(theirs),
               "mismatch for #{module.__a2a_proto_name__()}: ours=#{ours} theirs=#{theirs}"
      end
    end
  end
end
