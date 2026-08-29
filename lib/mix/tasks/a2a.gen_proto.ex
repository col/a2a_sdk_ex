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
        [
          "--elixir_out=#{@out}",
          "--elixir_opt=package_prefix=a2a.oracle",
          Path.join(@proto_dir, "a2a.proto")
        ]

    case System.cmd(protoc, args, stderr_to_stdout: true) do
      {_out, 0} -> Mix.shell().info("Generated proto modules into #{@out}")
      {out, code} -> Mix.raise("protoc failed (#{code}):\n#{out}")
    end
  end

  defp well_known_includes do
    # google_protos ships the well-known .proto files; add its priv dir if present.
    # `Application.app_dir/1` raises when the app isn't loaded, hence the rescue.
    ["-I", Path.join(Application.app_dir(:google_protos), "priv/protos")]
  rescue
    _ -> []
  end
end
