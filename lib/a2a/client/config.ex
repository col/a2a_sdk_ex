defmodule A2A.Client.Config do
  @moduledoc "Client configuration. Build with `new/1`."
  @type t :: %__MODULE__{
          http_client: module(),
          http_opts: keyword(),
          headers: [{String.t(), String.t()}],
          preferred_transports: [String.t()],
          streaming?: boolean(),
          timeout: timeout(),
          stream_timeout: timeout(),
          protocol_version: String.t()
        }
  defstruct http_client: A2A.Client.HTTP.Req,
            http_opts: [],
            headers: [],
            preferred_transports: [],
            streaming?: true,
            timeout: 30_000,
            stream_timeout: 120_000,
            protocol_version: "1.0"

  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts), do: struct!(__MODULE__, opts)
end
