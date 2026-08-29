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

    assert %Part{
             kind: :raw,
             raw: <<1, 2, 3>>,
             filename: "a.bin",
             media_type: "application/octet-stream"
           } = p
  end

  test "url/2 and data/2" do
    assert %Part{kind: :url, url: "https://x/y"} = Part.url("https://x/y")
    assert %Part{kind: :data, data: %{"k" => "v"}} = Part.data(%{"k" => "v"})
  end

  test "field spec maps every proto field with oneof grouping" do
    by_name = Map.new(Part.__a2a_fields__(), &{&1.name, &1})

    assert %{
             proto_name: "text",
             number: 1,
             type: :string,
             oneof: {:content, :text},
             presence: :explicit
           } = by_name.text

    assert %{proto_name: "raw", number: 2, type: :bytes, oneof: {:content, :raw}} = by_name.raw
    assert %{proto_name: "url", number: 3, type: :string, oneof: {:content, :url}} = by_name.url
    assert %{proto_name: "data", number: 4, type: :value, oneof: {:content, :data}} = by_name.data
    assert %{proto_name: "metadata", number: 5, type: :struct, oneof: nil} = by_name.metadata
    assert %{proto_name: "filename", number: 6, type: :string} = by_name.filename

    assert %{proto_name: "media_type", number: 7, type: :string, json_name: "mediaType"} =
             by_name.media_type

    assert Part.__a2a_proto_name__() == "Part"
    assert Part.__a2a_discriminator__() == :kind
  end
end
