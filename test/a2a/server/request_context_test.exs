defmodule A2A.Server.RequestContextTest do
  use ExUnit.Case, async: true
  alias A2A.Server.RequestContext
  alias A2A.Types.{Message, Part}

  test "user_input/1 concatenates text parts" do
    msg = %Message{
      role: :user,
      parts: [Part.text("hello "), Part.data(%{"x" => 1}), Part.text("world")]
    }

    ctx = %RequestContext{message: msg, task_id: "t", context_id: "c", user: A2A.User.anonymous()}
    assert RequestContext.user_input(ctx) == "hello world"
  end

  test "user_input/1 is empty when there are no text parts" do
    ctx = %RequestContext{message: %Message{role: :user, parts: []}, task_id: "t", context_id: "c"}
    assert RequestContext.user_input(ctx) == ""
  end
end
