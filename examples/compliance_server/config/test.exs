import Config

# Unit tests cover pure modules only — binding a fixed port would make the
# suite fail whenever a compliance run (or a stray echo server) holds it.
config :compliance_server, start_http?: false
