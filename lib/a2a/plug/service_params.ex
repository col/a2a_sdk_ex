defmodule A2A.Plug.ServiceParams do
  @moduledoc """
  Validation of the A2A service parameters (specification §3.2.6) that both
  bindings share, run before dispatch so JSON-RPC and REST reject the same
  requests — each rendering the refusal in its own error shape.

  Two parameters are checked:

    * **`A2A-Version`** — the protocol version the client is speaking. §6.3
      requires agents to process a request under the semantics of the requested
      version, "matching `Major.Minor`", and to return `VersionNotSupportedError`
      when that version is not supported. A client may send it as a header or,
      per the same section, as an `A2A-Version` query parameter.

    * **`Content-Type`** — §11.1 mandates `application/json`. The registered
      `application/a2a+json` (§14.1.1) and any other `+json` structured suffix
      are accepted too: this SDK does not emit them, but refusing them would
      reject a conformant client.

  Both checks are **lenient about absence and strict about disagreement**: a
  client that states nothing is taken to mean the version and media type this
  SDK implements, and only a value that actively conflicts is refused. An empty
  `A2A-Version` counts as unstated (the TCK's `VER-SERVER-003` expects a request
  carrying one to succeed).
  """
  alias A2A.Error
  alias Plug.Conn.Query

  # This SDK targets A2A v1.0 only — see ADR-0002.
  @protocol_version "1.0"

  @version_header "a2a-version"
  @version_params ["A2A-Version", "a2a-version"]

  @doc "The `Major.Minor` protocol version this SDK implements."
  @spec protocol_version() :: String.t()
  def protocol_version, do: @protocol_version

  @doc """
  Checks a request's service parameters, returning the `A2A.Error` to render
  instead of dispatching when one of them is unsupported.
  """
  @spec check(Plug.Conn.t()) :: :ok | {:error, Error.t()}
  def check(%Plug.Conn{} = conn) do
    with :ok <- check_version(conn), do: check_content_type(conn)
  end

  defp check_version(conn) do
    case requested_version(conn) do
      nil -> :ok
      version -> compare_version(version)
    end
  end

  # Header first, then the query-parameter form the spec also permits.
  defp requested_version(conn) do
    case Plug.Conn.get_req_header(conn, @version_header) do
      [value | _] -> blank_to_nil(value)
      [] -> version_param(conn)
    end
  end

  defp version_param(%Plug.Conn{query_string: query}) when byte_size(query) > 0 do
    params = Query.decode(query)

    @version_params
    |> Enum.find_value(&Map.get(params, &1))
    |> blank_to_nil()
  end

  defp version_param(_conn), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  # §6.3 matches on Major.Minor, so "1.0.7" is the same protocol as "1.0".
  defp compare_version(version) do
    case major_minor(version) == major_minor(@protocol_version) do
      true ->
        :ok

      false ->
        {:error,
         %Error{
           code: :version_not_supported,
           message: "unsupported A2A protocol version: #{version}",
           data: %{requested_version: version, supported_version: @protocol_version}
         }}
    end
  end

  defp major_minor(version), do: version |> String.split(".") |> Enum.take(2)

  defp check_content_type(conn) do
    case Plug.Conn.get_req_header(conn, "content-type") do
      [] -> :ok
      [value | _] -> compare_media_type(media_type(value))
    end
  end

  # "application/json; charset=utf-8" -> "application/json"
  defp media_type(header) do
    header
    |> String.split(";", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  defp compare_media_type("application/json"), do: :ok

  defp compare_media_type(media_type) do
    case String.ends_with?(media_type, "+json") do
      true ->
        :ok

      false ->
        {:error,
         %Error{
           code: :content_type_not_supported,
           message: "unsupported request content type: #{media_type}",
           data: %{content_type: media_type}
         }}
    end
  end
end
