defmodule A2A.Test.CoverageTest do
  use ExUnit.Case, async: true
  alias A2A.Test.Coverage

  @all_proto_messages ~w(
    SendMessageConfiguration Task TaskStatus Part Message Artifact
    TaskStatusUpdateEvent TaskArtifactUpdateEvent AuthenticationInfo AgentInterface
    AgentCard AgentProvider AgentCapabilities AgentExtension AgentSkill AgentCardSignature
    TaskPushNotificationConfig StringList SecurityRequirement SecurityScheme
    APIKeySecurityScheme HTTPAuthSecurityScheme OAuth2SecurityScheme OpenIdConnectSecurityScheme
    MutualTlsSecurityScheme OAuthFlows AuthorizationCodeOAuthFlow ClientCredentialsOAuthFlow
    ImplicitOAuthFlow PasswordOAuthFlow DeviceCodeOAuthFlow SendMessageRequest GetTaskRequest
    ListTasksRequest ListTasksResponse CancelTaskRequest GetTaskPushNotificationConfigRequest
    DeleteTaskPushNotificationConfigRequest SubscribeToTaskRequest
    ListTaskPushNotificationConfigsRequest GetExtendedAgentCardRequest SendMessageResponse
    StreamResponse ListTaskPushNotificationConfigsResponse
  )

  test "covered set = all 44 Phase-1+2+3+4 messages + 2 enums" do
    assert Coverage.covered() ==
             MapSet.new(~w(
               Message Task TaskStatus Part Artifact TaskStatusUpdateEvent TaskArtifactUpdateEvent
               StreamResponse SendMessageRequest SendMessageResponse SendMessageConfiguration GetTaskRequest
               AgentCard AgentInterface AgentProvider AgentCapabilities AgentExtension AgentSkill
               AgentCardSignature GetExtendedAgentCardRequest
               SecurityRequirement StringList SecurityScheme
               AuthorizationCodeOAuthFlow ClientCredentialsOAuthFlow ImplicitOAuthFlow
               PasswordOAuthFlow DeviceCodeOAuthFlow OAuthFlows
               APIKeySecurityScheme HTTPAuthSecurityScheme OAuth2SecurityScheme
               OpenIdConnectSecurityScheme MutualTlsSecurityScheme AuthenticationInfo
               TaskPushNotificationConfig GetTaskPushNotificationConfigRequest
               DeleteTaskPushNotificationConfigRequest ListTaskPushNotificationConfigsRequest
               ListTaskPushNotificationConfigsResponse
               ListTasksRequest ListTasksResponse CancelTaskRequest SubscribeToTaskRequest
               TaskState Role
             ))
  end

  test "deferred is empty — every proto message has a hand-written struct" do
    assert MapSet.size(Coverage.deferred_names()) == 0
    assert Coverage.deferred() == []
  end

  test "partition holds: covered and deferred are disjoint and cover all proto messages" do
    assert MapSet.disjoint?(Coverage.covered_messages(), Coverage.deferred_names())
    # covered messages (excluding the 2 enums) ∪ deferred == all 44 proto messages
    assert MapSet.union(Coverage.covered_messages(), Coverage.deferred_names()) ==
             MapSet.new(@all_proto_messages)
  end
end
