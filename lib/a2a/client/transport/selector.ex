defmodule A2A.Client.Transport.Selector do
  @moduledoc """
  Chooses a transport module + endpoint URL from an AgentCard's advertised
  interfaces, reconciled against the client's preferred bindings. Ports the
  reference SDKs' selection (prefer version 1.0; server order unless the client
  states a preference). See the design spec, "transport selection".
  """
  alias A2A.Types.AgentCard

  @impls %{"jsonrpc" => A2A.Client.Transport.JSONRPC, "http+json" => A2A.Client.Transport.REST}

  @spec select(AgentCard.t(), [String.t()]) ::
          {:ok, {module(), String.t()}} | {:error, A2A.Error.t()}
  def select(%AgentCard{supported_interfaces: ifaces}, preferred) when is_list(ifaces) do
    card_bindings = Enum.map(ifaces, & &1.protocol_binding)
    priority = dedup_ci((preferred || []) ++ card_bindings)

    result =
      Enum.find_value(priority, fn binding ->
        with impl when not is_nil(impl) <- Map.get(@impls, downcase(binding)),
             %{url: url} <- best_iface(ifaces, binding) do
          {impl, url}
        else
          _ -> nil
        end
      end)

    case result do
      nil -> {:error, %A2A.Error{code: :unsupported_operation, message: "no compatible transport"}}
      {mod, url} -> {:ok, {mod, url}}
    end
  end

  defp best_iface(ifaces, binding) do
    matching = Enum.filter(ifaces, &(downcase(&1.protocol_binding) == downcase(binding)))
    Enum.find(matching, &(&1.protocol_version == "1.0")) || List.first(matching)
  end

  defp dedup_ci(list) do
    list
    |> Enum.reduce({[], MapSet.new()}, fn b, {acc, seen} ->
      key = downcase(b)
      if MapSet.member?(seen, key), do: {acc, seen}, else: {[b | acc], MapSet.put(seen, key)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp downcase(nil), do: ""
  defp downcase(s), do: String.downcase(s)
end
