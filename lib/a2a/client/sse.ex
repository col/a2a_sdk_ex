defmodule A2A.Client.SSE do
  @moduledoc """
  Minimal Server-Sent Events parser: turns a lazy enumerable of raw binary body
  chunks into a lazy enumerable of event `data` payloads. Events are separated by
  a blank line; `data:` lines within an event are joined with `\\n`. Comment lines
  (starting `:`) and other fields are ignored — the A2A wire uses only `data:`.
  """
  @spec frames(Enumerable.t()) :: Enumerable.t()
  def frames(chunks) do
    chunks
    |> Stream.transform(
      fn -> "" end,
      &split_events/2,
      &flush_leftover/1,
      fn _acc -> :ok end
    )
    |> Stream.map(&event_data/1)
    |> Stream.reject(&(&1 == nil))
  end

  # On stream exhaustion, flush a non-empty leftover buffer as a final event.
  defp flush_leftover(""), do: {[], ""}
  defp flush_leftover(buffer), do: {[buffer], ""}

  # Accumulate the buffer, emit each complete event (delimited by "\n\n").
  defp split_events(chunk, buffer) do
    data = buffer <> chunk
    parts = String.split(data, "\n\n")
    {complete, [rest]} = Enum.split(parts, -1)
    {complete, rest}
  end

  # Extract and fold the `data:` lines of one raw event block; nil if none.
  defp event_data(event_block) do
    lines =
      event_block
      |> String.split("\n")
      |> Enum.flat_map(fn line ->
        case line do
          "data:" <> rest -> [strip_one_leading_space(rest)]
          _ -> []
        end
      end)

    case lines do
      [] -> nil
      _ -> Enum.join(lines, "\n")
    end
  end

  # SSE spec: strip at most one leading space from a field value, not all of them.
  defp strip_one_leading_space(" " <> rest), do: rest
  defp strip_one_leading_space(value), do: value
end
