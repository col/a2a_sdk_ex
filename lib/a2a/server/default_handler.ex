defmodule A2A.Server.DefaultHandler do
  @moduledoc """
  Batteries-included `RequestHandler`. Phase 1: blocking `send_message/2` and `get_task/2`.
  It subscribes to the task topic *before* starting the execution process, then drains
  the event stream through `ResultAssembler` to the terminal (or `input_required`) frame.
  """
  @behaviour A2A.Server.RequestHandler

  alias A2A.Server.{Events, Execution, RequestContext, ResultAssembler}
  alias A2A.Server.Events.Event
  alias A2A.Types.{GetTaskRequest, Message, SendMessageRequest, Task}

  @drain_timeout 30_000

  @impl true
  @spec send_message(A2A.Server.t(), SendMessageRequest.t()) ::
          {:ok, Task.t()} | {:error, A2A.Error.t()}
  def send_message(%A2A.Server{} = server, %SendMessageRequest{message: %Message{} = message} = req) do
    task_id = message.task_id || server.id_generator.()
    context_id = message.context_id || server.id_generator.()

    with :ok <- reject_terminal(server, task_id) do
      ctx = %RequestContext{
        message: message,
        task_id: task_id,
        context_id: context_id,
        task: nil,
        user: A2A.User.anonymous(),
        config: req.configuration || %{}
      }

      :ok = Events.subscribe(server.pubsub, task_id)

      arg = %{
        task_id: task_id,
        context_id: context_id,
        executor: server.executor,
        context: ctx,
        updater_opts: [pubsub: server.pubsub, store: server.store, scope: server.scope],
        registry: server.registry
      }

      case Execution.start(server.dyn_sup, server.registry, arg) do
        {:ok, _pid} ->
          result = drain(ResultAssembler.init(task_id, context_id))
          :ok = Events.unsubscribe(server.pubsub, task_id)
          result

        {:error, {:already_started, _}} ->
          {:error, %A2A.Error{code: :task_in_progress, message: "task already running"}}

        {:error, reason} ->
          {:error, %A2A.Error{code: :internal_error, message: inspect(reason)}}
      end
    end
  end

  @impl true
  @spec get_task(A2A.Server.t(), GetTaskRequest.t()) :: {:ok, Task.t()} | {:error, A2A.Error.t()}
  def get_task(%A2A.Server{} = server, %GetTaskRequest{id: id}) do
    case server.store.get(id, server.scope) do
      {:ok, task} -> {:ok, task}
      {:error, :not_found} -> {:error, A2A.Error.not_found(id)}
    end
  end

  defp reject_terminal(server, task_id) do
    case server.store.get(task_id, server.scope) do
      {:ok, task} ->
        if ResultAssembler.terminal?(task),
          do: {:error, A2A.Error.terminal_task(task_id)},
          else: :ok

      {:error, :not_found} ->
        :ok
    end
  end

  defp drain(acc) do
    receive do
      %Event{payload: payload, terminal?: true} -> {:ok, ResultAssembler.apply(acc, payload)}
      %Event{payload: payload} -> drain(ResultAssembler.apply(acc, payload))
    after
      @drain_timeout ->
        {:error, %A2A.Error{code: :timeout, message: "timed out draining task events"}}
    end
  end
end
