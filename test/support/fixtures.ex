defmodule A2A.Test.Fixtures do
  @moduledoc """
  One hand-built, non-trivial instance per covered `A2A.Types.*` message.
  Reused by the golden-file tests and by the Tier 2 differential-oracle
  conformance test (`test/a2a/proto_conformance_test.exs`) so both suites
  exercise exactly the same representative data.
  """

  alias A2A.Types.{
    AgentCapabilities,
    AgentCard,
    AgentCardSignature,
    AgentExtension,
    AgentInterface,
    AgentProvider,
    AgentSkill,
    APIKeySecurityScheme,
    Artifact,
    AuthenticationInfo,
    AuthorizationCodeOAuthFlow,
    ClientCredentialsOAuthFlow,
    DeviceCodeOAuthFlow,
    GetExtendedAgentCardRequest,
    GetTaskRequest,
    HTTPAuthSecurityScheme,
    ImplicitOAuthFlow,
    Message,
    MutualTlsSecurityScheme,
    OAuth2SecurityScheme,
    OAuthFlows,
    OpenIdConnectSecurityScheme,
    Part,
    PasswordOAuthFlow,
    SecurityRequirement,
    SendMessageConfiguration,
    SendMessageRequest,
    SendMessageResponse,
    StreamResponse,
    StringList,
    Task,
    TaskArtifactUpdateEvent,
    TaskStatus,
    TaskStatusUpdateEvent
  }

  @doc "Returns `[{module, struct}, ...]`, one instance per covered message."
  @spec all() :: [{module, struct}]
  def all do
    [
      {Message, message()},
      {Part, part()},
      {Artifact, artifact()},
      {TaskStatus, task_status()},
      {Task, task()},
      {TaskStatusUpdateEvent, task_status_update_event()},
      {TaskArtifactUpdateEvent, task_artifact_update_event()},
      {StreamResponse, stream_response()},
      {SendMessageConfiguration, send_message_configuration()},
      {SendMessageRequest, send_message_request()},
      {SendMessageResponse, send_message_response()},
      {GetTaskRequest, get_task_request()},
      {AgentInterface, agent_interface()},
      {AgentProvider, agent_provider()},
      {AgentExtension, agent_extension()},
      {AgentCapabilities, agent_capabilities()},
      {AgentSkill, agent_skill()},
      {AgentCardSignature, agent_card_signature()},
      {AgentCard, agent_card()},
      {GetExtendedAgentCardRequest, get_extended_agent_card_request()},
      {StringList, string_list()},
      {SecurityRequirement, security_requirement()},
      {AuthorizationCodeOAuthFlow, authorization_code_oauth_flow()},
      {ClientCredentialsOAuthFlow, client_credentials_oauth_flow()},
      {ImplicitOAuthFlow, implicit_oauth_flow()},
      {PasswordOAuthFlow, password_oauth_flow()},
      {DeviceCodeOAuthFlow, device_code_oauth_flow()},
      {OAuthFlows, oauth_flows()},
      {APIKeySecurityScheme, api_key_security_scheme()},
      {HTTPAuthSecurityScheme, http_auth_security_scheme()},
      {OAuth2SecurityScheme, oauth2_security_scheme()},
      {OpenIdConnectSecurityScheme, open_id_connect_security_scheme()},
      {MutualTlsSecurityScheme, mutual_tls_security_scheme()},
      {AuthenticationInfo, authentication_info()}
    ]
  end

  def message do
    %Message{
      message_id: "msg-1",
      context_id: "ctx-1",
      task_id: "task-1",
      role: :user,
      parts: [Part.text("hello"), Part.data(%{"n" => 1})],
      metadata: %{"origin" => "test"},
      extensions: ["ext-a"],
      reference_task_ids: ["task-0"]
    }
  end

  def part,
    do: Part.url("https://example.com/file.png", filename: "file.png", media_type: "image/png")

  def artifact do
    %Artifact{
      artifact_id: "art-1",
      name: "result",
      description: "the result artifact",
      parts: [Part.text("done")],
      metadata: %{"score" => 1},
      extensions: ["ext-b"]
    }
  end

  def task_status do
    %TaskStatus{
      state: :completed,
      message: %Message{message_id: "msg-2", role: :agent, parts: [Part.text("ok")]},
      timestamp: DateTime.from_unix!(1_700_000_000)
    }
  end

  def task do
    %Task{
      id: "task-1",
      context_id: "ctx-1",
      status: task_status(),
      artifacts: [artifact()],
      history: [message()],
      metadata: %{"k" => true}
    }
  end

  def task_status_update_event do
    %TaskStatusUpdateEvent{
      task_id: "task-1",
      context_id: "ctx-1",
      status: task_status(),
      metadata: %{"final" => false}
    }
  end

  def task_artifact_update_event do
    %TaskArtifactUpdateEvent{
      task_id: "task-1",
      context_id: "ctx-1",
      artifact: artifact(),
      append: true,
      last_chunk: false,
      metadata: %{"seq" => 2}
    }
  end

  def stream_response, do: StreamResponse.status_update(task_status_update_event())

  def send_message_configuration do
    %SendMessageConfiguration{
      accepted_output_modes: ["text/plain"],
      history_length: 5,
      return_immediately: true
    }
  end

  def send_message_request do
    %SendMessageRequest{
      tenant: "tenant-1",
      message: message(),
      configuration: send_message_configuration(),
      metadata: %{"trace" => "abc"}
    }
  end

  def send_message_response, do: SendMessageResponse.task(task())

  def get_task_request, do: %GetTaskRequest{tenant: "tenant-1", id: "task-1", history_length: 10}

  def agent_interface do
    %AgentInterface{
      url: "https://agent.example.com/a2a",
      protocol_binding: "JSONRPC",
      tenant: "tenant-1",
      protocol_version: "1.0"
    }
  end

  def agent_provider do
    %AgentProvider{url: "https://example.com", organization: "Example Org"}
  end

  def agent_extension do
    %AgentExtension{
      uri: "https://example.com/ext/streaming",
      description: "Streaming support extension",
      required: true,
      params: %{"max_chunk_size" => 1024}
    }
  end

  def agent_capabilities do
    %AgentCapabilities{
      streaming: true,
      push_notifications: false,
      extensions: [agent_extension()],
      extended_agent_card: true
    }
  end

  def agent_skill do
    %AgentSkill{
      id: "skill-1",
      name: "Weather lookup",
      description: "Looks up current weather for a location",
      tags: ["weather", "forecast"],
      examples: ["What's the weather in Boston?"],
      input_modes: ["text/plain"],
      output_modes: ["text/plain", "application/json"]
    }
  end

  def agent_card_signature do
    %AgentCardSignature{
      protected: "eyJhbGciOiJFUzI1NiJ9",
      signature: "MEUCIQDx...",
      header: %{"kid" => "key-1"}
    }
  end

  def agent_card do
    %AgentCard{
      name: "Weather Agent",
      description: "Provides weather forecasts",
      supported_interfaces: [agent_interface()],
      provider: agent_provider(),
      version: "1.0.0",
      documentation_url: "https://example.com/docs",
      capabilities: agent_capabilities(),
      default_input_modes: ["text/plain"],
      default_output_modes: ["text/plain", "application/json"],
      skills: [agent_skill()],
      signatures: [agent_card_signature()],
      icon_url: "https://example.com/icon.png"
    }
  end

  def get_extended_agent_card_request, do: %GetExtendedAgentCardRequest{tenant: "tenant-1"}

  def string_list, do: %StringList{list: ["read", "write"]}

  def security_requirement,
    do: %SecurityRequirement{schemes: %{"oauth" => %StringList{list: ["read", "write"]}}}

  def authorization_code_oauth_flow do
    %AuthorizationCodeOAuthFlow{
      authorization_url: "https://auth.example.com/authorize",
      token_url: "https://auth.example.com/token",
      refresh_url: "https://auth.example.com/refresh",
      scopes: %{"read" => "Read access", "write" => "Write access"},
      pkce_required: true
    }
  end

  def client_credentials_oauth_flow do
    %ClientCredentialsOAuthFlow{
      token_url: "https://auth.example.com/token",
      refresh_url: "https://auth.example.com/refresh",
      scopes: %{"read" => "Read access"}
    }
  end

  def implicit_oauth_flow do
    %ImplicitOAuthFlow{
      authorization_url: "https://auth.example.com/authorize",
      refresh_url: "https://auth.example.com/refresh",
      scopes: %{"read" => "Read access"}
    }
  end

  def password_oauth_flow do
    %PasswordOAuthFlow{
      token_url: "https://auth.example.com/token",
      refresh_url: "https://auth.example.com/refresh",
      scopes: %{"read" => "Read access"}
    }
  end

  def device_code_oauth_flow do
    %DeviceCodeOAuthFlow{
      device_authorization_url: "https://auth.example.com/device",
      token_url: "https://auth.example.com/token",
      refresh_url: "https://auth.example.com/refresh",
      scopes: %{"read" => "Read access"}
    }
  end

  def oauth_flows, do: OAuthFlows.authorization_code(authorization_code_oauth_flow())

  def api_key_security_scheme,
    do: %APIKeySecurityScheme{description: "API key auth", location: "header", name: "X-API-Key"}

  def http_auth_security_scheme,
    do: %HTTPAuthSecurityScheme{description: "Bearer auth", scheme: "Bearer", bearer_format: "JWT"}

  def oauth2_security_scheme do
    %OAuth2SecurityScheme{
      description: "OAuth2 auth",
      flows: oauth_flows(),
      oauth2_metadata_url: "https://auth.example.com/.well-known/oauth-authorization-server"
    }
  end

  def open_id_connect_security_scheme,
    do: %OpenIdConnectSecurityScheme{
      description: "OIDC",
      open_id_connect_url: "https://oidc.example.com/.well-known/openid-configuration"
    }

  def mutual_tls_security_scheme, do: %MutualTlsSecurityScheme{description: "mTLS auth"}

  def authentication_info, do: %AuthenticationInfo{scheme: "Bearer", credentials: "push-token"}
end
