defmodule A2A.Server.AgentCardURL do
  @moduledoc """
  Resolves an `AgentCard`'s transport URLs at serve time. Each
  `supported_interfaces` entry with `url: nil` is filled from the request `conn`
  (scheme, host, port, mount path via `script_name`); a non-nil `url` — an
  author-pinned canonical URL — is left untouched. Behind a reverse proxy the
  `conn` sees the internal address, so pin the URL explicitly there.
  """
  alias A2A.Types.{AgentCard, AgentInterface}

  @spec resolve(AgentCard.t(), Plug.Conn.t()) :: AgentCard.t()
  def resolve(%AgentCard{supported_interfaces: interfaces} = card, conn) do
    base = base_url(conn)
    %{card | supported_interfaces: Enum.map(interfaces, &fill(&1, base))}
  end

  defp fill(%AgentInterface{url: nil} = interface, base), do: %{interface | url: base}
  defp fill(%AgentInterface{} = interface, _base), do: interface

  defp base_url(conn) do
    scheme = Atom.to_string(conn.scheme)
    "#{scheme}://#{authority(scheme, conn.host, conn.port)}#{mount_path(conn.script_name)}"
  end

  defp authority(scheme, host, port) do
    if default_port?(scheme, port), do: host, else: "#{host}:#{port}"
  end

  defp default_port?("http", 80), do: true
  defp default_port?("https", 443), do: true
  defp default_port?(_scheme, _port), do: false

  defp mount_path([]), do: "/"
  defp mount_path(segments), do: "/" <> Enum.join(segments, "/") <> "/"
end
