defmodule A2A.Server.PushSender do
  @moduledoc false
  alias A2A.Types.{StreamResponse, TaskPushNotificationConfig}

  @callback send(TaskPushNotificationConfig.t(), StreamResponse.t(), keyword()) ::
              :ok | {:error, term()}

  @doc """
  The default webhook-URL validator: accepts only `http`/`https` absolute URLs.
  Production deployments SHOULD supply a stricter validator (block internal
  ranges) via the `:push_url_validator` server option to mitigate SSRF (spec §13.2).
  """
  @spec default_url_validator() :: (String.t() -> :ok | {:error, term()})
  def default_url_validator do
    fn url ->
      case URI.new(url) do
        {:ok, %URI{scheme: s, host: h}} when s in ["http", "https"] and is_binary(h) and h != "" ->
          :ok

        _ ->
          {:error, :invalid_url}
      end
    end
  end
end
