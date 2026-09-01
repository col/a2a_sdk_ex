defmodule A2A.Client.ConfigTest do
  use ExUnit.Case, async: true
  alias A2A.Client.Config

  test "new/1 applies defaults" do
    c = Config.new([])
    assert c.http_client == A2A.Client.HTTP.Req
    assert c.streaming? == true
    assert c.timeout == 30_000
    assert c.stream_timeout == 120_000
    assert c.protocol_version == "1.0"
    assert c.preferred_transports == []
  end

  test "new/1 overrides provided keys" do
    c = Config.new(stream_timeout: 5_000, preferred_transports: ["JSONRPC"], http_client: MyMod)
    assert c.stream_timeout == 5_000
    assert c.preferred_transports == ["JSONRPC"]
    assert c.http_client == MyMod
  end
end
