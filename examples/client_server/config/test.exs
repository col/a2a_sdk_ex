import Config

# This example has no unit test suite of its own, but keep the listener off
# under MIX_ENV=test so a stray `mix test` never binds a port (mirrors
# compliance_server's config/test.exs).
config :client_server, listen: false
