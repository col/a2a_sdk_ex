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

  test "covered set = the 20 Phase-1+2 messages + 2 enums" do
    assert Coverage.covered() ==
             MapSet.new(~w(
               Message Task TaskStatus Part Artifact TaskStatusUpdateEvent TaskArtifactUpdateEvent
               StreamResponse SendMessageRequest SendMessageResponse SendMessageConfiguration GetTaskRequest
               AgentCard AgentInterface AgentProvider AgentCapabilities AgentExtension AgentSkill
               AgentCardSignature GetExtendedAgentCardRequest
               TaskState Role
             ))
  end

  test "deferred lists exactly the 24 remaining messages with a phase and reason" do
    assert MapSet.size(Coverage.deferred_names()) == 24

    for d <- Coverage.deferred() do
      assert d.phase in 2..4
      assert is_binary(d.reason) and d.reason != ""
    end
  end

  test "partition holds: covered and deferred are disjoint and cover all proto messages" do
    assert MapSet.disjoint?(Coverage.covered_messages(), Coverage.deferred_names())
    # covered messages (excluding the 2 enums) ∪ deferred == all 44 proto messages
    assert MapSet.union(Coverage.covered_messages(), Coverage.deferred_names()) ==
             MapSet.new(@all_proto_messages)
  end
end
