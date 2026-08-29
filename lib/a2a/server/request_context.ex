defmodule A2A.Server.RequestContext do
  @moduledoc "The read-side context handed to an `AgentExecutor`."
  alias A2A.Types.{Message, Part, Task}

  @type t :: %__MODULE__{
          message: Message.t() | nil,
          task_id: String.t(),
          context_id: String.t(),
          task: Task.t() | nil,
          user: A2A.User.t(),
          config: map(),
          requested_extensions: [String.t()],
          metadata: map()
        }
  defstruct [
    :message,
    :task_id,
    :context_id,
    :task,
    :user,
    config: %{},
    requested_extensions: [],
    metadata: %{}
  ]

  @spec user_input(t()) :: String.t()
  def user_input(%__MODULE__{message: %Message{parts: parts}}) do
    parts
    |> Enum.filter(&match?(%Part{kind: :text}, &1))
    |> Enum.map_join("", & &1.text)
  end

  def user_input(%__MODULE__{message: nil}), do: ""
end
