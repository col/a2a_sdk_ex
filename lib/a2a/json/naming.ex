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
