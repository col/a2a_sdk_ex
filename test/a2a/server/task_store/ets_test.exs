defmodule A2A.Server.TaskStore.ETSTest do
  use A2A.Server.TaskStore.ConformanceCase

  setup do
    start_supervised!(A2A.Server.TaskStore.ETS)
    :ets.delete_all_objects(A2A.Server.TaskStore.ETS)
    %{store: A2A.Server.TaskStore.ETS}
  end
end
