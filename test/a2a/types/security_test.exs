defmodule A2A.Types.SecurityTest do
  use ExUnit.Case, async: true
  alias A2A.JSON
  alias A2A.Types.{SecurityRequirement, StringList}

  test "StringList round-trips" do
    sl = %StringList{list: ["read", "write"]}
    {:ok, io} = JSON.encode(sl)
    assert %{"list" => ["read", "write"]} = Jason.decode!(IO.iodata_to_binary(io))
    assert {:ok, ^sl} = JSON.decode(IO.iodata_to_binary(io), StringList)
  end

  test "SecurityRequirement encodes schemes as map<string, StringList>" do
    req = %SecurityRequirement{schemes: %{"oauth" => %StringList{list: ["read"]}}}
    {:ok, io} = JSON.encode(req)

    assert %{"schemes" => %{"oauth" => %{"list" => ["read"]}}} =
             Jason.decode!(IO.iodata_to_binary(io))

    assert {:ok, ^req} = JSON.decode(IO.iodata_to_binary(io), SecurityRequirement)
  end

  test "empty map field is omitted on encode" do
    {:ok, io} = JSON.encode(%SecurityRequirement{schemes: %{}})
    assert Jason.decode!(IO.iodata_to_binary(io)) == %{}
  end

  test "AuthorizationCodeOAuthFlow round-trips with scopes map and pkce" do
    alias A2A.Types.AuthorizationCodeOAuthFlow

    f = %AuthorizationCodeOAuthFlow{
      authorization_url: "https://a.example/auth",
      token_url: "https://a.example/token",
      refresh_url: "https://a.example/refresh",
      scopes: %{"read" => "Read access"},
      pkce_required: true
    }

    {:ok, io} = A2A.JSON.encode(f)
    json = Jason.decode!(IO.iodata_to_binary(io))
    assert json["authorizationUrl"] == "https://a.example/auth"
    assert json["scopes"] == %{"read" => "Read access"}
    assert json["pkceRequired"] == true
    assert {:ok, ^f} = A2A.JSON.decode(IO.iodata_to_binary(io), AuthorizationCodeOAuthFlow)
  end

  test "DeviceCodeOAuthFlow round-trips" do
    alias A2A.Types.DeviceCodeOAuthFlow

    f = %DeviceCodeOAuthFlow{
      device_authorization_url: "https://a.example/device",
      token_url: "https://a.example/token",
      scopes: %{"read" => "Read"}
    }

    {:ok, io} = A2A.JSON.encode(f)
    assert {:ok, ^f} = A2A.JSON.decode(IO.iodata_to_binary(io), DeviceCodeOAuthFlow)
  end

  test "OAuthFlows dispatches on :kind and round-trips" do
    alias A2A.Types.{ClientCredentialsOAuthFlow, OAuthFlows}

    flows =
      OAuthFlows.client_credentials(%ClientCredentialsOAuthFlow{
        token_url: "https://auth.example.com/token",
        scopes: %{"read" => "Read"}
      })

    assert flows.kind == :client_credentials
    {:ok, io} = A2A.JSON.encode(flows)
    json = Jason.decode!(IO.iodata_to_binary(io))
    assert Map.has_key?(json, "clientCredentials")
    assert {:ok, ^flows} = A2A.JSON.decode(IO.iodata_to_binary(io), OAuthFlows)
  end
end
