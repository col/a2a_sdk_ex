defmodule A2A.Client.HTTP.Req do
  @moduledoc """
  Default `A2A.Client.HTTP` adapter, backed by `Req`. Requires the optional `:req`
  dependency. Compose retries/tracing/auth-refresh by passing Req options under
  the per-call `opts[:req]` keyword, or inject your own `A2A.Client.HTTP` module.
  """
  @behaviour A2A.Client.HTTP

  @impl true
  def request(%{opts: opts} = req) do
    ensure_req!()
    run(req, receive_timeout: timeout(opts, :timeout))
  end

  @impl true
  def stream(%{opts: opts} = req) do
    ensure_req!()
    run(req, receive_timeout: timeout(opts, :stream_timeout), into: :self)
  end

  defp run(%{method: m, url: url, headers: headers, body: body, opts: opts}, extra) do
    base = [method: m, url: url, headers: headers, retry: false, decode_body: false]
    base = if body, do: Keyword.put(base, :body, body), else: base
    all = base |> Keyword.merge(extra) |> Keyword.merge(Keyword.get(opts, :req, []))

    case Req.request(all) do
      {:ok, %Req.Response{status: s, headers: h, body: b}} ->
        {:ok, %{status: s, headers: flatten(h), body: b}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp timeout(opts, key), do: Keyword.get(opts, key, 30_000)

  # Req::Response.headers is always a map of lists; flatten to a keyword-ish list.
  defp flatten(headers), do: for({k, vs} <- headers, v <- List.wrap(vs), do: {k, v})

  defp ensure_req! do
    Code.ensure_loaded?(Req) ||
      raise "A2A.Client.HTTP.Req requires the :req dependency. Add {:req, \"~> 0.5\"} or set a :http_client in A2A.Client.Config."
  end
end
