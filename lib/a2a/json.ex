defmodule A2A.JSON do
  @moduledoc """
  proto3-JSON codec for the A2A type surface. Driven entirely by each struct's
  `__a2a_fields__/0` spec. `encode/1` and `decode/2` are the public surface;
  `to_json_map/1` and `from_json_map/2` expose the intermediate map layer.
  """
  alias A2A.Types.Enums

  @doc """
  Encodes an `A2A.Types.*` struct to proto3-JSON iodata.

  Assumes `struct` was built via the `A2A.Types.*` constructors/literals (i.e.
  every enum field holds a valid atom for its enum type and every nested
  message field holds a valid nested struct). Given such a struct this always
  succeeds; it is not a general-purpose validator. If an enum field holds an
  atom that isn't a member of its enum, this raises `ArgumentError` (via
  `A2A.Types.Enums.encode!/2`) rather than returning `{:error, _}`.
  """
  @spec encode(struct) :: {:ok, iodata} | {:error, term}
  def encode(struct), do: struct |> to_json_map() |> Jason.encode()

  @doc "Like `encode/1`, but returns iodata directly and raises on failure."
  @spec encode!(struct) :: iodata
  def encode!(struct), do: struct |> to_json_map() |> Jason.encode!()

  @doc "Encodes an `A2A.Types.*` struct into a plain proto3-JSON-shaped map (no `Jason.encode/1` pass)."
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
    case DateTime.shift_zone(dt, "Etc/UTC") do
      {:ok, utc} ->
        DateTime.to_iso8601(utc)

      {:error, _} ->
        # Fallback for time zone databases that can't shift a non-UTC source
        # even toward "Etc/UTC" (shouldn't happen with the default UTC-only
        # database, but keep the codec correct regardless): normalize the
        # instant manually and rewrite the zone/offset fields to UTC.
        total_offset = dt.utc_offset + dt.std_offset

        dt
        |> DateTime.add(-total_offset, :second)
        |> Map.merge(%{utc_offset: 0, std_offset: 0, zone_abbr: "UTC", time_zone: "Etc/UTC"})
        |> DateTime.to_iso8601()
    end
  end

  @doc """
  Decodes a proto3-JSON binary into an `A2A.Types.*` struct.

  Accepts both camelCase and original proto field names, enum names or their
  numeric tags, and any of the base64 variants (standard/URL-safe,
  padded/unpadded). Returns `{:error, reason}` on malformed JSON or a value
  that doesn't conform to the target struct's field spec.
  """
  @spec decode(binary, module) :: {:ok, struct} | {:error, term}
  def decode(json, module) when is_binary(json) do
    with {:ok, map} <- Jason.decode(json), do: from_json_map(map, module)
  end

  @doc "Like `decode/2`, but returns the struct directly and raises `ArgumentError` on failure."
  @spec decode!(binary, module) :: struct
  def decode!(json, module) do
    case decode(json, module) do
      {:ok, struct} -> struct
      {:error, reason} -> raise ArgumentError, "A2A.JSON.decode failed: #{inspect(reason)}"
    end
  end

  @doc "Decodes a plain proto3-JSON-shaped map into an `A2A.Types.*` struct (no `Jason.decode/1` pass)."
  @spec from_json_map(map, module) :: {:ok, struct} | {:error, term}
  def from_json_map(map, module) when is_map(map) do
    fields = module.__a2a_fields__()

    result =
      Enum.reduce_while(fields, {:ok, struct(module)}, fn field, {:ok, acc} ->
        decode_into(map, field, acc)
      end)

    with {:ok, struct} <- result, do: {:ok, set_discriminator(module, struct)}
  end

  defp decode_into(map, field, acc) do
    case fetch(map, field) do
      :missing -> {:cont, {:ok, acc}}
      {:ok, raw} -> decode_into_field(field, raw, acc)
    end
  end

  defp decode_into_field(field, raw, acc) do
    case decode_field(field, raw) do
      {:ok, value} -> {:cont, {:ok, Map.put(acc, field.name, value)}}
      {:error, _} = err -> {:halt, err}
    end
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

  defp decode_scalar(:int64, v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> {:ok, n}
      _ -> {:error, {:invalid_int64, v}}
    end
  end

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
      tag = module.__a2a_fields__() |> Enum.find_value(&oneof_tag_if_set(&1, struct))
      Map.put(struct, disc, tag)
    else
      struct
    end
  end

  defp oneof_tag_if_set(%{oneof: {_group, tag}} = field, struct) do
    if Map.get(struct, field.name) != nil, do: tag
  end

  defp oneof_tag_if_set(_field, _struct), do: nil
end
