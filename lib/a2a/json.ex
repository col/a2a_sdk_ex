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

  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
