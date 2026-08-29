defmodule A2ATest do
  use ExUnit.Case, async: true

  test "module is defined" do
    assert Code.ensure_loaded?(A2A)
  end
end
