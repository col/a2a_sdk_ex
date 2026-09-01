defmodule A2A.Client.Error do
  @moduledoc """
  Decodes wire errors into `%A2A.Error{}` — the inverse of
  `A2A.Error.to_jsonrpc/1` and `A2A.Error.to_rest/1`. Both bindings decode to the
  same struct so callers handle errors identically regardless of transport.
  """

  # Reverse of A2A.Error's @errors table. Kept explicit (not reflected) so it is
  # obvious and reviewable; if A2A.Error grows a code, add it here too.
  #
  # -32600/-32700 are not in A2A.Error's @errors table (no atom encodes to
  # them) but are emitted directly by A2A.Plug.JSONRPC for a malformed
  # envelope/unparseable body, so the client still needs to decode them; both
  # fall back to :invalid_params, the closest semantic match. -32603 is shared
  # on encode by both :timeout (http 504) and :internal_error (http 500); on
  # decode that's ambiguous, so it resolves to :internal_error.
  @by_jsonrpc %{
    -32_001 => :task_not_found,
    -32_002 => :task_not_cancelable,
    -32_003 => :push_notification_not_supported,
    -32_004 => :unsupported_operation,
    -32_005 => :content_type_not_supported,
    -32_006 => :invalid_agent_response,
    -32_007 => :extended_agent_card_not_configured,
    -32_008 => :extension_support_required,
    -32_009 => :version_not_supported,
    -32_600 => :invalid_params,
    -32_601 => :method_not_found,
    -32_602 => :invalid_params,
    -32_603 => :internal_error,
    -32_700 => :invalid_params
  }
  @by_reason %{
    "TASK_NOT_FOUND" => :task_not_found,
    "TASK_NOT_CANCELABLE" => :task_not_cancelable,
    "PUSH_NOTIFICATION_NOT_SUPPORTED" => :push_notification_not_supported,
    "UNSUPPORTED_OPERATION" => :unsupported_operation,
    "CONTENT_TYPE_NOT_SUPPORTED" => :content_type_not_supported,
    "INVALID_AGENT_RESPONSE" => :invalid_agent_response,
    "EXTENDED_AGENT_CARD_NOT_CONFIGURED" => :extended_agent_card_not_configured,
    "EXTENSION_SUPPORT_REQUIRED" => :extension_support_required,
    "VERSION_NOT_SUPPORTED" => :version_not_supported
  }

  @spec from_jsonrpc(map()) :: A2A.Error.t()
  def from_jsonrpc(%{"code" => code} = err) do
    message = Map.get(err, "message", "error")
    info = err |> Map.get("data") |> error_info()
    reason = info && info["reason"]

    atom = (reason && @by_reason[reason]) || Map.get(@by_jsonrpc, code, :internal_error)
    %A2A.Error{code: atom, message: message, data: metadata(info)}
  end

  # Fallback for a malformed/nonstandard error object missing "code" entirely.
  def from_jsonrpc(err) when is_map(err),
    do: %A2A.Error{code: :internal_error, message: Map.get(err, "message", "error")}

  @spec from_rest(integer(), map() | binary()) :: A2A.Error.t()
  def from_rest(status, body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} -> from_rest(status, map)
      {:error, _} -> %A2A.Error{code: http_atom(status), message: body}
    end
  end

  def from_rest(status, %{"error" => err}) do
    message = Map.get(err, "message", "error")
    info = err |> Map.get("details") |> error_info()
    reason = info && info["reason"]
    atom = (reason && @by_reason[reason]) || http_atom(status)
    %A2A.Error{code: atom, message: message, data: metadata(info)}
  end

  def from_rest(status, _other), do: %A2A.Error{code: http_atom(status), message: "error"}

  @spec from_transport(term()) :: A2A.Error.t()
  def from_transport(reason),
    do: %A2A.Error{code: :internal_error, message: "transport error", data: reason}

  # The details/data array may carry a google.rpc.ErrorInfo; find it.
  defp error_info(list) when is_list(list),
    do: Enum.find(list, &match?(%{"reason" => _}, &1))

  defp error_info(_), do: nil

  defp metadata(%{"metadata" => m}) when is_map(m), do: m
  defp metadata(_), do: nil

  # Coarse fallback when no A2A reason is present.
  defp http_atom(404), do: :method_not_found
  defp http_atom(409), do: :task_not_cancelable
  defp http_atom(415), do: :content_type_not_supported
  defp http_atom(504), do: :timeout
  defp http_atom(s) when s in 500..599, do: :internal_error
  defp http_atom(_), do: :invalid_params
end
