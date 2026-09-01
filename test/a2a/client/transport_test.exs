defmodule A2A.Client.TransportTest do
  use ExUnit.Case, async: true
  alias A2A.Client.Config
  alias A2A.Client.Transport

  defp client(opts) do
    %A2A.Client{endpoint: "http://x", config: Config.new(opts)}
  end

  test "base_headers merges defaults, config, and per-call (opts win)" do
    c = client(headers: [{"authorization", "Bearer a"}], protocol_version: "1.0")
    h = Transport.base_headers(c, headers: [{"authorization", "Bearer b"}])
    assert {"content-type", "application/json"} in h
    assert {"a2a-version", "1.0"} in h
    assert {"authorization", "Bearer b"} in h
    refute {"authorization", "Bearer a"} in h
  end

  test "run/3 wraps transport error via from_transport" do
    defmodule BoomHTTP do
      @behaviour A2A.Client.HTTP
      def request(_), do: {:error, :econnrefused}
      def stream(_), do: {:error, :econnrefused}
    end

    c = client(http_client: BoomHTTP)
    req = %{method: :post, url: "http://x/", headers: [], body: "{}", opts: []}

    assert {:error, %A2A.Error{code: :internal_error, data: :econnrefused}} =
             Transport.run(c, req, :unary)
  end
end
