defmodule A2A.Plug.Cache do
  @moduledoc """
  HTTP cache validators for the agent card (specification §8.6).

  The card "changes infrequently relative to the frequency at which clients may
  fetch it", so §8.6.1 asks servers to send `Cache-Control`, an `ETag` "derived
  from the Agent Card's `version` field or a hash of the card content", and
  optionally `Last-Modified`.

  The ETag here hashes the **served body**, not the `version` field: a card whose
  URL or capabilities changed without a version bump would otherwise keep a
  validator that says nothing changed, and a stale card is a worse failure than a
  redundant fetch.
  """

  @doc """
  A strong ETag for a response body — the quoted form RFC 9110 §8.8.3 requires.
  """
  @spec etag(iodata()) :: String.t()
  def etag(body) do
    digest =
      :sha256
      |> :crypto.hash(body)
      |> binary_part(0, 16)
      |> Base.encode16(case: :lower)

    ~s("#{digest}")
  end

  @doc """
  Whether a request's `If-None-Match` matches `etag`, meaning the client's copy
  is still fresh and the response should be `304`.

  Follows RFC 9110 §13.1.2: `*` matches any existing representation, and a list
  of tags matches if any member does. Weak comparison is used, so `W/"x"` and
  `"x"` match — correct for a `GET`, which is all this endpoint serves.
  """
  @spec fresh?(Plug.Conn.t(), String.t()) :: boolean()
  def fresh?(%Plug.Conn{} = conn, etag) do
    case Plug.Conn.get_req_header(conn, "if-none-match") do
      [] -> false
      [header | _] -> matches?(header, etag)
    end
  end

  defp matches?(header, etag) do
    case String.trim(header) do
      "*" -> true
      value -> value |> String.split(",") |> Enum.any?(&(strip_weak(&1) == strip_weak(etag)))
    end
  end

  defp strip_weak(tag) do
    tag |> String.trim() |> String.replace_prefix(~s(W/), "")
  end

  @doc """
  An IMF-fixdate (RFC 9110 §5.6.7) — the only format an HTTP date may be sent in.
  """
  @spec http_date(DateTime.t()) :: String.t()
  def http_date(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
  end
end
