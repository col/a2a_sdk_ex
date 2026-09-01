defmodule A2A.Client.HTTP.ReqTest do
  use ExUnit.Case, async: true
  alias A2A.Client.HTTP.Req, as: Adapter

  test "request/1 performs a unary request" do
    Req.Test.stub(A2A.Client.HTTP.Req, fn conn ->
      assert conn.method == "POST"
      Req.Test.json(conn, %{"ok" => true})
    end)

    req = %{
      method: :post,
      url: "http://example.com/",
      headers: [{"content-type", "application/json"}],
      body: "{}",
      opts: [timeout: 1000, req: [plug: {Req.Test, A2A.Client.HTTP.Req}]]
    }

    assert {:ok, %{status: 200, body: body}} = Adapter.request(req)
    assert body =~ "ok"
  end

  test "stream/1 returns an enumerable body of chunks" do
    Req.Test.stub(A2A.Client.HTTP.Req, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_chunked(200)
      |> then(fn c ->
        {:ok, c} = Plug.Conn.chunk(c, "data: 1\n\n")
        c
      end)
    end)

    req = %{
      method: :get,
      url: "http://example.com/",
      headers: [],
      body: nil,
      opts: [stream_timeout: 1000, req: [plug: {Req.Test, A2A.Client.HTTP.Req}]]
    }

    assert {:ok, %{status: 200, body: async}} = Adapter.stream(req)
    assert Enum.join(Enum.to_list(async)) =~ "data: 1"
  end
end
