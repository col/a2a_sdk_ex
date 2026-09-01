defmodule A2A.Server.ForRequestTest do
  use ExUnit.Case, async: true

  alias A2A.Server
  alias A2A.Scope
  alias A2A.User

  defp base(overrides \\ %{}) do
    Map.merge(
      %Server{
        name: :t,
        executor: A2A.Test.EchoExecutor,
        pubsub: :p,
        scope: Scope.default(),
        user: User.anonymous(),
        owner_resolver: fn _ -> nil end
      },
      overrides
    )
  end

  test "default owner_resolver leaves scope owner nil and sets the user" do
    server = base()
    u = %User{id: "alice", authenticated?: true}
    out = Server.for_request(server, u)

    assert out.user == u
    assert out.scope.owner == nil
  end

  test "a configured owner_resolver derives scope.owner from the user" do
    server = base(%{owner_resolver: fn %User{id: id} -> "owner:" <> id end})
    out = Server.for_request(server, %User{id: "bob", authenticated?: true})

    assert out.scope.owner == "owner:bob"
  end

  test "for_request preserves the tenant already on the base scope" do
    server = base(%{scope: %Scope{tenant: "acme", owner: nil}, owner_resolver: fn _ -> "o" end})
    out = Server.for_request(server, User.anonymous())

    assert out.scope.tenant == "acme"
    assert out.scope.owner == "o"
  end
end
