defmodule A2A.Client.HTTP.Stub do
  @moduledoc false
  # A stub A2A.Client.HTTP. Configure per-test with `put/1`, keyed by {method, path}.
  # Value is either a response map %{status:, headers:, body:} or a fun(request) ->
  # {:ok, resp} | {:error, term}. `stream/1` bodies may be a list of chunks.
  @behaviour A2A.Client.HTTP

  def put(map) when is_map(map), do: Process.put(__MODULE__, map)
  def requests, do: Process.get({__MODULE__, :log}, [])

  @impl true
  def request(req), do: dispatch(req)

  @impl true
  def stream(req), do: dispatch(req)

  defp dispatch(%{method: method, url: url} = req) do
    Process.put({__MODULE__, :log}, [req | requests()])
    path = URI.parse(url).path || "/"
    map = Process.get(__MODULE__, %{})

    case Map.get(map, {method, path}) || Map.get(map, path) do
      nil -> {:error, {:no_stub, method, path}}
      fun when is_function(fun, 1) -> fun.(req)
      %{} = resp -> {:ok, Map.merge(%{status: 200, headers: []}, resp)}
    end
  end
end
