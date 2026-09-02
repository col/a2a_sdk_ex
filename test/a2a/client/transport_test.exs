defmodule A2A.Client.TransportTest do
  use ExUnit.Case, async: true
  alias A2A.Client.Config
  alias A2A.Client.Transport

  defp client(opts) do
    %A2A.Client{endpoint: "http://x", config: Config.new(opts)}
  end

  test "base_headers merges defaults, config, and per-call (opts win)" do
    client = client(headers: [{"authorization", "Bearer a"}], protocol_version: "1.0")
    headers = Transport.base_headers(client.config, headers: [{"authorization", "Bearer b"}])
    assert {"content-type", "application/json"} in headers
    assert {"a2a-version", "1.0"} in headers
    assert {"authorization", "Bearer b"} in headers
    refute {"authorization", "Bearer a"} in headers
  end

  test "run/3 wraps transport error via from_transport" do
    defmodule BoomHTTP do
      @behaviour A2A.Client.HTTP
      def request(_), do: {:error, :econnrefused}
      def stream(_), do: {:error, :econnrefused}
    end

    client = client(http_client: BoomHTTP)
    request = %{method: :post, url: "http://x/", headers: [], body: "{}", opts: []}

    assert {:error, %A2A.Error{code: :internal_error, data: :econnrefused}} =
             Transport.run(client, request, :unary)
  end
end
