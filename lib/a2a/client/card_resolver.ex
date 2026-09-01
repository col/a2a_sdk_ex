defmodule A2A.Client.CardResolver do
  @moduledoc "Fetches + decodes an AgentCard from a base URL's well-known path."
  alias A2A.Client.{Config, Error, Transport}
  alias A2A.Types.AgentCard

  @well_known "/.well-known/agent-card.json"

  @spec resolve(String.t(), Config.t(), keyword()) ::
          {:ok, AgentCard.t()} | {:error, A2A.Error.t()}
  def resolve(base_url, %Config{} = config, opts) do
    path = Keyword.get(opts, :agent_card_path, @well_known)
    url = String.trim_trailing(base_url, "/") <> path

    headers = Transport.base_headers(config, opts)

    req = %{
      method: :get,
      url: url,
      headers: headers,
      body: nil,
      opts: Keyword.merge(config.http_opts, timeout: config.timeout)
    }

    case config.http_client.request(req) do
      {:ok, %{status: s, body: b}} when s in 200..299 -> decode(b)
      {:ok, %{status: s, body: b}} -> {:error, Error.from_rest(s, b)}
      {:error, reason} -> {:error, Error.from_transport(reason)}
    end
  end

  defp decode(body) do
    with {:ok, map} <- Jason.decode(body),
         {:ok, %AgentCard{} = card} <- A2A.JSON.from_json_map(map, AgentCard) do
      {:ok, card}
    else
      {:error, reason} ->
        {:error, %A2A.Error{code: :invalid_agent_response, message: inspect(reason)}}
    end
  end
end
