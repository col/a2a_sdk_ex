defmodule A2A.Types.Enums do
  @moduledoc "Atom ⇄ proto3-JSON mappings for the A2A enums."

  @type task_state ::
          :submitted
          | :working
          | :completed
          | :failed
          | :canceled
          | :input_required
          | :rejected
          | :auth_required

  @type role :: :user | :agent

  @enums %{
    task_state: %{
      submitted: {1, "TASK_STATE_SUBMITTED"},
      working: {2, "TASK_STATE_WORKING"},
      completed: {3, "TASK_STATE_COMPLETED"},
      failed: {4, "TASK_STATE_FAILED"},
      canceled: {5, "TASK_STATE_CANCELED"},
      input_required: {6, "TASK_STATE_INPUT_REQUIRED"},
      rejected: {7, "TASK_STATE_REJECTED"},
      auth_required: {8, "TASK_STATE_AUTH_REQUIRED"}
    },
    role: %{
      user: {1, "ROLE_USER"},
      agent: {2, "ROLE_AGENT"}
    }
  }

  @proto_type_names %{task_state: "TaskState", role: "Role"}

  @spec proto_names() :: [String.t()]
  def proto_names, do: Map.values(@proto_type_names)

  @spec atoms(atom) :: [atom]
  def atoms(enum), do: Map.keys(Map.fetch!(@enums, enum))

  @spec encode(atom, atom) :: {:ok, String.t()} | {:error, term}
  def encode(enum, atom) do
    case @enums |> Map.fetch!(enum) |> Map.get(atom) do
      {_num, name} -> {:ok, name}
      nil -> {:error, {:unknown_enum_value, enum, atom}}
    end
  end

  @spec encode!(atom, atom) :: String.t()
  def encode!(enum, atom) do
    case encode(enum, atom) do
      {:ok, name} -> name
      {:error, reason} -> raise ArgumentError, "invalid #{enum}: #{inspect(reason)}"
    end
  end

  @spec decode(atom, String.t() | integer) :: {:ok, atom} | {:error, term}
  def decode(enum, value) do
    table = Map.fetch!(@enums, enum)

    match =
      Enum.find(table, fn
        {_atom, {num, name}} -> value == num or value == name
      end)

    case match do
      {atom, _} -> {:ok, atom}
      nil -> {:error, {:unknown_enum_value, enum, value}}
    end
  end
end
