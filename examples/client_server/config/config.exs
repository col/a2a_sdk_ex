import Config

config :client_server, port: 4010, listen: true

import_config "#{config_env()}.exs"
