defmodule A2A.Client.HTTP do
  @moduledoc """
  Behaviour for the client's HTTP layer. `request/1` performs a unary request;
  `stream/1` performs a request whose response `:body` is an `Enumerable.t()` of
  binary chunks, enumerated lazily in the calling process. Inject a custom module
  via `A2A.Client.Config`'s `:http_client`; `A2A.Client.HTTP.Req` is the default.
  """
  @type request :: %{
          method: :get | :post | :delete,
          url: String.t(),
          headers: [{String.t(), String.t()}],
          body: iodata() | nil,
          opts: keyword()
        }
  @type response :: %{
          status: non_neg_integer(),
          headers: [{String.t(), String.t()}],
          body: binary() | Enumerable.t()
        }

  @callback request(request()) :: {:ok, response()} | {:error, term()}
  @callback stream(request()) :: {:ok, response()} | {:error, term()}
end
