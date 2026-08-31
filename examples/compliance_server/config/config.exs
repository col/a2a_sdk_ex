import Config

# The TCK drives this server over HTTP; `scripts/run_tck.sh` boots it with
# `mix run --no-halt` and polls the agent card on this port.
config :compliance_server, port: 5002, start_http?: true

import_config "#{config_env()}.exs"
