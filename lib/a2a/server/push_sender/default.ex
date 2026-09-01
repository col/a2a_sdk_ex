defmodule A2A.Server.PushSender.Default do
  @moduledoc false
  @behaviour A2A.Server.PushSender

  alias A2A.Types.{StreamResponse, TaskPushNotificationConfig}

  @content_type "application/a2a+json"
  @default_timeout 5_000

  @impl true
  def send(%TaskPushNotificationConfig{} = config, %StreamResponse{} = frame, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    {url, headers, content_type, body} = build_request({config, frame})
    post(url, headers, content_type, body, timeout)
  end

  @doc "Pure: builds `{url, auth_headers, content_type, body}` for a dispatch."
  @spec build_request({TaskPushNotificationConfig.t(), StreamResponse.t()}) ::
          {String.t(), [{String.t(), String.t()}], String.t(), binary()}
  def build_request({%TaskPushNotificationConfig{url: url} = config, %StreamResponse{} = frame}) do
    {url, auth_headers(config), @content_type, A2A.JSON.encode!(frame)}
  end

  defp auth_headers(%TaskPushNotificationConfig{authentication: %{scheme: s, credentials: c}})
       when is_binary(s) and is_binary(c) and s != "" and c != "",
       do: [{"Authorization", "#{s} #{c}"}]

  defp auth_headers(%TaskPushNotificationConfig{token: t}) when is_binary(t) and t != "",
    do: [{"X-A2A-Notification-Token", t}]

  defp auth_headers(_), do: []

  defp post(url, headers, content_type, body, timeout) do
    if Code.ensure_loaded?(Req),
      do: post_req(url, headers, content_type, body, timeout),
      else: post_httpc(url, headers, content_type, body, timeout)
  end

  defp post_req(url, headers, content_type, body, timeout) do
    all = [{"content-type", content_type} | headers]

    case Req.post(url, body: body, headers: all, receive_timeout: timeout, retry: false) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp post_httpc(url, headers, content_type, body, timeout) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    hdrs = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
    request = {String.to_charlist(url), hdrs, String.to_charlist(content_type), body}

    case :httpc.request(:post, request, [timeout: timeout], []) do
      {:ok, {{_v, status, _r}, _h, _b}} when status in 200..299 -> :ok
      {:ok, {{_v, status, _r}, _h, _b}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
