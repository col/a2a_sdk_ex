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
      Field.new(
        name: :text,
        proto_name: "text",
        number: 1,
        type: :string,
        presence: :explicit,
        oneof: {:content, :text}
      ),
      Field.new(
        name: :raw,
        proto_name: "raw",
        number: 2,
        type: :bytes,
        presence: :explicit,
        oneof: {:content, :raw}
      ),
      Field.new(
        name: :url,
        proto_name: "url",
        number: 3,
        type: :string,
        presence: :explicit,
        oneof: {:content, :url}
      ),
      Field.new(
        name: :data,
        proto_name: "data",
        number: 4,
        type: :value,
        presence: :explicit,
        oneof: {:content, :data}
      ),
      Field.new(name: :metadata, proto_name: "metadata", number: 5, type: :struct),
      Field.new(name: :filename, proto_name: "filename", number: 6, type: :string),
      Field.new(name: :media_type, proto_name: "media_type", number: 7, type: :string)
    ]
  end
end
