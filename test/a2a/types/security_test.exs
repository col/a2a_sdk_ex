defmodule A2A.Types.SecurityTest do
  use ExUnit.Case, async: true
  alias A2A.JSON
  alias A2A.Types.{SecurityRequirement, StringList}

  test "StringList round-trips" do
    sl = %StringList{list: ["read", "write"]}
    {:ok, io} = JSON.encode(sl)
    assert %{"list" => ["read", "write"]} = Jason.decode!(IO.iodata_to_binary(io))
    assert {:ok, ^sl} = JSON.decode(IO.iodata_to_binary(io), StringList)
  end

  test "SecurityRequirement encodes schemes as map<string, StringList>" do
    req = %SecurityRequirement{schemes: %{"oauth" => %StringList{list: ["read"]}}}
    {:ok, io} = JSON.encode(req)

    assert %{"schemes" => %{"oauth" => %{"list" => ["read"]}}} =
             Jason.decode!(IO.iodata_to_binary(io))

    assert {:ok, ^req} = JSON.decode(IO.iodata_to_binary(io), SecurityRequirement)
  end

  test "empty map field is omitted on encode" do
    {:ok, io} = JSON.encode(%SecurityRequirement{schemes: %{}})
    assert Jason.decode!(IO.iodata_to_binary(io)) == %{}
  end
end
