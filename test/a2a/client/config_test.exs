defmodule A2A.Client.ConfigTest do
  use ExUnit.Case, async: true
  alias A2A.Client.Config

  test "new/1 applies defaults" do
    config = Config.new([])
    assert config.http_client == A2A.Client.HTTP.Req
    assert config.streaming? == true
    assert config.timeout == 30_000
    assert config.stream_timeout == 120_000
    assert config.protocol_version == "1.0"
    assert config.preferred_transports == []
  end

  test "new/1 overrides provided keys" do
    config =
      Config.new(stream_timeout: 5_000, preferred_transports: ["JSONRPC"], http_client: MyMod)

    assert config.stream_timeout == 5_000
    assert config.preferred_transports == ["JSONRPC"]
    assert config.http_client == MyMod
  end
end
