defmodule A2A.Server.Agent.Result do
  @moduledoc """
  The pure, pipeable value an `A2A.Server.Agent` returns from `handle_message/1`.

  Accumulates *directives* (buffered/streamed artifacts), an optional terminal
  status `message`, and a single `terminal` state. It performs no side effects —
  `A2A.Server.Agent.Interpreter` folds it into `A2A.Server.TaskUpdater` calls.
  Directives are stored reversed and read in author order via `directives/1`.
  """
  alias A2A.Types.Part

  @type parts_input :: String.t() | Part.t() | [String.t() | Part.t()]
  @type directive ::
          {:artifact, String.t() | nil, [Part.t()], keyword()}
          | {:stream, String.t() | nil, Enumerable.t(), keyword()}
  @type terminal :: {:completed | :input_required | :rejected | :failed, keyword()}

  @type t :: %__MODULE__{
          directives: [directive()],
          message: {[Part.t()], keyword()} | nil,
          terminal: terminal() | nil
        }
  defstruct directives: [], message: nil, terminal: nil

  @spec reply() :: t()
  def reply, do: %__MODULE__{}

  @spec artifact(t(), String.t() | nil, parts_input(), keyword()) :: t()
  def artifact(%__MODULE__{} = r, name, parts, opts \\ []),
    do: add_directive(r, {:artifact, name, normalize_parts(parts), opts})

  @spec stream(t(), String.t() | nil, Enumerable.t(), keyword()) :: t()
  def stream(%__MODULE__{} = r, name, enumerable, opts \\ []),
    do: add_directive(r, {:stream, name, enumerable, opts})

  @spec message(t(), parts_input(), keyword()) :: t()
  def message(%__MODULE__{} = r, parts, opts \\ []),
    do: %{r | message: {normalize_parts(parts), opts}}

  @spec complete(t(), keyword()) :: t()
  def complete(%__MODULE__{} = r, opts \\ []),
    do: r |> apply_message(opts) |> put_terminal(:completed)

  @spec input_required(t(), keyword()) :: t()
  def input_required(%__MODULE__{} = r, opts \\ []),
    do: r |> apply_message(opts) |> put_terminal(:input_required)

  @spec reject(t(), String.t() | nil) :: t()
  def reject(%__MODULE__{} = r, reason \\ nil),
    do: r |> reason_message(reason) |> put_terminal(:rejected)

  @spec fail(t(), String.t()) :: t()
  def fail(%__MODULE__{} = r, reason) when is_binary(reason),
    do: r |> reason_message(reason) |> put_terminal(:failed)

  @spec directives(t()) :: [directive()]
  def directives(%__MODULE__{directives: d}), do: Enum.reverse(d)

  # --- internal ---

  defp add_directive(r, d), do: %{r | directives: [d | r.directives]}

  defp put_terminal(%__MODULE__{terminal: nil} = r, state), do: %{r | terminal: {state, []}}

  defp put_terminal(%__MODULE__{}, _state),
    do: raise(ArgumentError, "terminal already set — a Result may declare only one terminal")

  # `complete`/`input_required` opts sugar: :message sets the status message,
  # :metadata rides on that message (TaskStatus itself has no metadata field).
  defp apply_message(r, opts) do
    case {Keyword.get(opts, :message), Keyword.get(opts, :metadata)} do
      {nil, nil} -> r
      {nil, meta} -> message(r, [], metadata: meta)
      {parts, nil} -> message(r, parts, [])
      {parts, meta} -> message(r, parts, metadata: meta)
    end
  end

  defp reason_message(r, nil), do: r
  defp reason_message(r, reason) when is_binary(reason), do: message(r, reason, [])

  defp normalize_parts(parts), do: parts |> List.wrap() |> Enum.map(&normalize_part/1)
  defp normalize_part(p) when is_binary(p), do: Part.text(p)
  defp normalize_part(%Part{} = p), do: p
end
