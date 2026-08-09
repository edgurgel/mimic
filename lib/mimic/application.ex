defmodule Mimic.Application do
  use Application
  @moduledoc false

  def start(_, _) do
    children = [
      # Runs module copies off the Coordinator's main loop. async_nolink keeps a
      # failed copy from taking the Coordinator down with it.
      {Task.Supervisor, name: Mimic.TaskSupervisor},
      Mimic.Coordinator,
      {PartitionSupervisor, child_spec: Mimic.Server, name: Mimic.Server.Partitions}
    ]

    # rest_for_one: the Coordinator owns the shared ETS table so let's restart the Servers
    # if something goes wrong with it
    Supervisor.start_link(children, name: Mimic.Supervisor, strategy: :rest_for_one)
  end
end
