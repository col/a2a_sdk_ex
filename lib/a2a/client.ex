defmodule A2A.Client do
  @moduledoc """
  A2A client. Build one with `connect/2`, then call the operation functions.
  The struct is a plain value — hold it, pass it, discard it; it starts no
  process. See `docs/superpowers/specs/2026-09-01-a2a-client-design.md`.
  """
  @type t :: %__MODULE__{
          agent_card: A2A.Types.AgentCard.t(),
          transport: module(),
          endpoint: String.t(),
          config: A2A.Client.Config.t()
        }
  defstruct [:agent_card, :transport, :endpoint, :config]

  alias A2A.Client.{CardResolver, Config}

  @spec fetch_agent_card(String.t(), keyword()) ::
          {:ok, A2A.Types.AgentCard.t()} | {:error, A2A.Error.t()}
  def fetch_agent_card(url, opts \\ []) when is_binary(url) do
    {config_opts, resolve_opts} = Keyword.split(opts, config_keys())
    CardResolver.resolve(url, Config.new(config_opts), resolve_opts)
  end

  # Keys that belong to Config; everything else passes through to the resolver/opts.
  defp config_keys,
    do: [
      :http_client,
      :http_opts,
      :headers,
      :preferred_transports,
      :streaming?,
      :timeout,
      :stream_timeout,
      :protocol_version
    ]
end
