defmodule A2A.Server.PushSender.DefaultTest do
  use ExUnit.Case, async: false
  alias A2A.Server.PushSender
  alias A2A.Server.PushSender.Default
  alias A2A.Test.WebhookReceiver
  alias A2A.Types.{AuthenticationInfo, Message, Part, StreamResponse, TaskPushNotificationConfig}

  defp frame do
    StreamResponse.message(%Message{message_id: "m1", role: :agent, parts: [Part.text("hi")]})
  end

  test "build_request uses Authorization when authentication is present" do
    cfg = %TaskPushNotificationConfig{
      url: "https://h/cb",
      authentication: %AuthenticationInfo{scheme: "Bearer", credentials: "tok"}
    }

    {url, headers, content_type, body} = Default.build_request({cfg, frame()})
    assert url == "https://h/cb"
    assert content_type == "application/a2a+json"
    assert {"Authorization", "Bearer tok"} in headers
    assert {:ok, %StreamResponse{}} = A2A.JSON.decode(body, StreamResponse)
  end

  test "build_request falls back to the notification-token header" do
    cfg = %TaskPushNotificationConfig{url: "https://h/cb", token: "abc"}
    {_url, headers, _ct, _body} = Default.build_request({cfg, frame()})
    assert {"X-A2A-Notification-Token", "abc"} in headers
    refute Enum.any?(headers, fn {k, _} -> k == "Authorization" end)
  end

  test "build_request emits no auth headers when neither authentication nor token is set" do
    cfg = %TaskPushNotificationConfig{url: "https://h/cb"}
    {_url, headers, _ct, _body} = Default.build_request({cfg, frame()})
    assert headers == []
  end

  test "default_url_validator accepts http(s) and rejects others" do
    v = PushSender.default_url_validator()
    assert :ok = v.("https://ok/cb")
    assert :ok = v.("http://ok/cb")
    assert {:error, _} = v.("ftp://nope")
    assert {:error, _} = v.("not-a-url")
  end

  @tag :integration
  test "Default.send POSTs the serialized frame with headers to a live endpoint" do
    {base, srv} = WebhookReceiver.start(self())
    on_exit(fn -> Process.exit(srv, :normal) end)

    cfg = %TaskPushNotificationConfig{url: base <> "/cb", token: "abc"}
    assert :ok = Default.send(cfg, frame())

    assert_receive {:webhook, headers, body}, 2_000
    assert {"content-type", "application/a2a+json"} in downcase(headers)
    assert {"x-a2a-notification-token", "abc"} in downcase(headers)
    assert {:ok, %StreamResponse{}} = A2A.JSON.decode(body, StreamResponse)
  end

  defp downcase(headers), do: Enum.map(headers, fn {k, v} -> {String.downcase(k), v} end)
end
