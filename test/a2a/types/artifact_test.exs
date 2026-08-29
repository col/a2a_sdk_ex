defmodule A2A.Types.ArtifactTest do
  use ExUnit.Case, async: true
  alias A2A.Types.{Artifact, Part}

  test "constructs an artifact and exposes its field spec" do
    a = %Artifact{artifact_id: "a1", parts: [Part.text("x")]}
    assert a.artifact_id == "a1"
    by_name = Map.new(Artifact.__a2a_fields__(), &{&1.name, &1})

    assert %{proto_name: "artifact_id", number: 1, type: :string, json_name: "artifactId"} =
             by_name.artifact_id

    assert %{proto_name: "name", number: 2, type: :string} = by_name.name
    assert %{proto_name: "description", number: 3, type: :string} = by_name.description

    assert %{proto_name: "parts", number: 4, type: {:message, Part}, cardinality: :repeated} =
             by_name.parts

    assert %{proto_name: "metadata", number: 5, type: :struct} = by_name.metadata
    assert %{proto_name: "extensions", number: 6, cardinality: :repeated} = by_name.extensions
    assert Artifact.__a2a_proto_name__() == "Artifact"
  end
end
